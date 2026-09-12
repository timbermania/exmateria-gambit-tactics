"""Seed-red tests for the install register (ADR-0202, goal #5's addon → host direction).

An arm that has never been seen to FIRE is indistinguishable from an arm that cannot fire,
and this family has now paid for that four times: `check_addon_portability.py` shipped green
across an entire extraction because it stopped looking, and `check_lattice_ports`,
`check_lattice_doors` and `check_lattice_publish` each had a control go vacuous the day its
burn-down emptied. So every seed below CONSTRUCTS the site — and, where the arm is about a
listed row, the row too. None of them reads a row off the shipped list.

🔴 THE TWO STRIPPER TESTS ARE THE POINT OF THIS FILE. This register's arms need the OPPOSITE
stripper from its three siblings: they scan for symbols and blank string literals, and every
site here lives inside one. `test_strip_noncode_would_read_ZERO_here` proves that by running
the sibling stripper over a seeded body and watching the path vanish — an assertion about the
tree, not about the author's intent. `test_a_shader_include_survives_the_slash_slash_stripper`
pins the other half: `res://` contains `//`, so a shader comment stripper applied first eats
every include, which is how an earlier arm in this family read 0 of 5.

⚠️ THESE SEEDS WRITE INTO THE REAL TREE, so a `check_addon_install.py` run happening
CONCURRENTLY will see them and read one site too many — the same hazard
`test_check_lattice_publish` carries, observed twice there. Inside the suite it is harmless:
`tests/run_all_tests.sh` runs the pre-flight guards serially. Do not read a register count
taken while the suite is running.

Run from tools/:
    uv run python -m unittest test_check_addon_install
"""

from __future__ import annotations

import contextlib
import io
import os
import re
import sys
import unittest
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
PROJECT_DIR = TOOLS_DIR.parent
sys.path.insert(0, str(TOOLS_DIR))

os.chdir(PROJECT_DIR)

import check_addon_install as cai


def _run(burn_down=None):
    buf = io.StringIO()
    original = cai.INSTALL_BURN_DOWN
    if burn_down is not None:
        cai.INSTALL_BURN_DOWN = burn_down
    try:
        with contextlib.redirect_stdout(buf):
            rc = cai.main()
    finally:
        cai.INSTALL_BURN_DOWN = original
        os.chdir(PROJECT_DIR)
    return rc, buf.getvalue()


class SeedFile:
    """A dependency written into the REAL addon, at a REAL scan root.

    A scratch package would prove the code path, which is not the claim: the claim is that
    the register, over THIS addon with THIS tokenizer, scores the seeded line. Removed in
    `__exit__` whether or not the body raised."""

    def __init__(self, rel: str, body: str):
        self.path = PROJECT_DIR / rel
        self.body = body

    def __enter__(self):
        assert not self.path.exists(), f"a previous run leaked {self.path}"
        self.path.write_text(self.body, encoding="utf-8")
        return self.path

    def __exit__(self, *exc):
        self.path.unlink(missing_ok=True)
        return False


SEED_GD = "addons/exmateria_battlefield/_install_seed.gd"
SEED_SHADER = "addons/exmateria_battlefield/_install_seed.gdshaderinc"
SEED_ADDON = "exmateria_battlefield"

ADDONS = sorted(cai.SUBJECTS)


def _seeded(addon: str, key, value) -> dict:
    """A copy of the nested register with one extra row on ONE subject.

    Nested, because `_check_registers()` raises on a register whose keys are not the
    subject names — which is the widening's own failure mode and is asserted below."""
    reg = {a: dict(rows) for a, rows in cai.INSTALL_BURN_DOWN.items()}
    reg[addon][key] = value
    return reg


def _section(out: str, addon: str) -> str:
    """Just this subject's block of the report."""
    start = out.index("SUBJECT %s " % addon)
    nxt = [out.index("SUBJECT %s " % a) for a in ADDONS
           if a != addon and out.index("SUBJECT %s " % a) > start]
    return out[start:min(nxt)] if nxt else out[start:out.rindex("axis B per addon")]


class BothDirectionsFail(unittest.TestCase):
    """The ratchet has two arms and this family has shipped one-armed ratchets before."""

    def test_an_unlisted_asset_reach_is_RED(self):
        body = 'extends Node\n\n\nconst SEEDED := "res://assets/seeded_thing.tres"\n'
        with SeedFile(SEED_GD, body):
            rc, out = _run()
        self.assertIn("INSTALL:", out)
        self.assertIn("res://assets/seeded_thing.tres", out)
        self.assertEqual(rc, 1, out)

    def test_a_stale_row_is_RED(self):
        seeded = _seeded(SEED_ADDON, (SEED_GD, "asset", "res://assets/never_there.tres"),
                         ("A", "#0", "a row that names no reach"))
        rc, out = _run(seeded)
        self.assertIn("STALE INSTALL_BURN_DOWN", out)
        self.assertIn("never_there.tres", out)
        self.assertEqual(rc, 1, out)

    def test_a_row_whose_LAST_site_went_away_is_STALE(self):
        """The shape a CLOSED row actually has — and the shape Class A's three rows will
        take when this pass moves the materials in. The file STAYS and keeps its other
        reaches; only the one target leaves. A scanner that asked "does this file exist?"
        would keep the row alive forever and grade the move as a no-op."""
        body = ('extends Node\n\n\nconst KEPT := "res://assets/kept_thing.tres"\n')
        seeded = _seeded(SEED_ADDON, (SEED_GD, "asset", "res://assets/kept_thing.tres"),
                         ("A", "#0", "the seeded row that survives"))
        seeded[SEED_ADDON][(SEED_GD, "asset", "res://assets/moved_thing.tres")] = (
            "A", "#0", "a row whose reach is gone — this is what SUCCESS looks like")
        with SeedFile(SEED_GD, body):
            rc, out = _run(seeded)
        tail = out.split("STALE INSTALL_BURN_DOWN", 1)
        self.assertEqual(len(tail), 2, out)
        self.assertIn("moved_thing.tres", tail[1])
        self.assertNotIn("kept_thing.tres", tail[1])
        self.assertEqual(rc, 1, out)

    def test_an_unlisted_input_action_is_RED(self):
        body = ('extends Node\n\n\n'
                'const SEEDED_ACTIONS: Array[StringName] = [&"seeded_action"]\n')
        with SeedFile(SEED_GD, body):
            rc, out = _run()
        self.assertIn("seeded_action", out)
        self.assertEqual(rc, 1, out)

    def test_an_unlisted_global_uniform_is_RED(self):
        body = "global uniform float seeded_global;\n"
        with SeedFile(SEED_SHADER, body):
            rc, out = _run()
        self.assertIn("seeded_global", out)
        self.assertEqual(rc, 1, out)


class TheStrippersAreTheOppositeOfTheSiblings(unittest.TestCase):

    def test_strip_noncode_would_read_ZERO_here(self):
        """🔴 The register's central design claim, asserted against the tree.

        `check_lattice_publish` and `check_lattice_doors` both slice
        `touch_matrix.strip_noncode` and scan its output for SYMBOLS. That function BLANKS
        string literals — which is every site this register scores. Reusing it here would
        have produced a guard reporting a clean tree over eleven live edges, and the
        docstring's claim to that effect would have been unfalsifiable prose. This runs it."""
        src = (PROJECT_DIR / "tools" / "touch_matrix.py").read_text()
        fn = re.search(r'^def strip_noncode\(.*?(?=^\S)', src, re.S | re.M)
        self.assertIsNotNone(fn, "touch_matrix.py no longer defines strip_noncode")
        ns = {"re": re}
        exec(fn.group(0), ns)
        body = 'const SEEDED := "res://assets/seeded_thing.tres"\n'
        self.assertNotIn("res://assets/seeded_thing.tres", ns["strip_noncode"](body),
                         "strip_noncode kept the literal; this test no longer proves anything")
        self.assertTrue(any("res://assets/seeded_thing.tres" in lit
                            for _ln, lit in cai._literals(body, "#")),
                        "the register's own tokenizer lost the path")

    def test_a_shader_include_survives_the_slash_slash_stripper(self):
        """🔴 `res://` CONTAINS `//`. A shader comment stripper run before the literals are
        found eats every `#include`, which is how an earlier arm in this family read 0 of 5.
        The seeded file carries a real `//` comment beside the include so the two cannot be
        confused: the comment must go, the include must stay."""
        body = ('// a real comment, which must be stripped\n'
                '#include "res://assets/seeded_include.gdshaderinc"\n')
        lits = cai._literals(body, "//", True)
        self.assertEqual([b for _ln, b in lits], ["res://assets/seeded_include.gdshaderinc"])
        with SeedFile(SEED_SHADER, body):
            rc, out = _run()
        self.assertIn("seeded_include.gdshaderinc", out)
        self.assertEqual(rc, 1, out)

    def test_a_hash_inside_a_literal_does_not_truncate_the_line(self):
        """The defect `check_lattice_publish._code_lines` had to repair after the fact,
        pinned here BEFORE it can be introduced: a `#` opening a format string is not a
        comment, and the code after the closing quote is not lost."""
        body = 'print("# a heading")\nconst SEEDED := "res://assets/after_the_hash.tres"\n'
        self.assertTrue(any("res://assets/after_the_hash.tres" in lit
                            for _ln, lit in cai._literals(body, "#")))


class ProseAndPermittedRootsDoNotScore(unittest.TestCase):
    """The false-positive half. An arm that scores prose is as useless as one that scores
    nothing, and `DoodadLibrary.gd` alone holds four `res://assets/` mentions in docstrings."""

    def test_a_res_path_in_a_COMMENT_does_not_score(self):
        body = ('extends Node\n\n\n'
                '## 1. Maps: res://assets/maps/ (for MAP### files)\n'
                '# and a bare comment naming res://assets/doodads/ too\n')
        with SeedFile(SEED_GD, body):
            rc, out = _run()
        self.assertEqual(rc, 0, out)
        self.assertNotIn("_install_seed.gd", out)

    def test_a_res_path_in_a_TRIPLE_QUOTED_block_does_not_score(self):
        body = ('extends Node\n\n\nfunc _f() -> void:\n'
                '\t"""Prose about res://assets/prose_only.tres\n\n\tand more."""\n\tpass\n')
        with SeedFile(SEED_GD, body):
            rc, out = _run()
        self.assertEqual(rc, 0, out)
        self.assertNotIn("prose_only.tres", out)

    def test_a_path_into_a_PERMITTED_root_does_not_score(self):
        """ADR-0202 dec. 2's target is empty + kernel + port, so a reach into the kernel is
        SATISFIED by the install. `debug/MapGridOverlay.gd:19` is the live instance — a
        `preload` of `exmateria_schema/compositing_key/DepthMode.gd`. A register that flagged
        it has the permitted-root test inverted; one that cannot see it at all is blind to
        `preload` and would also miss `TileCursor.gd:150`, the one parse-time site."""
        body = ('extends Node\n\n\n'
                'const Kernel := preload("res://addons/exmateria_schema/'
                'compositing_key/DepthMode.gd")\n'
                'const Port := preload("res://addons/exmateria_platform/'
                'tunables/TunePort.gd")\n')
        with SeedFile(SEED_GD, body):
            rc, out = _run()
        self.assertEqual(rc, 0, out)
        self.assertNotIn("_install_seed.gd", out)

    def test_a_ui_action_does_not_score(self):
        """Godot ships the `ui_*` family in every project, bare or not."""
        body = 'extends Node\n\n\nconst A: Array[StringName] = [&"ui_accept", &"ui_cancel"]\n'
        with SeedFile(SEED_GD, body):
            rc, out = _run()
        self.assertEqual(rc, 0, out)
        self.assertNotIn("_install_seed.gd", out)


class TheReportingArmCannotRed(unittest.TestCase):

    def test_a_fork_token_is_REPORTED_and_scores_NOTHING(self):
        """ADR-0202 dec. 3: the fork IS the target, so its tokens are conformant. A register
        that scored its own target could never reach 0, and a burn-down that cannot reach 0
        stops being read. Seeded rather than asserted off the shipped six, which would go
        vacuous if the addon ever stopped folding."""
        body = "// seeded\nrender_mode compositor_layer;\n"
        with SeedFile(SEED_SHADER, body):
            rc, out = _run()
        self.assertEqual(rc, 0, out)
        self.assertIn("_install_seed.gdshaderinc", out.split("FORK-ONLY", 1)[1])


class TheShippedListStaysHonest(unittest.TestCase):

    def test_the_register_is_green_on_the_real_tree(self):
        """No unlisted row, no stale row — and the VERDICT matches the list.

        This assertion used to hardcode `"Not a pass"`, the debt-bearing heading. That is a
        control that expires on success: the day the last row was paid the register started
        printing `INSTALL REGISTER CLEAR` and this test went red on the addon getting BETTER,
        aborting the whole suite at pre-flight for everyone. It is the sixth guard in this
        repo to fail that way, so it is written the other way round now: discriminate on
        `INSTALL_BURN_DOWN`, and assert the heading the list ENTAILS. rc 0 means nothing
        unlisted and nothing stale, so on a green tree the burned set IS the list — a
        non-empty list must print the debt heading and an empty one must print CLEAR. Both
        directions are asserted, so a register that printed CLEAR while still carrying rows
        (or the reverse) reds here rather than reading as a pass."""
        rc, out = _run()
        self.assertEqual(rc, 0, out)
        # \U0001f534 PER SUBJECT. Before the widening this read the whole report, which was
        # sound while there was one subject and became a lie the moment there were two:
        # `exmateria_battlefield` prints CLEAR and `exmateria_sprite_rig` prints the debt
        # heading in the SAME run, so either half asserted tree-wide would fail on a
        # correct tree. One addon at 0 and another carrying debt are two readings.
        for addon in ADDONS:
            with self.subTest(addon=addon):
                sec = _section(out, addon)
                if cai.INSTALL_BURN_DOWN[addon]:
                    self.assertIn("Not a pass", sec)
                    self.assertNotIn("INSTALL REGISTER CLEAR", sec)
                else:
                    self.assertIn("INSTALL REGISTER CLEAR", sec)
                    self.assertNotIn("Not a pass", sec)

    def test_a_NON_EMPTY_list_still_prints_the_debt_heading(self):
        """The other arm of the test above, seeded rather than borrowed from the live list.

        `INSTALL_BURN_DOWN` is empty today, so the debt branch of that discriminator would
        be exercised by nothing — and a branch exercised by nothing is how this family keeps
        shipping controls that expire. So construct the state: one seeded reach plus the row
        that names it. rc is 0 (nothing unlisted, nothing stale) and the heading must be the
        debt one, NOT `CLEAR` — a register that called a listed, still-live row clean would
        report ADR-0202's goal as met while it was not."""
        body = 'extends Node\n\n\nconst SEEDED := "res://assets/seeded_debt.tres"\n'
        seeded = _seeded(SEED_ADDON, (SEED_GD, "asset", "res://assets/seeded_debt.tres"),
                         ("A", "#0", "a live row, to prove the debt heading still prints"))
        with SeedFile(SEED_GD, body):
            rc, out = _run(seeded)
        self.assertEqual(rc, 0, out)
        sec = _section(out, SEED_ADDON)
        self.assertIn("Not a pass", sec)
        self.assertNotIn("INSTALL REGISTER CLEAR", sec)

    def test_every_burn_down_row_names_a_real_file_and_a_real_class(self):
        """The one direction a literal list rots silently: a row whose file was renamed
        would go stale and be deleted as if its debt were paid."""
        for addon, rows in cai.INSTALL_BURN_DOWN.items():
            for (rel, kind, target), (klass, owner, why) in rows.items():
                with self.subTest(addon=addon, rel=rel, target=target):
                    self.assertTrue((PROJECT_DIR / rel).is_file(), f"{rel} is not a file")
                    self.assertIn(klass, cai.CLASS_LABEL)
                    self.assertIn(kind, ("asset", "action", "global"))
                    self.assertTrue(owner and why)

    def test_a_global_uniforms_line_number_is_the_DECLARATION_line(self):
        """`\\s` matches a newline, so `^\\s*global` under `re.M` could begin on the blank
        line ABOVE the declaration. This guard's first run reported `psx_dither.gdshaderinc:6`
        for a declaration on 7. A line number quietly off by one is what a reader checks once,
        finds wrong, and then stops trusting the whole register over."""
        body = "\n\nglobal uniform float seeded_global;\n"
        with SeedFile(SEED_SHADER, body):
            _rc, out = _run()
        self.assertIn("_install_seed.gdshaderinc:3", out)

    def test_the_seed_is_what_reddens_it_and_not_the_tree(self):
        """The control for every seed above: none of them leaked."""
        for rel in (SEED_GD, SEED_SHADER):
            self.assertFalse((PROJECT_DIR / rel).exists(), f"a seed test leaked {rel}")


class TheWideningCoversEverySubject(unittest.TestCase):
    """Widening a hardcoded subject into a mapping introduces ways to be silently wrong
    that the old shape could not have. Copied from `test_check_lattice_scene`'s
    `TheRegistersCoverTheMapping`, because it is the same widening and the same holes."""

    def test_every_subject_has_a_row_in_the_register(self):
        self.assertEqual(sorted(cai.INSTALL_BURN_DOWN), ADDONS)

    def test_a_MISSING_row_raises(self):
        """LOUD is not enough on its own — `.get(addon, {})` would make every site UNLISTED,
        which reds. It still raises, so the two failures cannot be confused."""
        reg = {a: dict(cai.INSTALL_BURN_DOWN[a]) for a in ADDONS[1:]}
        with self.assertRaises(SystemExit) as e:
            _run(reg)
        self.assertIn("no row for", str(e.exception))

    def test_an_EXTRA_row_raises(self):
        """The silent direction, and the reason `_check_registers` raises rather than
        reporting: a register naming a subject nobody scans reads as owing nothing."""
        reg = {a: dict(cai.INSTALL_BURN_DOWN[a]) for a in ADDONS}
        reg["exmateria_not_a_subject"] = {}
        with self.assertRaises(SystemExit) as e:
            _run(reg)
        self.assertIn("SUBJECTS does not grade", str(e.exception))

    def test_every_subject_is_actually_SCANNED(self):
        """A subject declared and never walked would print a section full of zeroes that
        reads exactly like a clean addon. Assert each one saw FILES."""
        _rc, out = _run()
        for addon in ADDONS:
            with self.subTest(addon=addon):
                m = re.search(r"— (\d+) scannable file\(s\)", _section(out, addon))
                self.assertIsNotNone(m, out)
                self.assertGreater(int(m.group(1)), 0)

    def test_the_summary_prints_the_SIZE_of_each_register(self):
        """The last line is the one a reader quotes. `check_lattice_scene`'s equivalent
        spent a whole pass printing `0` over an eleven-row register because it rendered an
        rc; this one prints the size, and the size IS the debt."""
        _rc, out = _run()
        tail = out[out.rindex("axis B per addon"):]
        for addon in ADDONS:
            self.assertIn("%s %d" % (addon, len(cai.INSTALL_BURN_DOWN[addon])), tail)
        self.assertIn("NOT the addon being installable", tail)


class ProvidedIsPerSubjectNotPerTree(unittest.TestCase):

    def test_a_name_provided_OUTSIDE_the_target_is_still_a_gap(self):
        """\U0001f534 THE FINDING THE WIDENING EXISTS TO PRODUCE. A name provided by an addon
        that is not in this subject's target must read UNPROVIDED for this subject. A
        tree-wide `provided` set would report an install that does not exist.

        \u26a0\ufe0f IT USED TO BE WITNESSED ON `psx_par`, AND THAT WITNESS WAS THE DEFECT.
        (`psx_par` is the name it carried THEN; today it is `pixel_aspect`, and this
        clause keeps the old spelling because a record of what a name WAS is not a
        name -- ADR-0240 dec. 7.) `psx_par` was provided only by
        `addons/exmateria_battlefield/plugin.gd`, off a
        declaration living in `addons/exmateria_platform/`, so it read provided for the
        battlefield and unprovided for the sprite rig -- which is exactly why the rig could
        not compile its unit shaders. ADR-0220 dec. 2 moved every shader global to the
        addon that DECLARES it, and the port is in both targets, so that divergence is
        gone. Re-seeding it here to keep the assertion would be asserting the bug as a
        requirement.

        The `input/` half still diverges live and is the witness now:
        `exmateria_battlefield` provides eight actions and is absent from the rig's
        target."""
        prov_bf = cai.provided_by_walk(cai.permitted("exmateria_battlefield"))
        prov_rig = cai.provided_by_walk(cai.permitted("exmateria_sprite_rig"))
        self.assertIn("input/cursor_confirm", prov_bf)
        self.assertNotIn("input/cursor_confirm", prov_rig)

    def test_the_port_provides_into_EVERY_subject_and_that_is_dec_2s_mechanism(self):
        """\U0001f534 THE OTHER HALF OF ADR-0220 dec. 2, and the reason the battlefield could
        shed its five without its own arm 3 moving. `exmateria_platform` is in every
        subject's install target, so ONE provide closes the name for all of them; a provide
        keyed to a consumer is O(N addons) and re-opens the row for each new one."""
        port = "addons/exmateria_platform/plugin.gd"
        for addon in ADDONS:
            prov = cai.provided_by_walk(cai.permitted(addon))
            with self.subTest(addon=addon):
                for name in ("pixel_aspect", "unit_stretch", "psx_dither_enabled",
                             "psx_fx_stretch", "psx_cursor_stretch", "psx_camera_angle"):
                    self.assertEqual(prov.get("shader_globals/" + name), port,
                                     "%s must be provided by its DECLARER for every "
                                     "subject (ADR-0220 dec. 1)" % name)

    def test_no_OTHER_plugin_gd_in_the_tree_provides_a_shader_global(self):
        """ADR-0220 dec. 1 composed with arm 4b: only the port declares, the declarer
        provides, therefore only the port provides. A second array holding `pixel_aspect`'s 1.0
        is a second home for a value whose wrongness is a blank screen (ADR-0203 dec. 7),
        and this is the arm that says so -- `check_addon_portability`'s arm 4c cannot,
        because a scan that starts at declarations cannot see a provide that has none
        behind it."""
        for key, provider in cai.provided_anywhere().items():
            if key.startswith("shader_globals/"):
                self.assertEqual(provider, "addons/exmateria_platform/plugin.gd", key)

    def test_the_rigs_two_globals_are_on_its_compile_surface(self):
        """Both arrive through an `#include` into the PORT, which is permitted — so arm 1
        is 0 and arm 3 is 2. The register has to be able to say that."""
        files = cai.addon_files("exmateria_sprite_rig")
        names = {n for _rel, n, _ln in
                 cai.scan_globals(files, cai.permitted("exmateria_sprite_rig"))}
        self.assertIn("pixel_aspect", names)
        self.assertIn("unit_stretch", names)


class AStringNameIsNotAnInputAction(unittest.TestCase):
    """Arm 2 matched every `&"…"`, which was harmless with one subject and produced a
    confident false RED the day a second one had a `has_method(&"job_is_monster")`."""

    def test_a_reflection_argument_does_NOT_score(self):
        body = ('extends Node\n\n\n'
                'func f(n: Node) -> bool:\n'
                '\treturn n.has_method(&"seeded_method_name")\n')
        with SeedFile(SEED_GD, body):
            _rc, out = _run()
        self.assertNotIn("seeded_method_name", out)

    def test_a_REAL_action_on_the_SAME_LINE_still_scores(self):
        """The narrowing is by balanced-paren span, not to end-of-line. If it were the
        latter this literal would vanish with the one before it and the arm would have
        traded a false positive for a silent false negative."""
        body = ('extends Node\n\n\n'
                'func f(n: Node) -> bool:\n'
                '\treturn n.has_method(&"seeded_method_name") and '
                'Input.is_action_pressed(&"seeded_real_action")\n')
        with SeedFile(SEED_GD, body):
            rc, out = _run()
        self.assertNotIn("seeded_method_name", out)
        self.assertIn("seeded_real_action", out)
        self.assertEqual(rc, 1, out)

    def test_the_narrowing_did_NOT_move_the_battlefields_count(self):
        """The control. Every `&"…"` in `exmateria_battlefield` really is an action name,
        so a narrowing that changed its 8 would be cutting into the population."""
        _rc, out = _run()
        self.assertIn("REQUIRES 8 action(s) over 12", _section(out, "exmateria_battlefield"))


if __name__ == "__main__":
    unittest.main()
