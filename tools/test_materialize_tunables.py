"""Unit tests for tools/materialize_tunables.py — the ADR-0068 materialize codemod.

Pure-function tests on synthetic source text and snapshots (no Godot, no disk).
Covers the parsing primitives, literal formatting by type, content-revalidation,
and the four skip paths (non-literal default, AUTOSAVE, stale snapshot, drain).

Run from tools/:
    uv run python -m unittest test_materialize_tunables
"""

from __future__ import annotations

import unittest

import materialize_tunables as m


class ArgSplitTest(unittest.TestCase):
    def test_splits_top_level_commas_only(self):
        args = m.split_top_level_args('8.0, "render.scale", {"min": 1, "max": 9}')
        self.assertEqual([a.token for a in args],
                         ["8.0", '"render.scale"', '{"min": 1, "max": 9}'])

    def test_spans_point_at_the_trimmed_token(self):
        s = 'DEFAULT_Y_LIFT, "render.unit_y_lift"'
        args = m.split_top_level_args(s)
        self.assertEqual(s[args[0].start:args[0].end], "DEFAULT_Y_LIFT")

    def test_comma_inside_string_is_not_a_split(self):
        args = m.split_top_level_args('"a,b", 2')
        self.assertEqual([a.token for a in args], ['"a,b"', "2"])


class LiteralTest(unittest.TestCase):
    def test_recognizes_literals(self):
        for tok in ["2", "-3", "8.0", "true", "false", '"hi"', "Color(1, 0, 0, 1)"]:
            self.assertTrue(m.is_literal(tok), tok)

    def test_rejects_symbols_and_forwarded_params(self):
        for tok in ["DEFAULT_Y_LIFT", "Foo.BAR", "SHARED.x", "default_value"]:
            self.assertFalse(m.is_literal(tok), tok)

    def test_format_by_type(self):
        self.assertEqual(m.format_literal("int", 2.0), "2")
        self.assertEqual(m.format_literal("float", 0.5), "0.5")
        self.assertEqual(m.format_literal("bool", 0.0), "false")
        self.assertEqual(m.format_literal("bool", 1), "true")
        self.assertEqual(m.format_literal("String", "hi"), '"hi"')
        self.assertEqual(m.format_literal("Color", [1.0, 0.0, 0.0, 1.0]),
                         "Color(1.0, 0.0, 0.0, 1.0)")


class LoadAllGdScopeTest(unittest.TestCase):
    """#623 — the walk that feeds the const-slug and class-name maps.

    The one test in this file that touches disk, deliberately: the defect was the
    walk's SCOPE, not any pure function downstream of it, and a synthetic dict of
    file texts cannot express "the walk never looked here". Extraction #3 moved 46
    files out of `src/`, 19+ of them declaring slug consts, and a const the map
    cannot see is a bind site that cannot be revalidated — silently, because a
    codemod reports what it rewrote.
    """

    def test_walk_reaches_the_refactors_own_addons(self):
        texts = m._load_all_gd()
        addon = [k for k in texts if k.startswith("res://addons/")]
        self.assertTrue(addon, "the walk sees no addon .gd at all")

    def test_an_addon_declared_slug_const_resolves(self):
        # PlayerCamera.gd moved to addons/exmateria_battlefield/camera/ at pass 6 and
        # declares 8 slug consts. If the walk cannot reach it, this map is short and
        # every bind site keyed on one of those consts self-skips.
        texts = m._load_all_gd()
        consts = m.build_const_slug_map(texts)
        self.assertIn("DEADZONE_WIDTH_SLUG", consts)
        self.assertTrue(consts["DEADZONE_WIDTH_SLUG"].startswith("camera."))

    def test_the_vendored_sound_addon_is_NOT_walked(self):
        # `addons/exmateria_sound` is another package's source, deployed here by
        # rsync (canonical worktree) or symlink (every other one). Rewriting it from
        # this project is what _walk_roots exists to prevent, so a fix for #623 that
        # scanned `addons/*` wholesale would be a different defect, not a fix.
        texts = m._load_all_gd()
        self.assertEqual(
            [k for k in texts if k.startswith("res://addons/exmateria_sound/")], [])


class LocateTest(unittest.TestCase):
    def test_finds_bind_default_by_inline_slug(self):
        # bind(slug, literal, …) — slug idx 0, literal idx 1.
        text = 'var x = Tune.bind("render.scale", 8.0)\n'
        arg, call = m.locate_call_for_slug(text, 1, "render.scale", set())
        self.assertEqual(call, "Tune.bind")
        self.assertEqual(arg.token, "8.0")

    def test_finds_bind_default_via_const_slug(self):
        # slug arrives as a const name; the const->slug map revalidates it.
        text = 'body = int(Tune.bind(CASTER_SLUG, DEFAULT_SPRITE, _HINT))\n'
        arg, call = m.locate_call_for_slug(text, 1, "effect.caster", {"CASTER_SLUG"})
        self.assertEqual(arg.token, "DEFAULT_SPRITE")

    def test_bind_update_default_is_the_third_arg(self):
        # bind_update(owner, slug, literal, apply, …) — slug idx 1, literal idx 2.
        text = 'Tune.bind_update(owner, "render.lift", 0.05, cb)\n'
        arg, call = m.locate_call_for_slug(text, 1, "render.lift", set())
        self.assertEqual(call, "Tune.bind_update")
        self.assertEqual(arg.token, "0.05")

    def test_finds_bind_default_through_the_port_facade(self):
        # #588 re-pointed every registration line inside `addons/` onto `TunePort`.
        # The façade forwards the singleton's signature verbatim, so the arg indices
        # are unchanged — what changes is the call NAME, and CALLS is a hardcoded list
        # of names that fails QUIET (a missing spelling reads as "no literal here").
        text = 'var x = TunePort.bind("render.scale", 8.0)\n'
        arg, call = m.locate_call_for_slug(text, 1, "render.scale", set())
        self.assertEqual(call, "TunePort.bind")
        self.assertEqual(arg.token, "8.0")

    def test_port_bind_update_default_is_the_third_arg(self):
        text = 'TunePort.bind_update(owner, "render.lift", 0.05, cb)\n'
        arg, call = m.locate_call_for_slug(text, 1, "render.lift", set())
        self.assertEqual(call, "TunePort.bind_update")
        self.assertEqual(arg.token, "0.05")

    def test_port_spelling_does_not_shadow_the_singleton_spelling(self):
        # `Tune.bind` is a prefix of neither `TunePort.bind` nor `Tune.bind_update`
        # under the `\s*\(` suffix the matcher requires — asserted rather than assumed,
        # because a table with four near-identical keys is exactly where a prefix match
        # would attribute the wrong call name and then index the wrong argument.
        text = 'TunePort.bind_update(owner, "render.lift", 0.05, cb)\n'
        self.assertEqual(m.locate_call_for_slug(text, 1, "render.lift", set())[1],
                         "TunePort.bind_update")
        text = 'Tune.bind_update(owner, "render.lift", 0.05, cb)\n'
        self.assertEqual(m.locate_call_for_slug(text, 1, "render.lift", set())[1],
                         "Tune.bind_update")

    def test_of_is_no_longer_recognized(self):
        # `of` was deleted from the API (ADR-0068 R5); its call shape must not match.
        text = 'var x = Tune.of(8.0, "render.scale")\n'
        self.assertIsNone(m.locate_call_for_slug(text, 1, "render.scale", set()))

    def test_returns_none_when_call_absent_at_line(self):
        text = 'const CASTER_SLUG := "effect.caster"\n'
        self.assertIsNone(m.locate_call_for_slug(text, 1, "effect.caster", {"CASTER_SLUG"}))


def _snap(slug, default, type_, persist, file="res://src/A.gd", line=1, locs=None):
    return {slug: {"default": default, "type": type_, "persist": persist,
                   "locations": locs if locs is not None else [{"file": file, "line": line}]}}


class MaterializeTest(unittest.TestCase):
    def test_rewrites_a_literal_bind_default_and_drains_it(self):
        files = {"res://src/A.gd": 'var s = Tune.bind("render.scale", 8.0)\n'}
        overrides = {"render.scale": 9.5}
        snap = _snap("render.scale", 8.0, "float", 1)
        new_files, new_over, rep = m.materialize(overrides, snap, files, {})
        self.assertIn('Tune.bind("render.scale", 9.5)', new_files["res://src/A.gd"])
        self.assertEqual(new_over, {})  # drained
        self.assertEqual(len(rep.rewritten), 1)

    def test_int_type_writes_int_literal_not_float(self):
        files = {"res://src/A.gd": 'Tune.bind("unit.id", 1)\n'}
        new_files, _, _ = m.materialize({"unit.id": 7.0}, _snap("unit.id", 1, "int", 1), files, {})
        self.assertIn('Tune.bind("unit.id", 7)', new_files["res://src/A.gd"])

    def test_rewrites_a_bind_update_literal_default(self):
        # bind_update's literal is the third arg — the sugar's set-once consumer shape.
        files = {"res://src/A.gd": 'Tune.bind_update(o, "render.lift", 0.05, cb)\n'}
        new_files, new_over, rep = m.materialize(
            {"render.lift": 0.2}, _snap("render.lift", 0.05, "float", 1), files, {})
        self.assertIn('Tune.bind_update(o, "render.lift", 0.2, cb)', new_files["res://src/A.gd"])
        self.assertEqual(new_over, {})
        self.assertEqual(len(rep.rewritten), 1)

    def test_skips_non_literal_const_default_and_keeps_override(self):
        files = {"res://src/A.gd": 'Tune.bind_update(o, "render.lift", DEFAULT_Y_LIFT, cb)\n'}
        overrides = {"render.lift": 0.0}
        new_files, new_over, rep = m.materialize(
            overrides, _snap("render.lift", 0.05, "float", 1), files, {})
        self.assertEqual(new_files, files)               # untouched
        self.assertEqual(new_over, overrides)            # NOT drained
        self.assertIn("non-literal default", rep.skipped[0]["reason"])

    def test_skips_autosave_slug(self):
        files = {"res://src/A.gd": 'Tune.bind("scenario.active_id", 5)\n'}
        overrides = {"scenario.active_id": 17}
        new_files, new_over, rep = m.materialize(
            overrides, _snap("scenario.active_id", 5, "int", m.PERSIST_AUTOSAVE), files, {})
        self.assertEqual(new_over, overrides)
        self.assertIn("AUTOSAVE", rep.skipped[0]["reason"])

    def test_skips_when_snapshot_line_is_stale(self):
        # snapshot points at line 3, but the call is not there anymore.
        files = {"res://src/A.gd": 'Tune.bind("render.scale", 8.0)\n\n# unrelated\n'}
        new_files, new_over, rep = m.materialize(
            {"render.scale": 9.5}, _snap("render.scale", 8.0, "float", 1, line=3), files, {})
        self.assertEqual(new_files, files)
        self.assertIn("stale", rep.skipped[0]["reason"])

    def test_skips_slug_absent_from_snapshot(self):
        _, new_over, rep = m.materialize({"ghost.slug": 1}, {}, {}, {})
        self.assertEqual(new_over, {"ghost.slug": 1})
        self.assertIn("not registered", rep.skipped[0]["reason"])


class NonLiteralDefaultTest(unittest.TestCase):
    """Direct-literal-only (ADR-0068 M5, R6): a non-literal default is SKIPPED with a
    warning, never followed to a const declaration. The general const-follower is a
    rejected approach (it inlines over shared consts with many readers, and `.x`-of-a-
    Vector has no single literal to hit — R6 replaces it with the narrow static-var
    follower, built separately under the one-slug↔one-static-var invariant)."""

    def test_skips_a_present_scalar_const_default(self):
        # Even when the const declaration IS in the files, we do NOT chase it: the
        # default position is not a literal, and a plain `const` is not a static var,
        # so the R6 follower declines it too — the slug skips and is not drained.
        src = ('const DEFAULT_Y_LIFT := 0.05\n'
               'func _r():\n'
               '\tTune.bind_update(o, "render.lift", DEFAULT_Y_LIFT, cb)\n')
        files = {"res://src/Unit.gd": src}
        snap = _snap("render.lift", 0.05, "float", 1, file="res://src/Unit.gd", line=3)
        newf, newo, rep = m.materialize({"render.lift": 0.0}, snap, files, {})
        self.assertEqual(newf, files)                    # declaration untouched
        self.assertEqual(newo, {"render.lift": 0.0})     # NOT drained
        self.assertIn("non-literal default", rep.skipped[0]["reason"])

    def test_skips_a_cross_module_vector_component_default(self):
        # `.y` of a static var is a COMPONENT access, not a bare `Class.static_var`
        # ref — the R6 follower requires exactly `Identifier.identifier`, so this skips.
        a = 'func _r():\n\tTune.bind("render.locy", SpriteLayerManager.shared_loc_offset.y)\n'
        b = 'class_name SpriteLayerManager\nstatic var shared_loc_offset := Vector2(27.0, 26.0)\n'
        files = {"res://src/A.gd": a, "res://addons/exmateria_sprite_rig/layers/SpriteLayerManager.gd": b}
        snap = _snap("render.locy", 26.0, "float", 1, file="res://src/A.gd", line=2)
        newf, newo, rep = m.materialize({"render.locy": 27.0}, snap, files, {})
        self.assertEqual(newf, files)                    # nothing rewritten
        self.assertEqual(newo, {"render.locy": 27.0})    # NOT drained
        self.assertIn("non-literal default", rep.skipped[0]["reason"])


class StaticVarFollowerTest(unittest.TestCase):
    """R6: a `Class.static_var` default is followed ONE hop to the static var's
    initializer literal, which is rewritten in place. Safe because one slug ↔ one
    static var (R6 invariant) — exactly one home to hit. Anything that is not a bare
    `Identifier.identifier` resolving to a `static var` declaration still skips."""

    def test_follows_bare_static_var_ref_and_rewrites_initializer(self):
        a = 'func _r():\n\tTune.bind("render.loc_offset", SpriteLayerManager.shared_loc_offset)\n'
        b = ('class_name SpriteLayerManager\n'
             'static var shared_loc_offset := Vector2(27.0, 26.0)\n')
        files = {"res://src/A.gd": a, "res://addons/exmateria_sprite_rig/layers/SpriteLayerManager.gd": b}
        snap = _snap("render.loc_offset", [27.0, 26.0], "Vector2", 1,
                     file="res://src/A.gd", line=2)
        newf, newo, rep = m.materialize(
            {"render.loc_offset": [30.0, 24.0]}, snap, files, {})
        # The call site is untouched; the static var's initializer is rewritten.
        self.assertEqual(newf["res://src/A.gd"], a)
        self.assertIn("static var shared_loc_offset := Vector2(30.0, 24.0)",
                      newf["res://addons/exmateria_sprite_rig/layers/SpriteLayerManager.gd"])
        self.assertEqual(newo, {})                       # drained
        self.assertEqual(len(rep.rewritten), 1)
        self.assertIn("shared_loc_offset", rep.rewritten[0]["via"])

    def test_follows_typed_static_var_declaration(self):
        a = 'func _r():\n\tTune.bind("render.lift", Unit.default_lift)\n'
        b = 'class_name Unit\nstatic var default_lift: float = 0.05\n'
        files = {"res://src/A.gd": a, "res://src/units/Unit.gd": b}
        snap = _snap("render.lift", 0.05, "float", 1, file="res://src/A.gd", line=2)
        newf, newo, rep = m.materialize({"render.lift": 0.2}, snap, files, {})
        self.assertIn("static var default_lift: float = 0.2",
                      newf["res://src/units/Unit.gd"])
        self.assertEqual(newo, {})

    def test_skips_when_static_var_initializer_is_itself_non_literal(self):
        # The one-hop follower does not recurse: a static var whose initializer is
        # another symbol is left for a human.
        a = 'func _r():\n\tTune.bind("render.lift", Unit.default_lift)\n'
        b = 'class_name Unit\nstatic var default_lift := BASE_LIFT\n'
        files = {"res://src/A.gd": a, "res://src/units/Unit.gd": b}
        snap = _snap("render.lift", 0.05, "float", 1, file="res://src/A.gd", line=2)
        newf, newo, rep = m.materialize({"render.lift": 0.2}, snap, files, {})
        self.assertEqual(newf, files)
        self.assertEqual(newo, {"render.lift": 0.2})
        self.assertIn("non-literal default", rep.skipped[0]["reason"])

    def test_skips_when_class_name_is_unknown(self):
        a = 'func _r():\n\tTune.bind("render.lift", Missing.some_var)\n'
        files = {"res://src/A.gd": a}
        snap = _snap("render.lift", 0.05, "float", 1, file="res://src/A.gd", line=2)
        newf, newo, rep = m.materialize({"render.lift": 0.2}, snap, files, {})
        self.assertEqual(newf, files)
        self.assertEqual(newo, {"render.lift": 0.2})
        self.assertIn("non-literal default", rep.skipped[0]["reason"])

    def test_follows_bare_same_file_static_var_owner_equals_binder(self):
        # ADR R1 owner==binder: a class binds its OWN static var, read BARE because
        # GDScript can't qualify a class with its own class_name. The follower resolves
        # the bare token in the bind's own file and rewrites the initializer in place.
        a = ('class_name MapComposer\n'
             'static var _uv_snap_offx_default := 0.0\n'
             'static func _r():\n'
             '\tTune.bind("map.uv_snap_offx", _uv_snap_offx_default)\n')
        files = {"res://src/map/MapComposer.gd": a}
        snap = _snap("map.uv_snap_offx", 0.0, "float", 1,
                     file="res://src/map/MapComposer.gd", line=4)
        newf, newo, rep = m.materialize({"map.uv_snap_offx": 0.5}, snap, files, {})
        self.assertIn("static var _uv_snap_offx_default := 0.5",
                      newf["res://src/map/MapComposer.gd"])
        self.assertEqual(newo, {})                       # drained
        self.assertEqual(len(rep.rewritten), 1)
        self.assertIn("_uv_snap_offx_default", rep.rewritten[0]["via"])

    def test_skips_bare_ident_with_no_static_var_declaration(self):
        # A bare default that is NOT a static var in the bind's file (a forwarded param
        # or a local of the same spelling) has no declaration to follow → skips, so the
        # wrapper hazard the literal-only rule guards against stays handled.
        a = 'func _wrap(default):\n\tTune.bind("render.lift", default)\n'
        files = {"res://src/A.gd": a}
        snap = _snap("render.lift", 0.05, "float", 1, file="res://src/A.gd", line=2)
        newf, newo, rep = m.materialize({"render.lift": 0.2}, snap, files, {})
        self.assertEqual(newf, files)
        self.assertEqual(newo, {"render.lift": 0.2})
        self.assertIn("non-literal default", rep.skipped[0]["reason"])


def _spec_snap(slug, default, type_, meta=None, file="res://src/ui/Win.gd", line=1):
    return {slug: {"default": default, "type": type_, "persist": 1,
                   "meta": meta or {},
                   "locations": [{"file": file, "line": line}]}}


SPEC_SRC = '''var header := UI3Element.new({
\t"id": "picker.window",
\t"rect": Rect2(76, 135, 174, 101),
\t"transition": UI3Element.Transition.BOX_OPEN,
\t"frame": UI3Element.Frame.STRIPE,
\t"clip": UI3Element.Clip.OWN_APERTURE,
\t"fast_open": false,
})
'''

FRAME_META = {"enum": {"NONE": 0, "MENU_TILE": 1, "STRIPE": 2},
              "enum_tokens": "UI3Element.Frame"}


class SpecDictTest(unittest.TestCase):
    """ADR-0088 §5: the UI3Element criteria-spec dict is a recognized literal home —
    the captured location (via the UI3Element.gd skip list) is the caller's
    `new({...})` line; the slug's last component names the dict key."""

    def test_rect2_literal_formats_and_parses(self):
        self.assertTrue(m.is_literal("Rect2(76, 135, 174, 101)"))
        self.assertTrue(m.is_literal("Vector4(6.0, 7.0, 21.0, 17.0)"))
        self.assertEqual(m.format_literal("Rect2", [100, 150, 174, 101]),
                         "Rect2(100.0, 150.0, 174.0, 101.0)")
        self.assertEqual(m.format_literal("Vector4", [6, 7, 21, 17]),
                         "Vector4(6.0, 7.0, 21.0, 17.0)")

    def test_rect_rewrite_inserts_the_authored_home_freeze(self):
        # Rewriting the rect literal with NO explicit authored_home must first pin
        # "authored_home" to the OLD rect position — else the home would ride the pin
        # and content would visually shift back (the two-model-split bug).
        files = {"res://src/ui/Win.gd": SPEC_SRC}
        snap = _spec_snap("picker.window.rect", [76, 135, 174, 101], "Rect2")
        newf, newo, rep = m.materialize(
            {"picker.window.rect": [100, 150, 174, 101]}, snap, files, {})
        out = newf["res://src/ui/Win.gd"]
        self.assertIn('"rect": Rect2(100.0, 150.0, 174.0, 101.0)', out)
        self.assertIn('"authored_home": Vector2(76.0, 135.0)', out)
        self.assertEqual(newo, {})  # drained

    def test_rect_rewrite_never_double_freezes(self):
        src = SPEC_SRC.replace('"fast_open": false,',
                               '"fast_open": false,\n\t"authored_home": Vector2(10.0, 20.0),')
        files = {"res://src/ui/Win.gd": src}
        snap = _spec_snap("picker.window.rect", [76, 135, 174, 101], "Rect2")
        newf, _, _ = m.materialize(
            {"picker.window.rect": [100, 150, 174, 101]}, snap, files, {})
        out = newf["res://src/ui/Win.gd"]
        self.assertEqual(out.count("authored_home"), 1)
        self.assertIn('"authored_home": Vector2(10.0, 20.0)', out)

    def test_enum_field_formats_back_to_its_token(self):
        # An enum-hinted int reverses the recorded hint map to the named-const token
        # (one-hop, unambiguous — R2), which M5's plain-literal rule would skip.
        files = {"res://src/ui/Win.gd": SPEC_SRC}
        snap = _spec_snap("picker.window.frame", 2, "int", meta=FRAME_META)
        newf, newo, rep = m.materialize({"picker.window.frame": 0}, snap, files, {})
        self.assertIn('"frame": UI3Element.Frame.NONE,', newf["res://src/ui/Win.gd"])
        self.assertEqual(newo, {})

    def test_plain_spec_field_rewrites(self):
        files = {"res://src/ui/Win.gd": SPEC_SRC}
        snap = _spec_snap("picker.window.fast_open", False, "bool")
        newf, _, _ = m.materialize({"picker.window.fast_open": 1}, snap, files, {})
        self.assertIn('"fast_open": true,', newf["res://src/ui/Win.gd"])

    def test_captured_line_inside_the_dict_still_finds_the_opener(self):
        # A multi-line construction dict can capture its use-site a few lines BELOW
        # the `.new({` opener (Godot reports a mid-statement line — the picker's
        # comment-rich spec dict does exactly this). The search window must extend
        # BACKWARD too, not just forward from the captured line.
        files = {"res://src/ui/Win.gd": SPEC_SRC}
        snap = _spec_snap("picker.window.rect", [76, 135, 174, 101], "Rect2", line=3)
        newf, newo, rep = m.materialize(
            {"picker.window.rect": [76, 137, 169, 101]}, snap, files, {})
        self.assertIn('"rect": Rect2(76.0, 137.0, 169.0, 101.0)',
                      newf["res://src/ui/Win.gd"])
        self.assertEqual(newo, {})  # drained

    def test_comments_inside_the_dict_do_not_derail_the_parse(self):
        # A GDScript comment inside the construction dict can contain an apostrophe
        # ("the STRIPE crop's") or unbalanced parens — the char scanners must skip
        # comment text (to end-of-line) instead of treating it as quotes/nesting.
        src = SPEC_SRC.replace(
            '\t"rect": Rect2(76, 135, 174, 101),',
            "\t# the STRIPE crop's own 5px body ((unbalanced\n"
            '\t"rect": Rect2(76, 135, 174, 101),')
        files = {"res://src/ui/Win.gd": src}
        snap = _spec_snap("picker.window.rect", [76, 135, 174, 101], "Rect2")
        newf, newo, rep = m.materialize(
            {"picker.window.rect": [76, 137, 169, 101]}, snap, files, {})
        self.assertIn('"rect": Rect2(76.0, 137.0, 169.0, 101.0)',
                      newf["res://src/ui/Win.gd"])
        self.assertEqual(newo, {})  # drained

    def test_spec_with_wrong_id_is_stale(self):
        # Content-revalidation: the dict at the captured line must declare the slug's
        # own id — a different element's spec never gets rewritten.
        files = {"res://src/ui/Win.gd": SPEC_SRC.replace("picker.window", "other.window")}
        snap = _spec_snap("picker.window.rect", [76, 135, 174, 101], "Rect2")
        newf, newo, rep = m.materialize(
            {"picker.window.rect": [100, 150, 174, 101]}, snap, files, {})
        self.assertEqual(newf, files)
        self.assertIn("picker.window.rect", newo)
        self.assertIn("stale", rep.skipped[0]["reason"])

    def test_answer_call_is_a_recognized_home(self):
        # The widget path (ADR-0088 §7): answer("<field>", <literal>) in the widget's
        # own file is the class-scoped one-literal home.
        src = ('func _register_criteria() -> void:\n'
               '\tanswer("id", "uibutton")\n'
               '\tanswer("frame", UI3Element.Frame.MENU_TILE)\n')
        files = {"res://src/ui3/UIButton.gd": src}
        snap = _spec_snap("uibutton.frame", 1, "int", meta=FRAME_META,
                          file="res://src/ui3/UIButton.gd", line=3)
        newf, newo, _ = m.materialize({"uibutton.frame": 2}, snap, files, {})
        self.assertIn('answer("frame", UI3Element.Frame.STRIPE)',
                      newf["res://src/ui3/UIButton.gd"])
        self.assertEqual(newo, {})


if __name__ == "__main__":
    unittest.main()
