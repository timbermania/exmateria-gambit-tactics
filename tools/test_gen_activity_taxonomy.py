"""Unit tests for tools/gen_activity_taxonomy.py.

Covers the validator's rejection paths -- the rules a future YAML edit
must not slip past. Uses stdlib unittest so there's no pytest dep on the
tools venv.

Run from tools/:
    uv run python -m unittest test_gen_activity_taxonomy
"""

from __future__ import annotations

import unittest
from typing import Any

import gen_activity_taxonomy as g


def _row(**overrides: Any) -> dict[str, Any]:
    """A row that passes validation; tests override one field to make it
    fail and assert the right error."""
    base = {
        "unified": "X",
        "logical": "X_LOGICAL",
        "value": 100,
        "display": "X_DISPLAY",
        "routing": "direct",
    }
    base.update(overrides)
    return base


def _doc(*rows: dict[str, Any]) -> dict[str, Any]:
    return {"rows": list(rows)}


class StructuralValidation(unittest.TestCase):

    def test_valid_minimal_row_parses(self):
        tax = g.parse(_doc(_row()))
        self.assertEqual(len(tax.rows), 1)
        self.assertEqual(tax.rows[0].unified, "X")

    def test_top_level_must_have_rows_key(self):
        with self.assertRaisesRegex(g.GenError, "top-level mapping with 'rows:'"):
            g.parse({"items": []})

    def test_row_with_neither_logical_nor_display_is_rejected(self):
        with self.assertRaisesRegex(g.GenError, "at least one of 'logical' / 'display'"):
            g.parse(_doc(_row(logical=None, value=None, display=None)))

    def test_display_only_row_is_accepted(self):
        # No logical -> no value required. routing=none is the metadata
        # routing for "engine doesn't model yet" Display rows.
        tax = g.parse(_doc(_row(logical=None, value=None, routing="none")))
        self.assertEqual(tax.rows[0].logical, None)

    def test_unknown_routing_is_rejected(self):
        with self.assertRaisesRegex(g.GenError, "unknown routing"):
            g.parse(_doc(_row(routing="teleport")))

    def test_malformed_predicate_is_rejected(self):
        with self.assertRaisesRegex(g.GenError, "predicate does not parse"):
            g.parse(_doc(_row(predicate="state.get(")))

    def test_logical_set_without_value_is_rejected(self):
        with self.assertRaisesRegex(g.GenError, "must declare an integer 'value'"):
            g.parse(_doc(_row(value=None)))

    def test_value_set_without_logical_is_rejected(self):
        with self.assertRaisesRegex(g.GenError, "'value' is only meaningful when 'logical' is set"):
            g.parse(_doc(_row(logical=None, value=5)))

    def test_duplicate_unified_name_is_rejected(self):
        with self.assertRaisesRegex(g.GenError, "duplicate unified name"):
            g.parse(_doc(_row(), _row(value=101, logical="Y_LOGICAL", display="Y_DISPLAY")))

    def test_invalid_identifier_in_logical_is_rejected(self):
        with self.assertRaisesRegex(g.GenError, "not a valid identifier"):
            g.parse(_doc(_row(logical="bad-name")))

    def test_invalid_identifier_in_display_is_rejected(self):
        with self.assertRaisesRegex(g.GenError, "not a valid identifier"):
            g.parse(_doc(_row(display="9starts-with-digit")))


class RoutingParams(unittest.TestCase):

    def test_parameterized_requires_method_and_param_field(self):
        with self.assertRaisesRegex(g.GenError, "needs routing_params keys"):
            g.parse(_doc(_row(routing="parameterized")))

    def test_parameterized_with_required_params_parses(self):
        tax = g.parse(_doc(_row(
            routing="parameterized",
            routing_params={"method": "charge_ability", "param_field": "casting_ability_id"},
        )))
        self.assertEqual(tax.rows[0].routing_params["method"], "charge_ability")

    def test_parameterized_with_unexpected_params_is_rejected(self):
        with self.assertRaisesRegex(g.GenError, "unexpected routing_params"):
            g.parse(_doc(_row(
                routing="parameterized",
                routing_params={
                    "method": "charge_ability",
                    "param_field": "casting_ability_id",
                    "extra": "junk",
                },
            )))


class MultiRowLogicalSplits(unittest.TestCase):

    def test_two_rows_sharing_logical_must_share_value(self):
        with self.assertRaisesRegex(g.GenError, "rows disagree on 'value'"):
            g.parse(_doc(
                _row(unified="A", value=2, predicate="x > 0"),
                _row(unified="B", value=3, predicate="x <= 0", display="Y_DISPLAY"),
            ))

    def test_split_rows_must_all_carry_predicate(self):
        with self.assertRaisesRegex(g.GenError, "no predicate"):
            g.parse(_doc(
                _row(unified="A", predicate="x > 0"),
                _row(unified="B", display="Y_DISPLAY"),  # no predicate
            ))

    def test_split_rows_with_matching_value_and_predicates_parses(self):
        tax = g.parse(_doc(
            _row(unified="A", routing="attack_handler", predicate="x <= 0"),
            _row(unified="B", routing="cast_deferred", predicate="x > 0",
                 display="Y_DISPLAY"),
        ))
        self.assertEqual(len(tax.rows_by_logical("X_LOGICAL")), 2)


class DistinctLogicalsCannotShareValue(unittest.TestCase):

    def test_two_distinct_logicals_with_same_value_is_rejected(self):
        with self.assertRaisesRegex(g.GenError, "is claimed by both"):
            g.parse(_doc(
                _row(unified="A"),
                _row(unified="B", logical="Y_LOGICAL", display="Y_DISPLAY"),  # same value=100
            ))


class CommittedYamlIsValid(unittest.TestCase):
    """Belt-and-suspenders: the actual checked-in YAML round-trips through
    load() and gives back the expected row count. Catches accidental drift
    from a schema change that the regeneration step might miss."""

    def test_load_real_yaml(self):
        tax = g.load()
        self.assertEqual(len(tax.rows), 18)
        # 11 LOGICAL_ACTIVITY_* names. Drift collapse landed in PR2 (MOVING->
        # WALKING etc.); the granularity asymmetries (WALKING_TO_CAST,
        # APPROACHING, RETREATING, ACTING-split) stay.
        expected_logicals = {
            "IDLE", "WALKING", "ACTING", "PREEMPTIVE_COUNTER", "SPELL_CHARGING",
            "WALKING_TO_CAST", "DYING", "CELEBRATING", "APPROACHING",
            "AWAITING_IMPACT", "RETREATING",
        }
        self.assertEqual(set(tax.logical_names()), expected_logicals)
        # logical_entries returns 1 entry per unique logical name with the
        # shared value; ACTING (2 rows) shows up once.
        entries = tax.logical_entries()
        self.assertEqual(len(entries), 11)
        # The values are still a DENSE 0..N-1 range, which is the property worth
        # asserting: RETREATING (ADR-0301) was appended at 10 rather than slotted
        # into a gap, so no committed U_STATE value moved.
        self.assertEqual({v for _, v in entries}, set(range(11)))


class TheKernelTargetDidNotChangeTheOtherFive(unittest.TestCase):
    """#740 acceptance criterion 2. The generator gained a sixth target; the
    five it already had must be byte-identical across that change *except* for
    the dispatch shell's Display-member spelling.

    🔴 "THE GENERATOR GAINED A TARGET" AND "THE GENERATOR CHANGED `Battle`" HAVE
    TO BE DISTINGUISHABLE, and eyeballing a diff is not an instrument. These
    three tests are: the first pins four targets against the tree, the second
    proves the fifth changed by exactly one substitution and nothing else, and
    the third proves the new target agrees with the two it duplicates."""

    def setUp(self):
        self.tax = g.load()

    def test_four_targets_are_byte_identical_to_the_tree(self):
        # combat_common.glslinc, GPUConstants.gd, DisplayActivity.gd and the
        # cluster region. If a future edit to any of these emitters lands
        # without a regeneration -- or changes what they emit at all -- this
        # goes red before check_addon_globals or a suite run ever sees it.
        for emitter in (g.emit_glsl, g.emit_gpu_constants,
                        g.emit_display_activity, g.emit_context):
            for path, text in emitter(self.tax):
                with self.subTest(target=path.name):
                    self.assertEqual(
                        text, path.read_text(),
                        f"{path.relative_to(g.ROOT)} is not what the generator "
                        f"emits -- regenerate, or this emitter changed",
                    )

    def test_the_dispatch_shell_changed_by_exactly_one_substitution(self):
        new = g.render_translator(self.tax, g.DISPLAY_QUALIFIER)
        old = g.render_translator(self.tax, g.LEGACY_DISPLAY_QUALIFIER)
        self.assertNotEqual(new, old, "the two spellings must actually differ")
        # The whole claim: swap the qualifier back and you are byte-for-byte at
        # the pre-#740 text. Anything else the rename touched shows up here.
        self.assertEqual(
            new.replace(g.DISPLAY_QUALIFIER, g.LEGACY_DISPLAY_QUALIFIER), old)
        # And the substitution is not vacuous -- four emitted lines carry it
        # (one resolver_variant + three direct), from two sites in the source.
        self.assertEqual(new.count(g.DISPLAY_QUALIFIER), 4)
        self.assertNotIn(g.LEGACY_DISPLAY_QUALIFIER, new)

    def test_the_shipped_translator_carries_the_kernel_spelling(self):
        # The emitted text is only half the claim; the file on disk is the
        # other half, and a generated region nobody regenerated is the failure
        # mode this whole ticket is about.
        text = g.TRANSLATOR_PATH.read_text()
        self.assertIn(g.DISPLAY_QUALIFIER, text)
        self.assertNotIn(g.LEGACY_DISPLAY_QUALIFIER, text)


class TheKernelPublishesBothHalves(unittest.TestCase):
    """#740: `ExMateriaSchema.UnitActivity` carries Display AND Logical, and it
    is not a second source of truth -- it agrees with `Battle`'s emissions
    because it comes from the same rows."""

    def setUp(self):
        self.tax = g.load()
        (self.path, self.text), = g.emit_kernel(self.tax)

    @staticmethod
    def _members(text: str, enum_name: str) -> list[str]:
        body = text.split(f"enum {enum_name} {{", 1)[1].split("}", 1)[0]
        out = []
        for line in body.splitlines():
            line = line.strip().rstrip(",")
            if not line or line.startswith("#"):
                continue
            out.append(line.split("##", 1)[0].strip().rstrip(","))
        return out

    def test_display_half_matches_the_rigs_generated_enum(self):
        kernel = self._members(self.text, "Display")
        (_p, rig_text), = g.emit_display_activity(self.tax)
        rig = self._members(rig_text, "Activity")
        self.assertEqual(kernel, rig)

    def test_logical_half_matches_battles_constants_name_and_value(self):
        kernel = dict(
            m.split(" = ") for m in self._members(self.text, "Logical"))
        kernel = {k: int(v) for k, v in kernel.items()}
        self.assertEqual(kernel, dict(self.tax.logical_entries()))
        # ...and the same numbers the shader and GPUConstants carry.
        (_p, glsl), = g.emit_glsl(self.tax)
        for name, value in kernel.items():
            self.assertIn(f"const int LOGICAL_ACTIVITY_{name} = {value};", glsl)

    def test_the_kernel_member_declares_no_class_name(self):
        # addons/exmateria_schema puts ONE global in a consumer's project and it
        # is the facade (ADR-0212 dec. 1). check_addon_globals pins the burn-down
        # at set(); this says it at the generator, where the regression would be
        # introduced.
        self.assertNotIn("class_name", self.text)
        self.assertTrue(self.text.startswith("extends RefCounted\n"))

    def test_the_rig_member_declares_no_class_name(self):
        # The same invariant as the kernel member above, on the other addon
        # (#746). `DisplayActivity` was the widest global the sprite rig held --
        # 60 reaches over 22 host files -- and it is a GENERATED file, so a
        # hand-strip of the `.gd` is undone by the next `gen_activity_taxonomy.py`
        # run and `--check` goes red days later pointing at the wrong thing.
        # This asserts the emitter, which is where it can actually be kept.
        #
        # 🔴 THE PREDICATE IS A DECLARATION, NOT THE SUBSTRING. `assertNotIn(
        # "class_name", ...)` -- the spelling the kernel half above uses -- fails
        # on the emitter's own COMMENT explaining why there is no `class_name`,
        # so the prose beside the rule would hold the string that breaks it.
        (_p, rig_text), = g.emit_display_activity(self.tax)
        declared = [ln for ln in rig_text.splitlines()
                    if ln.strip().startswith("class_name")]
        self.assertEqual(declared, [])
        self.assertIn("\nextends RefCounted\n", rig_text)

    def test_the_kernel_file_lands_inside_the_addon(self):
        rel = self.path.relative_to(g.ROOT).as_posix()
        self.assertEqual(
            rel, "addons/exmateria_schema/unit_vocabulary/UnitActivity.gd")
        self.assertEqual(self.text, self.path.read_text())


if __name__ == "__main__":
    unittest.main()
