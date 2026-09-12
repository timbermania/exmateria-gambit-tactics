"""Unit tests for tools/gen_gpu_layout.py's comment preservation.

The generator carries trailing `#` comments forward across a regeneration by
name, so the GDScript docs survive even though the shader carries none. Those
names are scoped to their enclosing enum, and these tests are why.

🔴 THE BUG THESE GUARD WAS LATENT ON TRUNK AND HAD NO SYMPTOM UNTIL A SECOND
ENUM REUSED A MEMBER NAME. `preserved_comments` keyed by bare member name, so
when #896 added `ResultField.RESULT` beside the existing
`BattleHeaderField.RESULT`, the two collided: one inherited the other's comment,
the bled comment was scraped back on the next pass, and the generator stopped
converging. `--check` reported STALE immediately after a successful
regeneration — which reads as "somebody forgot to run the generator" and not as
"the generator cannot finish", so it is the kind of failure a session burns an
hour on.

Idempotence is the property worth testing directly: regenerate, regenerate
again, and the second pass must be a no-op. A test that only asserted the
comments were right would pass on pass one and still leave the loop open.

Uses stdlib unittest so there is no pytest dep on the tools venv.

Run from tools/:
    uv run python -m unittest test_gen_gpu_layout
"""

from __future__ import annotations

import unittest

import gen_gpu_layout as g


class PreservedCommentsScoping(unittest.TestCase):
    def test_same_member_name_in_two_enums_does_not_collide(self):
        region = "\n".join(
            [
                "enum BattleHeaderField {",
                "\tTICK = 0,  # battle tick",
                "\tRESULT = 1,  # the battle header's verdict word",
                "}",
                "",
                "enum ResultField {",
                "\tRESULT = 0,  # the result record's verdict",
                "\tTICKS = 1,  # tick this record was written at",
                "}",
            ]
        )
        comments = g.preserved_comments(region)
        self.assertEqual(
            comments["BattleHeaderField.RESULT"], "the battle header's verdict word"
        )
        self.assertEqual(comments["ResultField.RESULT"], "the result record's verdict")

    def test_a_standalone_const_stays_unscoped(self):
        region = "\n".join(
            [
                "const UNIT_SIZE = 102  # ints per unit block",
                "",
                "enum UnitField {",
                "\tHP = 2,  # current hit points",
                "}",
            ]
        )
        comments = g.preserved_comments(region)
        self.assertEqual(comments["UNIT_SIZE"], "ints per unit block")
        self.assertEqual(comments["UnitField.HP"], "current hit points")
        # And NOT under a scope — a const is not inside any enum.
        self.assertNotIn("UnitField.UNIT_SIZE", comments)

    def test_a_member_after_a_closing_brace_is_unscoped_again(self):
        """The closing brace has to clear the scope, or every const emitted
        after the last enum inherits that enum's name and stops matching."""
        region = "\n".join(
            [
                "enum UnitField {",
                "\tHP = 2,  # current hit points",
                "}",
                "",
                "const TURN_METER_FULL = 100  # meter value at a full turn",
            ]
        )
        comments = g.preserved_comments(region)
        self.assertEqual(comments["TURN_METER_FULL"], "meter value at a full turn")


class Idempotence(unittest.TestCase):
    def test_regenerating_the_real_targets_twice_changes_nothing(self):
        """The generator must reach a fixed point on the ACTUAL tree.

        Deliberately run against the real shader and the real GDScript rather
        than a synthetic fixture: the collision that broke this was between two
        enums that both exist, and a fixture would only have found it if
        somebody had already thought to write those two enums into it.
        """
        literals, non_literal = g.parse_shader()
        for target in g.TARGETS:
            path = g.ROOT / target["file"]
            text = path.read_text()
            first = self._regenerate(target, text, literals, non_literal)
            second = self._regenerate(target, first, literals, non_literal)
            self.assertEqual(
                first,
                second,
                f"{target['file']}: a second regeneration changed the file again — "
                "the generator does not converge",
            )

    def test_the_tree_is_not_stale(self):
        """And the committed files already ARE that fixed point.

        This is the same thing `--check` reports, asserted here so a stale tree
        is a named test failure rather than a pre-flight abort that hides
        whatever guard runs after it (#929).
        """
        literals, non_literal = g.parse_shader()
        for target in g.TARGETS:
            path = g.ROOT / target["file"]
            text = path.read_text()
            self.assertEqual(
                text,
                self._regenerate(target, text, literals, non_literal),
                f"{target['file']} is stale — run: uv run python tools/gen_gpu_layout.py",
            )

    @staticmethod
    def _regenerate(target, text, literals, non_literal):
        begin, end = g.BEGIN.strip(), g.END.strip()
        lines = text.splitlines()
        bi = next(i for i, l in enumerate(lines) if l.strip() == begin)
        ei = next(i for i, l in enumerate(lines) if l.strip() == end)
        region = "\n".join(lines[bi : ei + 1])
        comments = g.preserved_comments(region)
        return g.replace_region(
            text, g.emit_region(target, literals, non_literal, comments), target["file"]
        )


class RecordLayout(unittest.TestCase):
    def test_the_result_record_is_generated_not_hand_written(self):
        """`RESULT_SIZE` and the `R_*` offsets must come from the shader.

        They were a GD-only `RESULT_SIZE = 4` opposite a literal `battle_id * 4`
        in stage_victory.glsl, plus a third hand-written copy of the offsets in
        RolloutHarness — one number authored three times. Widening the record
        for #896's value function is exactly what that shape breaks silently.
        """
        literals, _ = g.parse_shader()
        self.assertIn("RESULT_SIZE", literals)
        size = literals["RESULT_SIZE"][0]
        offsets = sorted(v for n, (v, _) in literals.items() if n.startswith("R_"))
        self.assertEqual(
            offsets,
            list(range(size)),
            "the R_* offsets must cover [0, RESULT_SIZE) exactly once — a gap is "
            "an int nothing writes, and an overlap is two fields on one word",
        )

    def test_the_packer_target_emits_the_record(self):
        packer = next(t for t in g.TARGETS if t["file"].endswith("GPUCombatPacker.gd"))
        self.assertIn("RESULT_SIZE", packer["consts"])
        self.assertIn(("ResultField", "R_"), packer["enums"])


if __name__ == "__main__":
    unittest.main()
