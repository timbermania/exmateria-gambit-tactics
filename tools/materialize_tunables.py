"""Materialize tunable overrides back into their code default literals.

The `materialize` codemod of ADR-0068 (decision 8, M1–M6):
drain the tracked staging file `config/tune_overrides.json` back into the code
defaults at each tunable's use-site, producing a reviewable git diff. "Promote
to the real game value" — the code literal reabsorbs the override and becomes the
single source of truth again; the staging file trends back toward empty.

It is deliberately a DEV-ONLY tool: locations come from a registry snapshot the
running game dumps (F3 "Dump tune registry" -> `Tune.dump_registry`), which needs
`get_stack()`, which needs the script debugger.

Design (ADR-0068 M1–M6):
  - Locations are captured at registration and read from the snapshot, NOT
    grepped — so const-slugs resolve for free.
  - Rewrite is LITERAL -> literal only. A non-literal default (a named const, a
    `.x` expression, a wrapper-forwarded parameter) is skipped with a warning and
    left for a human. This single rule makes the tool non-destructive: it can
    never inline a literal over a const or break a wrapper.
  - Each `file:line` is CONTENT-REVALIDATED before it is touched (the recognized
    call for THIS slug must still be there) so a snapshot that went stale after an
    edit skips-and-warns instead of corrupting a random line.
  - AUTOSAVE slugs are skipped (decision 10: the staging file is their home).
  - On a rewrite the slug is drained from the override file. A failed verify
    leaves the diff in place (a red diff is more debuggable than a rollback).

Run from the package dir:
    uv run python tools/materialize_tunables.py            # rewrite + verify
    uv run python tools/materialize_tunables.py --dry-run  # report only
    uv run python tools/materialize_tunables.py --full     # verify via test suite

Tests: uv run python -m unittest test_materialize_tunables
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

import _walk_roots

PKG = Path(__file__).resolve().parent.parent
OVERRIDES = PKG / "config" / "tune_overrides.json"
SNAPSHOT = PKG / "config" / "tune_registry.snapshot.json"

# Tune.Persist enum order (weakest -> strongest). AUTOSAVE slugs never materialize
# (decision 10: the override file is their home, no code literal to bake into).
PERSIST_AUTOSAVE = 2

# Recognized registration calls -> (slug arg index, default arg index). The
# captured location lands on one of these; a wrapper (e.g. Unit._apply_render_tunable)
# lands on its INNER bind line, whose default arg is a forwarded parameter — not a
# literal, so it self-skips. The 4-verb API (ADR-0068 R1–R8): `of` is gone;
# `bind(slug, literal, …)` is slug-first; `bind_update(owner, slug, literal, …)`
# carries the owner ahead of the slug. TuneField.add/build_control keep a panel-side
# literal only for REGISTRANT rows (view rows pass a non-literal → self-skip).
#
# 🔴 THIS TABLE IS THE CODEMOD'S WHOLE SUBJECT, AND IT FAILS QUIET. A registration
# spelling that is not listed here is not reported as unrecognized — `locate_call_for_slug`
# simply finds nothing at the captured line and the slug self-skips, which is
# indistinguishable from "no literal to bake". So a rename that moves call sites onto a
# new spelling MUST land here in the same commit (ADR-0151's companion-change rule).
# `TunePort.*` is that case: #588 re-pointed 26 registration lines in
# `addons/exmateria_battlefield/` and `addons/exmateria_platform/` onto the port façade,
# and every one of them would have gone silently unmaterializable without these two rows.
# The arg indices are identical because the façade forwards the singleton's signature
# verbatim — only `get_value` gained an argument, and `get_value` is not a registration.
CALLS: dict[str, tuple[int, int]] = {
    "Tune.bind": (0, 1),
    "Tune.bind_update": (1, 2),
    "TunePort.bind": (0, 1),
    "TunePort.bind_update": (1, 2),
    "TuneField.add": (2, 3),
    "TuneField.build_control": (0, 1),
}

# How far past the captured line to look for the call's opening paren (tolerates
# minor drift + multi-line calls before declaring the snapshot stale).
WINDOW_LINES = 6

_LITERAL_RE = re.compile(
    r"""^(
        -?\d+\.\d+                          # float
      | -?\d+                               # int
      | true | false                        # bool
      | "(?:[^"\\]|\\.)*"                    # double-quoted string
      | '(?:[^'\\]|\\.)*'                    # single-quoted string
      | (?:Color|Vector2|Vector3|Vector4|Rect2i?)\([^()]*\) # simple constructor literal
    )$""",
    re.VERBOSE,
)

_CONST_SLUG_RE = re.compile(r'const\s+([A-Za-z_][A-Za-z0-9_]*)\s*:?=\s*"([^"]+)"')

_CLASS_NAME_RE = re.compile(r'^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)', re.MULTILINE)

# A bare `Class.member` reference — exactly two dotted identifiers, nothing more
# (so `Foo.bar.x` component access does NOT match: R6 follows one hop only).
_STATIC_VAR_REF_RE = re.compile(r'^([A-Za-z_]\w*)\.([A-Za-z_]\w*)$')

# A single bare identifier — the owner==binder static-var default (a class can't qualify
# its own class_name), resolved only against the bind's own file.
_BARE_IDENT_RE = re.compile(r'^[A-Za-z_]\w*$')


@dataclass
class Arg:
    """A top-level call argument and its char span (trimmed) within the source."""
    token: str
    start: int
    end: int


@dataclass
class Report:
    rewritten: list[dict] = field(default_factory=list)
    skipped: list[dict] = field(default_factory=list)

    def skip(self, slug: str, reason: str, **extra) -> None:
        self.skipped.append({"slug": slug, "reason": reason, **extra})


# --------------------------------------------------------------------------- #
# Pure parsing helpers (unit-tested)
# --------------------------------------------------------------------------- #
def match_paren(text: str, open_pos: int) -> int | None:
    """Index of the `)` matching the `(` at `open_pos`, or None. String-aware so a
    paren inside a quoted arg does not throw off the depth count, and COMMENT-aware
    so an apostrophe or unbalanced paren in a `# …` comment (a multi-line spec dict
    carries them) does not derail the scan."""
    depth = 0
    i = open_pos
    quote = ""
    while i < len(text):
        c = text[i]
        if quote:
            if c == "\\":
                i += 2
                continue
            if c == quote:
                quote = ""
        elif c == "#":
            nl = text.find("\n", i)
            if nl == -1:
                return None
            i = nl
        elif c in "\"'":
            quote = c
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return None


def split_top_level_args(s: str) -> list[Arg]:
    """Split a call's inner-paren text on top-level commas, respecting nesting,
    strings, and `# …` comments (a comma/quote/paren inside a comment must neither
    split a segment nor derail the depth count). Each Arg carries the trimmed token
    and its char span within `s`."""
    args: list[Arg] = []
    depth = 0
    quote = ""
    seg_start = 0
    i = 0

    def push(a: int, b: int) -> None:
        raw = s[a:b]
        lstripped = raw.lstrip()
        start = a + (len(raw) - len(lstripped))
        token = lstripped.rstrip()
        end = start + len(token)
        args.append(Arg(token, start, end))

    while i < len(s):
        c = s[i]
        if quote:
            if c == "\\":
                i += 2
                continue
            if c == quote:
                quote = ""
        elif c == "#":
            nl = s.find("\n", i)
            if nl == -1:
                break
            i = nl
        elif c in "\"'":
            quote = c
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == "," and depth == 0:
            push(seg_start, i)
            seg_start = i + 1
        i += 1
    if s.strip() != "" or args:
        push(seg_start, len(s))
    return args


def is_literal(token: str) -> bool:
    return bool(_LITERAL_RE.match(token.strip()))


def _fmt_float(v: float) -> str:
    return repr(float(v))


def format_literal(type_name: str, value) -> str:
    """Format `value` as a GDScript literal of the snapshot's recorded type. JSON
    collapses numbers to float and Color/Vector to arrays, so the type tag is what
    decides `2` vs `2.0` vs `Color(...)`."""
    if type_name == "int":
        return str(int(round(value)))
    if type_name == "float":
        return _fmt_float(value)
    if type_name == "bool":
        return "true" if value else "false"
    if type_name == "String":
        return json.dumps(value)
    if type_name in ("Color", "Vector2", "Vector3", "Vector4", "Rect2"):
        return "%s(%s)" % (type_name, ", ".join(_fmt_float(c) for c in value))
    raise ValueError(f"unsupported materialize type: {type_name}")


def build_const_slug_map(file_texts: dict[str, str]) -> dict[str, str]:
    """Map every `const NAME := "slug"` to NAME -> slug, so a call passing a
    const-slug can be revalidated against the slug it stands for."""
    out: dict[str, str] = {}
    for text in file_texts.values():
        for m in _CONST_SLUG_RE.finditer(text):
            out[m.group(1)] = m.group(2)
    return out


def build_class_name_map(file_texts: dict[str, str]) -> dict[str, str]:
    """Map every `class_name Foo` to Foo -> its res:// path. Stable across a
    materialize run (rewriting a static var initializer never touches class_name),
    so it is built once and reused as offsets shift underneath it."""
    out: dict[str, str] = {}
    for path, text in file_texts.items():
        cm = _CLASS_NAME_RE.search(text)
        if cm:
            out[cm.group(1)] = path
    return out


def resolve_static_var_default(
    token: str, files: dict[str, str], class_paths: dict[str, str],
    bind_file: str | None = None,
) -> tuple[str, int, int, str] | None:
    """R6 one-hop follower: resolve a static-var default to its initializer char span in
    the CURRENT file text (re-resolved live so a prior rewrite in the same file never
    leaves a stale offset). Two accepted forms, both preserving the one-slug-one-static-var
    invariant:
      - `Class.static_var` — a CROSS-class home (the class declaring `class_name Class`
        holds the var), e.g. `SpriteLayerManager.shared_loc_offset`.
      - a BARE `static_var` resolved in `bind_file` — the ADR R1 owner==binder case: a
        class binds its OWN static var, which GDScript can't qualify with its own
        `class_name`, so the bind reads it bare (e.g. MapComposer). Safe because it only
        resolves if `bind_file` actually declares `static var <name>` — a forwarded param
        or local of the same spelling has no such declaration, so it self-skips (the
        wrapper hazard stays handled).
    Returns (path, start, end, init_token), or None for anything else (component access,
    unknown class, no such static var). The caller still checks `is_literal(init_token)`:
    the follower resolves the home, it does not recurse into a symbolic initializer."""
    var: str | None = None
    path: str | None = None
    mt = _STATIC_VAR_REF_RE.match(token)
    if mt is not None:
        var = mt.group(2)
        path = class_paths.get(mt.group(1))
    elif bind_file is not None and _BARE_IDENT_RE.match(token):
        var = token
        path = bind_file
    if path is None or var is None or path not in files:
        return None
    # `static var NAME [: Type] [:]= <initializer>` — capture the initializer up to
    # end-of-line or an inline comment. Type annotation (if any) is skipped, not kept.
    dm = re.search(
        r'static\s+var\s+' + re.escape(var) + r'\b\s*(?::[^\n=]+)?:?=\s*([^\n#]*)',
        files[path])
    if dm is None:
        return None
    init = dm.group(1).rstrip()
    start = dm.start(1)
    return path, start, start + len(init), init.strip()


def _slug_matches(slug_tok: str, slug: str, slug_consts: set[str]) -> bool:
    if slug_tok in (f'"{slug}"', f"'{slug}'"):
        return True
    return slug_tok.split(".")[-1] in slug_consts


def locate_call_for_slug(
    text: str, line: int, slug: str, slug_consts: set[str]
) -> tuple[Arg, str] | None:
    """Find the recognized registration call for `slug` at/near `line` (1-based).
    Returns (default_arg_with_abs_span, call_name), or None when the call is not
    there — the content-revalidation that makes a stale snapshot safe (M5)."""
    lines = text.split("\n")
    if line < 1 or line > len(lines):
        return None
    # Char offset of the start of each line, so a 1-based line maps to a span.
    offsets = [0]
    for ln in lines:
        offsets.append(offsets[-1] + len(ln) + 1)
    win_lo = offsets[line - 1]
    win_hi = offsets[min(line - 1 + WINDOW_LINES, len(lines))]

    best: tuple[int, Arg, str] | None = None
    for call_name, (slug_idx, default_idx) in CALLS.items():
        for m in re.finditer(re.escape(call_name) + r"\s*\(", text):
            paren = m.end() - 1
            if not (win_lo <= paren < win_hi):
                continue
            close = match_paren(text, paren)
            if close is None:
                continue
            args = split_top_level_args(text[paren + 1 : close])
            if slug_idx >= len(args) or default_idx >= len(args):
                continue
            if not _slug_matches(args[slug_idx].token, slug, slug_consts):
                continue
            d = args[default_idx]
            abs_arg = Arg(d.token, paren + 1 + d.start, paren + 1 + d.end)
            if best is None or paren < best[0]:
                best = (paren, abs_arg, call_name)
    if best is None:
        return None
    return best[1], best[2]


@dataclass
class SpecHit:
    """A located ADR-0088 criteria-spec literal home: the value span for the slug's
    field, plus (for a `.new({...})` construction dict) whether the dict already pins
    an explicit authored_home — the rect-rewrite freeze rule needs to know."""
    arg: Arg
    field: str
    in_spec_dict: bool
    has_authored_home: bool


def _dict_entries(text: str, open_brace: int) -> list[tuple[str, Arg]] | None:
    """The `"key": value` entries of the dict literal opening at `open_brace`, each
    value as an Arg with ABSOLUTE char span. None when the braces don't close.
    A segment may carry LEADING `# …` comment lines (a comment above an entry lands
    in the following segment after the comma split) — they are shed before the key
    match so a commented dict still parses."""
    close = match_paren(text, open_brace)
    if close is None:
        return None
    out: list[tuple[str, Arg]] = []
    for a in split_top_level_args(text[open_brace + 1 : close]):
        tok = a.token
        off = 0
        while True:
            stripped = tok.lstrip()
            lead = len(tok) - len(stripped)
            if not stripped.startswith("#"):
                off += lead
                tok = stripped
                break
            nl = tok.find("\n", lead)
            if nl == -1:
                tok = ""
                break
            off += nl + 1
            tok = tok[nl + 1:]
        km = re.match(r'"([^"]+)"\s*:\s*', tok)
        if km is None:
            continue
        vstart = open_brace + 1 + a.start + off + km.end()
        out.append((km.group(1), Arg(tok[km.end():], vstart, open_brace + 1 + a.end)))
    return out


def locate_spec_entry(text: str, line: int, slug: str) -> SpecHit | None:
    """Find the ADR-0088 criteria-spec home for `slug` at/near `line` — either a
    `.new({...})` construction dict whose "id" entry equals the slug's prefix
    (content-revalidation: another element's spec never matches), or a widget-path
    `answer("<field>", <literal>)` call. The slug's LAST component names the field."""
    prefix, _, field = slug.rpartition(".")
    if field == "":
        return None
    lines = text.split("\n")
    if line < 1 or line > len(lines):
        return None
    offsets = [0]
    for ln in lines:
        offsets.append(offsets[-1] + len(ln) + 1)
    # The window extends BACKWARD as well as forward: a multi-line construction dict
    # captures its use-site at whatever mid-statement line Godot reports, which can
    # sit a few lines below the `.new({` opener. The id-revalidation below keeps the
    # wider window precise (another element's spec never matches).
    win_lo = offsets[max(0, line - 1 - WINDOW_LINES)]
    win_hi = offsets[min(line - 1 + WINDOW_LINES, len(lines))]

    for mo in re.finditer(r"\.new\s*\(\s*\{", text):
        brace = mo.end() - 1
        if not (win_lo <= mo.start() < win_hi):
            continue
        entries = _dict_entries(text, brace)
        if entries is None:
            continue
        by_key = dict(entries)
        id_arg = by_key.get("id")
        if id_arg is None or id_arg.token != f'"{prefix}"':
            continue
        val = by_key.get(field)
        if val is None:
            continue
        return SpecHit(val, field, True, "authored_home" in by_key)

    # The widget path: answer("<field>", <literal>) in the widget's own file — the
    # class id is not on the line, so the field name + captured location revalidate.
    for mo in re.finditer(r"\banswer\s*\(", text):
        paren = mo.end() - 1
        if not (win_lo <= paren < win_hi):
            continue
        close = match_paren(text, paren)
        if close is None:
            continue
        args = split_top_level_args(text[paren + 1 : close])
        if len(args) < 2 or args[0].token != f'"{field}"':
            continue
        d = args[1]
        return SpecHit(Arg(d.token, paren + 1 + d.start, paren + 1 + d.end), field, False, False)
    return None


def _enum_token_literal(meta_hint: dict, value) -> str | None:
    """Reverse an `enum:` hint map to its named-const token (`UI3Element.Frame.STRIPE`)
    — the ADR-0088 §5 enum-token formatting. None when the slug carries no enum hint
    or the value maps to no token."""
    options = meta_hint.get("enum")
    prefix = meta_hint.get("enum_tokens")
    if not options or not prefix:
        return None
    for token, v in options.items():
        if int(v) == int(round(value)):
            return f"{prefix}.{token}"
    return None


def _is_enum_token(token: str, meta_hint: dict) -> bool:
    prefix = meta_hint.get("enum_tokens")
    return bool(prefix) and token.startswith(prefix + ".")


_RECT_ARGS_RE = re.compile(r"Rect2i?\s*\((.*)\)\s*$", re.DOTALL)


def _authored_home_freeze(old_rect_token: str) -> str | None:
    """The `, "authored_home": Vector2(x, y)` insertion for a rect rewrite whose spec
    has no explicit home — pinned to the OLD rect literal's position so content
    authored against it never visually shifts (ADR-0088 §1, the freeze rule)."""
    rm = _RECT_ARGS_RE.match(old_rect_token.strip())
    if rm is None:
        return None
    parts = split_top_level_args(rm.group(1))
    if len(parts) < 2:
        return None
    try:
        x = float(parts[0].token)
        y = float(parts[1].token)
    except ValueError:
        return None
    return ', "authored_home": Vector2(%s, %s)' % (_fmt_float(x), _fmt_float(y))


# --------------------------------------------------------------------------- #
# Materialize (unit-tested against in-memory files)
# --------------------------------------------------------------------------- #
def materialize(
    overrides: dict, snapshot: dict, files: dict[str, str], const_to_slug: dict[str, str],
) -> tuple[dict[str, str], dict, Report]:
    """Core codemod over in-memory files keyed by `res://` path. Returns the
    (possibly) rewritten files, the drained override dict, and a Report."""
    report = Report()
    new_files = dict(files)
    drained: set[str] = set()
    class_paths = build_class_name_map(files)

    for slug in sorted(overrides):
        value = overrides[slug]
        meta = snapshot.get(slug)
        if meta is None:
            report.skip(slug, "not registered in the dumped session — re-dump or by hand")
            continue
        if int(meta.get("persist", 1)) == PERSIST_AUTOSAVE:
            report.skip(slug, "AUTOSAVE — the override file is its home (decision 10)")
            continue
        locations = meta.get("locations", [])
        if not locations:
            report.skip(slug, "no captured use-site location — re-dump")
            continue
        slug_consts = {n for n, s in const_to_slug.items() if s == slug}
        any_rewrite = False
        for loc in locations:
            path = loc["file"]
            line = int(loc["line"])
            text = new_files.get(path)
            if text is None:
                report.skip(slug, f"source not loaded: {path}", file=path, line=line)
                continue
            found = locate_call_for_slug(text, line, slug, slug_consts)
            if found is None:
                # The ADR-0088 criteria-spec home: a `.new({...})` dict (id-revalidated)
                # or a widget answer("<field>", …) call at the captured line.
                spec_hit = locate_spec_entry(text, line, slug)
                if spec_hit is None:
                    report.skip(slug, f"snapshot stale — call not found at {path}:{line}",
                                file=path, line=line)
                    continue
                meta_hint = meta.get("meta", {})
                token_lit = _enum_token_literal(meta_hint, value)
                old_ok = is_literal(spec_hit.arg.token) or _is_enum_token(spec_hit.arg.token, meta_hint)
                if not old_ok:
                    report.skip(slug, f"non-literal spec value ({spec_hit.arg.token}) — by hand",
                                file=path, line=line)
                    continue
                new_lit = token_lit if token_lit is not None else format_literal(meta["type"], value)
                insert = ""
                if spec_hit.field == "rect" and spec_hit.in_spec_dict \
                        and not spec_hit.has_authored_home:
                    # The freeze rule (ADR-0088 §1): pin authored_home to the OLD rect
                    # position before the literal moves, or content shifts back.
                    insert = _authored_home_freeze(spec_hit.arg.token) or ""
                new_files[path] = (text[: spec_hit.arg.start] + new_lit + insert
                                   + text[spec_hit.arg.end :])
                report.rewritten.append({"slug": slug, "file": path, "line": line,
                                         "old": spec_hit.arg.token, "new": new_lit + insert})
                any_rewrite = True
                continue
            default_arg, call_name = found
            if not is_literal(default_arg.token):
                # R6 static-var follower: a `Class.static_var` OR a bare owner-file
                # `static_var` default is chased ONE hop to the var's initializer (safe
                # because one slug ↔ one static var). Any other non-literal — a named
                # const, a `.x` component expression, a wrapper-forwarded param — is left
                # for a human. The general const-follower stays rejected (M5).
                follow = resolve_static_var_default(default_arg.token, new_files, class_paths, bind_file=path)
                if follow is not None and is_literal(follow[3]):
                    fpath, fstart, fend, old_init = follow
                    new_lit = format_literal(meta["type"], value)
                    ftext = new_files[fpath]
                    new_files[fpath] = ftext[:fstart] + new_lit + ftext[fend:]
                    report.rewritten.append(
                        {"slug": slug, "file": fpath, "line": line, "old": old_init,
                         "new": new_lit, "via": f"static var {default_arg.token}"})
                    any_rewrite = True
                    continue
                report.skip(slug, f"non-literal default ({default_arg.token}) — by hand",
                            file=path, line=line, call=call_name)
                continue
            new_lit = format_literal(meta["type"], value)
            new_files[path] = text[: default_arg.start] + new_lit + text[default_arg.end :]
            report.rewritten.append({"slug": slug, "file": path, "line": line,
                                     "old": default_arg.token, "new": new_lit})
            any_rewrite = True
        if any_rewrite:
            drained.add(slug)

    new_overrides = {k: v for k, v in overrides.items() if k not in drained}
    return new_files, new_overrides, report


# --------------------------------------------------------------------------- #
# I/O + CLI
# --------------------------------------------------------------------------- #
def _res_to_fs(res_path: str) -> Path:
    return PKG / res_path[len("res://"):]


def _load_all_gd() -> dict[str, str]:
    """Every `.gd` under `src/` AND under the refactor's own addon roots, keyed by
    res:// path (for the const-slug + class-name maps).

    🔴 `src/` alone stopped describing this tree at extraction #3's loop pass 6, which
    moved 46 files into `addons/exmateria_battlefield/` — 19+ const slug homes among
    them (`PlayerCamera.gd` 8, `MapComposer.gd` 5, `TileCursor.gd` 4). The REWRITE set
    was never at risk (`main()` folds in every use-site file the runtime snapshot names),
    but these two maps are what REVALIDATE a const-name slug argument, and a const
    declared in a file the walk cannot see is a slug that silently fails to resolve —
    quietly, because a codemod reports what it rewrote and a shorter report says nothing
    about a name that went missing (#623). Same hardcoded-directory defect as the five
    ADR-0184 dec. 5 named; this is the sixth.

    The addon list is `_walk_roots.addon_roots()` and NOT a fresh `addons/*` scan, for
    the reason that module's own docstring gives: scanning `addons/` wholesale drags in
    the vendored `addons/exmateria_sound`, which is another package's source and not
    this project's to rewrite. "Which source does this refactor own" already has one
    answer; this reads it rather than re-answering it a fourth time.
    """
    out: dict[str, str] = {}
    for root in [PKG / "src"] + _walk_roots.addon_roots():
        for q in _walk_roots.walk_files(root):
            if q.suffix == ".gd":
                out["res://" + str(q.relative_to(PKG))] = q.read_text(encoding="utf-8")
    return out


def _run_verify(touched: list[str], full: bool) -> bool:
    """Parse-load the touched files (import rebuilds the class cache first); --full
    runs the behavioral suite. Godot is invoked headful, never --headless."""
    subprocess.run(["godot", "--path", str(PKG), "--import", "--quit-after", "2"],
                   cwd=PKG, check=False)
    if full:
        r = subprocess.run(["bash", "tests/run_all_tests.sh"], cwd=PKG)
        return r.returncode == 0
    probe = "extends SceneTree\nfunc _init():\n\tvar bad := 0\n"
    for path in touched:
        probe += f'\tif load("{path}") == null: bad += 1; push_error("parse fail: {path}")\n'
    probe += '\tprint("PARSE_PROBE bad=", bad)\n\tquit(bad)\n'
    probe_path = PKG / "tools" / "_materialize_parse_probe.gd"
    probe_path.write_text(probe, encoding="utf-8")
    try:
        r = subprocess.run(["godot", "--path", str(PKG), "--script",
                            "res://tools/_materialize_parse_probe.gd"],
                           cwd=PKG, capture_output=True, text=True)
        sys.stdout.write(r.stdout)
        sys.stderr.write(r.stderr)
        return "PARSE_PROBE bad=0" in (r.stdout + r.stderr)
    finally:
        probe_path.unlink(missing_ok=True)
        Path(str(probe_path) + ".uid").unlink(missing_ok=True)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dry-run", action="store_true", help="report only; write nothing")
    ap.add_argument("--no-verify", action="store_true", help="skip the parse-load check")
    ap.add_argument("--full", action="store_true", help="verify via tests/run_all_tests.sh")
    args = ap.parse_args(argv)

    if not OVERRIDES.exists():
        print(f"nothing to materialize — {OVERRIDES} does not exist")
        return 0
    if not SNAPSHOT.exists():
        print(f"no snapshot at {SNAPSHOT} — dump the registry in-game (F3) first")
        return 1

    overrides = json.loads(OVERRIDES.read_text())
    snapshot = json.loads(SNAPSHOT.read_text())
    # All of src/ is loaded so the const->slug map can revalidate a const-slug call
    # site regardless of which file declares the slug const.
    all_gd = _load_all_gd()
    for meta in snapshot.values():  # fold in any use-site file outside src/
        for loc in meta.get("locations", []):
            fs = _res_to_fs(loc["file"])
            if loc["file"] not in all_gd and fs.exists():
                all_gd[loc["file"]] = fs.read_text()
    const_to_slug = build_const_slug_map(all_gd)

    new_files, new_overrides, report = materialize(
        overrides, snapshot, all_gd, const_to_slug)

    print("=== materialize ===")
    for r in report.rewritten:
        where = r["via"] if r.get("via") else f"line {r['line']}"
        print(f"  REWRITE {r['slug']}: {r['old']} -> {r['new']}  ({r['file']} — {where})")
    for s in report.skipped:
        print(f"  skip    {s['slug']}: {s['reason']}")
    if not report.rewritten:
        print("  (nothing rewritten)")
        return 0

    touched = sorted({r["file"] for r in report.rewritten})
    if args.dry_run:
        print("\n--dry-run: no files written")
        return 0

    for path in touched:
        _res_to_fs(path).write_text(new_files[path], encoding="utf-8")
    OVERRIDES.write_text(json.dumps(new_overrides, indent="\t", sort_keys=True) + "\n")
    print(f"\nrewrote {len(touched)} file(s); drained "
          f"{len(overrides) - len(new_overrides)} slug(s) from {OVERRIDES.name}")

    if args.no_verify:
        return 0
    if not _run_verify(touched, args.full):
        print("\nVERIFY FAILED — diff left in place. Inspect, or revert with:\n"
              f"  git checkout -- {' '.join(touched)} config/tune_overrides.json")
        return 1
    print("verify OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
