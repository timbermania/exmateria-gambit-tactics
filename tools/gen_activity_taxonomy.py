#!/usr/bin/env python3
"""Generate the Logical/Display activity taxonomy artifacts.

`tools/activity_taxonomy.yaml` is the single source of truth for "what
the engine and the animation layer think a unit is currently doing." It
declares 17 rows; from those this script (re)emits:

  - LOGICAL_ACTIVITY_* constants in `src/gpu/shaders/combat_common.glslinc`
  - LOGICAL_ACTIVITY_* + LOGICAL_ACTIVITY_NAMES in `src/gpu/GPUConstants.gd`
  - DisplayActivity.Activity enum in `addons/exmateria_sprite_rig/state/DisplayActivity.gd`
  - ActivityTranslator dispatch shell in `src/gpu/ActivityTranslator.gd`
  - a rendered Markdown table inside `docs/context/18-sprite-layers.md`
  - BOTH halves as one kernel member in
    `addons/exmateria_schema/unit_vocabulary/UnitActivity.gd`

The sixth target is why the activity rename is a GENERATOR change and not a
`sed` over the tree (ADR-0217 dec. 8, #740). The display half and the logical
half come from the SAME rows and exist only to be translated into each other,
so the kernel publishes both as one vocabulary; `Battle`'s GLSL and
`GPUConstants.gd` keep being emitted exactly as before, which is what leaves
the 227 lines that name `GPUConstants.LOGICAL_ACTIVITY_*` untouched.

PR1 lands the parser + validator first. Emit stages are filled in by
later commits so the diff for each stage stays small and reviewable.

Usage (run from `tools/` so uv picks up the tools venv;
       the generator imports pyyaml):
    cd tools && uv run python gen_activity_taxonomy.py           # rewrite
    cd tools && uv run python gen_activity_taxonomy.py --check   # exit 1 if stale
"""

from __future__ import annotations

import ast
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml

ROOT = Path(__file__).resolve().parent.parent
YAML_PATH = ROOT / "tools" / "activity_taxonomy.yaml"

ACTIVE_ROUTINGS = {
    "direct",
    "visualizer",
    "transient",
    "attack_handler",
    "cast_deferred",
    "parameterized",
    "resolver_variant",
}
METADATA_ROUTINGS = {"none", "animation_lifecycle"}
ALL_ROUTINGS = ACTIVE_ROUTINGS | METADATA_ROUTINGS

# Routing-specific required keys under `routing_params`.
ROUTING_PARAM_REQS: dict[str, set[str]] = {
    "parameterized": {"method", "param_field"},
}


class GenError(Exception):
    pass


@dataclass
class Row:
    unified: str
    logical: str | None
    value: int | None
    display: str | None
    routing: str
    predicate: str | None = None
    routing_params: dict[str, Any] = field(default_factory=dict)
    adr: str | None = None
    notes: str | None = None


@dataclass
class Taxonomy:
    rows: list[Row]

    def logical_names(self) -> list[str]:
        """Unique logical names, preserving first-seen order."""
        seen: dict[str, None] = {}
        for r in self.rows:
            if r.logical is not None and r.logical not in seen:
                seen[r.logical] = None
        return list(seen.keys())

    def logical_entries(self) -> list[tuple[str, int]]:
        """Unique (name, value) pairs sorted by integer value."""
        out: dict[str, int] = {}
        for r in self.rows:
            if r.logical is None or r.logical in out:
                continue
            assert r.value is not None
            out[r.logical] = r.value
        return sorted(out.items(), key=lambda kv: kv[1])

    def display_names(self) -> list[str]:
        """Unique display names, preserving first-seen order."""
        seen: dict[str, None] = {}
        for r in self.rows:
            if r.display is not None and r.display not in seen:
                seen[r.display] = None
        return list(seen.keys())

    def rows_by_logical(self, name: str) -> list[Row]:
        return [r for r in self.rows if r.logical == name]


def load(path: Path = YAML_PATH) -> Taxonomy:
    return parse(yaml.safe_load(path.read_text()), source=path.name)


def parse(raw: Any, source: str = "<input>") -> Taxonomy:
    if not isinstance(raw, dict) or "rows" not in raw:
        raise GenError(f"{source}: top-level mapping with 'rows:' key required")
    rows: list[Row] = []
    seen_unified: set[str] = set()
    for i, item in enumerate(raw["rows"]):
        if not isinstance(item, dict):
            raise GenError(f"row {i}: not a mapping")
        unified = item.get("unified")
        if not isinstance(unified, str) or not unified:
            raise GenError(f"row {i}: 'unified' must be a non-empty string")
        if unified in seen_unified:
            raise GenError(f"row {i}: duplicate unified name {unified!r}")
        seen_unified.add(unified)
        row = Row(
            unified=unified,
            logical=item.get("logical"),
            value=item.get("value"),
            display=item.get("display"),
            routing=item.get("routing"),
            predicate=item.get("predicate"),
            routing_params=item.get("routing_params") or {},
            adr=item.get("adr"),
            notes=item.get("notes"),
        )
        validate_row(row, i)
        rows.append(row)
    tax = Taxonomy(rows=rows)
    validate_taxonomy(tax)
    return tax


def validate_row(r: Row, idx: int) -> None:
    if r.logical is None and r.display is None:
        raise GenError(
            f"row {idx} ({r.unified}): at least one of 'logical' / 'display' must be set"
        )
    if r.logical is not None and not isinstance(r.value, int):
        raise GenError(
            f"row {idx} ({r.unified}): rows with 'logical' set must declare an integer 'value'"
        )
    if r.logical is None and r.value is not None:
        raise GenError(
            f"row {idx} ({r.unified}): 'value' is only meaningful when 'logical' is set"
        )
    if r.routing not in ALL_ROUTINGS:
        raise GenError(
            f"row {idx} ({r.unified}): unknown routing {r.routing!r}; "
            f"valid: {sorted(ALL_ROUTINGS)}"
        )
    if r.logical is not None and not _is_identifier(r.logical):
        raise GenError(f"row {idx} ({r.unified}): logical {r.logical!r} is not a valid identifier")
    if r.display is not None and not _is_identifier(r.display):
        raise GenError(f"row {idx} ({r.unified}): display {r.display!r} is not a valid identifier")
    if r.predicate is not None:
        try:
            ast.parse(r.predicate, mode="eval")
        except SyntaxError as e:
            raise GenError(
                f"row {idx} ({r.unified}): predicate does not parse as a Python expression: {e}"
            ) from e
    required = ROUTING_PARAM_REQS.get(r.routing, set())
    missing = required - set(r.routing_params.keys())
    if missing:
        raise GenError(
            f"row {idx} ({r.unified}): routing {r.routing!r} needs routing_params keys "
            f"{sorted(missing)} (got {sorted(r.routing_params.keys())})"
        )
    extras = set(r.routing_params.keys()) - required
    if extras and r.routing in ROUTING_PARAM_REQS:
        raise GenError(
            f"row {idx} ({r.unified}): routing {r.routing!r} got unexpected routing_params "
            f"keys {sorted(extras)}"
        )


def validate_taxonomy(tax: Taxonomy) -> None:
    by_logical: dict[str, list[Row]] = {}
    for r in tax.rows:
        if r.logical is None:
            continue
        by_logical.setdefault(r.logical, []).append(r)
    for name, rows in by_logical.items():
        # Rows that share a logical must agree on the integer value.
        values = {r.value for r in rows}
        if len(values) > 1:
            raise GenError(
                f"logical {name!r}: rows disagree on 'value' ({sorted(values)}); "
                f"rows: {[r.unified for r in rows]}"
            )
        # Multi-row logical splits must carry a predicate on every row so the
        # generated dispatch shell can pick the right branch.
        if len(rows) > 1:
            missing = [r.unified for r in rows if r.predicate is None]
            if missing:
                raise GenError(
                    f"logical {name!r} is split across {len(rows)} rows but "
                    f"these rows have no predicate: {missing}"
                )
    # Values must be unique across distinct logical names (no two different
    # logical activities sharing one shader value).
    value_to_logical: dict[int, str] = {}
    for name, rows in by_logical.items():
        v = rows[0].value
        assert v is not None  # validate_row ensures this
        if v in value_to_logical and value_to_logical[v] != name:
            raise GenError(
                f"value {v} is claimed by both {value_to_logical[v]!r} and {name!r}"
            )
        value_to_logical[v] = name


def _is_identifier(s: str) -> bool:
    return s.isidentifier() and not s.startswith("_")


# ---------------------------------------------------------------------------
# Emitters. Each returns a list of (path, new_text) for files it rewrites.
# All emitters use BEGIN/END marker pairs; the markers must already exist in
# the target file. The comment-prefix differs per file type so each emitter
# carries its own markers + header.
# ---------------------------------------------------------------------------

SHADER_PATH = ROOT / "src" / "gpu" / "shaders" / "combat_common.glslinc"
GLSL_BEGIN = "// === BEGIN GENERATED: logical-activity (tools/gen_activity_taxonomy.py) ==="
GLSL_END = "// === END GENERATED ==="

GPU_CONSTANTS_PATH = ROOT / "src" / "gpu" / "GPUConstants.gd"
GD_BEGIN = "# === BEGIN GENERATED: logical-activity (tools/gen_activity_taxonomy.py) ==="
GD_END = "# === END GENERATED ==="

# #744 moved the emitted file into the addon. This constant is an OUTPUT path, and
# line ~589 does `path.parent.mkdir(parents=True, exist_ok=True)` before writing:
# left stale, `--check` is LOUD (it lists the file as STALE and exits 1) but the
# remedy it prints is silently wrong -- the regenerate would RE-CREATE `src/animation/`
# and drop a resurrected DisplayActivity.gd into it that nothing loads, while the
# addon's real one drifts. A loud guard with a wrong fix is worth naming.
DISPLAY_ACTIVITY_PATH = ROOT / "addons" / "exmateria_sprite_rig" / "state" / "DisplayActivity.gd"

KERNEL_PATH = (
    ROOT / "addons" / "exmateria_schema" / "unit_vocabulary" / "UnitActivity.gd"
)

# How the dispatch shell spells a Display member when it writes one into a host
# file. ADR-0217 dec. 8 moves the vocabulary to the kernel, so this is the ONE
# string the rename turns over.
#
# 🔴 FULLY QUALIFIED, DELIBERATELY, RATHER THAN THROUGH AN ALIAS. ADR-0211
# dec. 4's alias contract is for HAND-WRITTEN call sites; a generated region that
# resolved through a hand-written `const` in its host would break the moment
# someone tidied that line away, and nothing would be red until the next
# regeneration — the same *green because the instrument stopped looking* shape
# dec. 13 is about. `ExMateriaSchema` is an engine-global `class_name`, so the
# emitted text needs nothing from the file it lands in.
DISPLAY_QUALIFIER = "ExMateriaSchema.UnitActivity.Display."

# The spelling this generator emitted before #740. It is dead as an output and
# live as an INSTRUMENT: `test_gen_activity_taxonomy` renders the dispatch shell
# with each qualifier and asserts the two texts differ by nothing but this
# substring, which is how "the generator gained a target" stays distinguishable
# from "the generator changed `Battle`" (#740 acceptance criterion 2).
LEGACY_DISPLAY_QUALIFIER = "DisplayActivity.Activity."

TRANSLATOR_PATH = ROOT / "src" / "gpu" / "ActivityTranslator.gd"
TRANSLATE_BEGIN = "# === BEGIN GENERATED: logical-activity-translate (tools/gen_activity_taxonomy.py) ==="
TRANSLATE_END = "# === END GENERATED ==="

# 🔴 The destination MOVED, it did not go stale. `2fb29d580` split the 9,001-line
# vocabulary into 37 cluster files behind an index, and this generated region moved
# with the prose it documents. `CONTEXT.md` is now itself generated (by
# `tools/gen_context_index.py`) and hosts no generated region of its own, so a
# BEGIN-marker-not-found here reads as "run the generator" while the generator is
# the thing that cannot find its destination — see #696.
CONTEXT_PATH = ROOT / "docs" / "context" / "18-sprite-layers.md"
CONTEXT_BEGIN = "<!-- === BEGIN GENERATED: activity-taxonomy (tools/gen_activity_taxonomy.py) === -->"
CONTEXT_END = "<!-- === END GENERATED === -->"


def _replace_region(text: str, begin: str, end: str, new_body: str, path: Path) -> str:
    """Replace the region delimited by `begin` and the FIRST `end` that
    follows it. Files may host multiple generated regions sharing the
    generic '=== END GENERATED ===' marker, so the search for the end has
    to be anchored after the begin."""
    lines = text.splitlines()
    bi = next((i for i, l in enumerate(lines) if l.strip() == begin.strip()), None)
    if bi is None:
        raise GenError(
            f"{path}: BEGIN marker not found (expected '{begin.strip()}')"
        )
    ei = next(
        (i for i, l in enumerate(lines[bi + 1:], start=bi + 1) if l.strip() == end.strip()),
        None,
    )
    if ei is None:
        raise GenError(
            f"{path}: END marker not found after BEGIN at line {bi + 1} "
            f"(expected '{end.strip()}')"
        )
    new_lines = [begin, *new_body.splitlines(), end]
    return "\n".join(lines[:bi] + new_lines + lines[ei + 1:]) + "\n"


def emit_glsl(tax: Taxonomy) -> list[tuple[Path, str]]:
    body_lines = [
        "// Source of truth: tools/activity_taxonomy.yaml",
        "// Names/values are generated - DO NOT edit them here.",
        "// Regenerate: (cd tools && uv run python gen_activity_taxonomy.py)",
        "",
    ]
    for name, value in tax.logical_entries():
        body_lines.append(f"const int LOGICAL_ACTIVITY_{name} = {value};")
    body = "\n".join(body_lines)

    text = SHADER_PATH.read_text()
    new_text = _replace_region(text, GLSL_BEGIN, GLSL_END, body, SHADER_PATH)
    return [(SHADER_PATH, new_text)]


def emit_gpu_constants(tax: Taxonomy) -> list[tuple[Path, str]]:
    entries = tax.logical_entries()
    body_lines = [
        "# Source of truth: tools/activity_taxonomy.yaml",
        "# Names/values are generated - DO NOT edit them here.",
        "# Regenerate: (cd tools && uv run python gen_activity_taxonomy.py)",
        "",
    ]
    for name, value in entries:
        body_lines.append(f"const LOGICAL_ACTIVITY_{name} = {value}")
    body_lines.append("")
    names_in_value_order = ", ".join(f'"{name}"' for name, _ in entries)
    body_lines.append(f"const LOGICAL_ACTIVITY_NAMES = [{names_in_value_order}]")
    body = "\n".join(body_lines)

    text = GPU_CONSTANTS_PATH.read_text()
    new_text = _replace_region(text, GD_BEGIN, GD_END, body, GPU_CONSTANTS_PATH)
    return [(GPU_CONSTANTS_PATH, new_text)]


def emit_display_activity(tax: Taxonomy) -> list[tuple[Path, str]]:
    """DisplayActivity.gd is a fully-generated file (no hand-edited regions),
    so the whole file is regenerated each run. Display enum values are
    assigned by declaration order, which follows first-occurrence in the
    YAML rows. Reference Display members by NAME, not by their int value
    -- the int values are not a stable contract."""
    display_names = tax.display_names()
    lines = [
        "# THIS FILE IS GENERATED -- DO NOT EDIT.",
        "# Source of truth: tools/activity_taxonomy.yaml",
        "# Regenerate: (cd tools && uv run python gen_activity_taxonomy.py)",
        "#",
        "# Reference enum members by name (DisplayActivity.Activity.IDLE), not by",
        "# integer value -- the values are declaration-order and not a contract.",
        "#",
        "# NO `class_name` (#746, ADR-0212 dec. 1). addons/exmateria_sprite_rig puts",
        "# exactly ONE global in a consumer's project and it is the facade, so this",
        "# enum is reached as `ExMateriaSpriteRig.DisplayActivity.Activity.*` -- or,",
        "# in the 22 host files that alias it, spelled exactly as it was before.",
        "# Said HERE, at the generator, because that is where the regression would",
        "# be reintroduced: a hand-fix to the .gd is overwritten by the next run.",
        "extends RefCounted",
        "",
        "enum Activity {",
    ]
    for name in display_names:
        lines.append(f"\t{name},")
    lines.append("}")
    return [(DISPLAY_ACTIVITY_PATH, "\n".join(lines) + "\n")]


def _routing_call(row: Row, indent: str, qualifier: str = DISPLAY_QUALIFIER) -> str:
    """Render a single `_translate_<routing>(...)` call line for the given row.
    Metadata routings (none, animation_lifecycle) emit no dispatch code.

    `qualifier` is how a Display member gets spelled in the emitted text. It is a
    parameter and not a hardcoded string for one reason: it is the only thing
    #740 changed about `Battle`'s dispatch shell, and a parameter is what lets a
    test render both spellings from the same rows and prove that."""
    r = row.routing
    clear = "true" if row.routing_params.get("clear_ability_id") else "false"
    if r == "direct":
        return (
            f"{indent}_translate_direct(unit, "
            f"{qualifier}{row.display}, {clear})"
        )
    if r == "visualizer":
        return f"{indent}_translate_visualizer(unit, state)"
    if r == "transient":
        return f"{indent}_translate_transient(unit, state)"
    if r == "attack_handler":
        return f"{indent}_translate_attack_handler(unit, state, unit_idx, attack_handler)"
    if r == "cast_deferred":
        return f"{indent}_translate_cast_deferred(unit, state)"
    if r == "parameterized":
        m = row.routing_params["method"]
        p = row.routing_params["param_field"]
        return f'{indent}_translate_parameterized(unit, state, "{m}", "{p}")'
    if r == "resolver_variant":
        return (
            f"{indent}_translate_resolver_variant(unit, state, "
            f"{qualifier}{row.display}, {clear})"
        )
    raise GenError(f"row {row.unified}: routing {r!r} has no dispatch mapping")


def render_translator(tax: Taxonomy, qualifier: str = DISPLAY_QUALIFIER) -> str:
    """The `translate()` match shell's body text, with Display members spelled
    using `qualifier`. Split out of `emit_translator` so a test can render the
    same rows under two spellings and diff them."""
    lines = [
        "# Source of truth: tools/activity_taxonomy.yaml",
        "# DO NOT edit by hand. Regenerate:",
        "#   (cd tools && uv run python gen_activity_taxonomy.py)",
        "",
        "static func translate(unit, logical: int, state: Dictionary, unit_idx: int,",
        "\t\tattack_handler: Callable = Callable()) -> void:",
        "\tmatch logical:",
    ]

    grouped: dict[str, list[Row]] = {}
    order: list[str] = []
    for r in tax.rows:
        if r.logical is None or r.routing in METADATA_ROUTINGS:
            continue
        if r.logical not in grouped:
            grouped[r.logical] = []
            order.append(r.logical)
        grouped[r.logical].append(r)

    for name in order:
        rows = grouped[name]
        lines.append(f"\t\tGPUConstants.LOGICAL_ACTIVITY_{name}:")
        if len(rows) == 1:
            lines.append(_routing_call(rows[0], "\t\t\t", qualifier))
        else:
            for i, r in enumerate(rows):
                if r.predicate is None:
                    raise GenError(
                        f"logical {name!r} has multi-row split; row {r.unified} "
                        f"is missing a predicate"
                    )
                keyword = "if" if i == 0 else "elif"
                lines.append(f"\t\t\t{keyword} {r.predicate}:")
                lines.append(_routing_call(r, "\t\t\t\t", qualifier))

    return "\n".join(lines)


def emit_translator(tax: Taxonomy) -> list[tuple[Path, str]]:
    """Emit the `translate()` match shell inside ActivityTranslator.gd.

    Logical values are grouped; single-row groups emit one call directly,
    multi-row groups (currently just ACTING) emit an if/elif ladder over
    the rows' predicate strings."""
    body = render_translator(tax)
    text = TRANSLATOR_PATH.read_text()
    new_text = _replace_region(text, TRANSLATE_BEGIN, TRANSLATE_END, body, TRANSLATOR_PATH)
    return [(TRANSLATOR_PATH, new_text)]


def _md_cell(s: str | None) -> str:
    """Single-line a Markdown table cell; em-dash for missing values; escape pipes."""
    if s is None or s == "":
        return "&mdash;"
    s = " ".join(s.split())
    return s.replace("|", "\\|")


def emit_context(tax: Taxonomy) -> list[tuple[Path, str]]:
    """Render a pipe-delimited Markdown table covering all rows. ACTING-split
    rows appear as separate entries with their predicate spelled out."""
    headers = ["#", "Unified", "Logical", "Display", "Routing", "Predicate", "ADR", "Notes"]
    body_lines = [
        "| " + " | ".join(headers) + " |",
        "|" + "|".join(["---"] * len(headers)) + "|",
    ]
    for i, r in enumerate(tax.rows, start=1):
        body_lines.append("| " + " | ".join([
            str(i),
            _md_cell(r.unified),
            _md_cell(r.logical),
            _md_cell(r.display),
            _md_cell(r.routing),
            _md_cell(f"`{r.predicate}`") if r.predicate else _md_cell(None),
            _md_cell(r.adr),
            _md_cell(r.notes),
        ]) + " |")
    body = "\n".join(body_lines)
    text = CONTEXT_PATH.read_text()
    new_text = _replace_region(text, CONTEXT_BEGIN, CONTEXT_END, body, CONTEXT_PATH)
    return [(CONTEXT_PATH, new_text)]


def emit_kernel(tax: Taxonomy) -> list[tuple[Path, str]]:
    """The kernel member. Fully generated, like `DisplayActivity.gd`.

    Both halves land here from the SAME rows (ADR-0217 dec. 8). Publishing one
    into the kernel and leaving the other in `Battle` would put a single source
    of truth across a package boundary — ADR-0196's argument for `CellMarking`
    applied unchanged.

    🔴 NO `class_name`. `addons/exmateria_schema` puts exactly one global in a
    consumer's project and it is the façade (ADR-0212 dec. 1); the burn-down
    `tools/check_addon_globals.py` pins at `set()` has to stay empty, so this
    file reaches only as `ExMateriaSchema.UnitActivity`.

    🔴 NO `LOGICAL_NAMES` ARRAY. `GPUConstants.gd` carries one because its half
    is loose `const`s with no reflection; an `enum` answers the same question
    through `Logical.keys()`, so emitting a second copy here would add a
    published name with no host use — which `arm_citations` scores, and rightly."""
    display_names = tax.display_names()
    entries = tax.logical_entries()
    lines = [
        "extends RefCounted",
        "",
        "## **What a unit is currently doing** — both halves of the activity",
        "## taxonomy, published as one kernel member.",
        "##",
        "## THIS FILE IS GENERATED -- DO NOT EDIT.",
        "## Source of truth: `tools/activity_taxonomy.yaml`",
        "## Regenerate: `(cd tools && uv run python gen_activity_taxonomy.py)`",
        "##",
        "## Part of ADR-0118 dec. 1's **tenth** schema row — the unit-sprite",
        "## vocabulary — admitted by ADR-0215 dec. 2 and named by ADR-0217 dec. 7;",
        "## dec. 8 is why it is one member and not two. `Display` is what the",
        "## ANIMATION layer should play and `Logical` is what the ENGINE thinks the",
        "## unit is doing; they are generated from the same rows and exist only to",
        "## be translated into each other, so a value vocabulary two systems must",
        "## agree on is the kernel's.",
        "##",
        "## 🔴 `UnitActivity` HAS BEEN THIS TAXONOMY'S NAME BEFORE. The YAML's own",
        "## vocabulary note records the CPU-side enum that `DisplayActivity`",
        "## replaced as `UnitActivity`. The name is reused here on purpose",
        "## (ADR-0217 dec. 7's subject-noun form), and no live symbol carried it",
        "## when this landed, so nothing collides — but a reader meeting the word",
        "## in ADR-0025 or ADR-0026 is meeting the retired one.",
        "",
        "## What the animation layer should play. 🔴 REFERENCE MEMBERS BY NAME.",
        "## The integers are declaration order — first occurrence in the YAML rows —",
        "## and are NOT a contract; `addons/exmateria_sprite_rig/state/DisplayActivity.gd` is emitted",
        "## from the same list, so the two agree by construction rather than by",
        "## anyone keeping them in step.",
        "enum Display {",
    ]
    for name in display_names:
        lines.append(f"\t{name},")
    lines += [
        "}",
        "",
        "## What the engine thinks the unit is doing. 🔴 THE INTEGERS ARE WRITTEN",
        "## OUT AND THEY ARE A CONTRACT: the GPU compute shader writes these values",
        "## into `U_STATE`, and `src/gpu/shaders/combat_common.glslinc` +",
        "## `src/gpu/GPUConstants.gd` carry the same numbers from the same rows.",
        "## Renumbering here without a buffer-version bump is a silent",
        "## wrong-activity bug with nothing red in between.",
        "enum Logical {",
    ]
    for name, value in entries:
        lines.append(f"\t{name} = {value},")
    lines.append("}")
    return [(KERNEL_PATH, "\n".join(lines) + "\n")]


def emit_all(tax: Taxonomy) -> list[tuple[Path, str]]:
    outputs: list[tuple[Path, str]] = []
    outputs += emit_glsl(tax)
    outputs += emit_gpu_constants(tax)
    outputs += emit_display_activity(tax)
    outputs += emit_translator(tax)
    outputs += emit_context(tax)
    outputs += emit_kernel(tax)
    return outputs


def main(argv: list[str]) -> int:
    check = "--check" in argv[1:]
    tax = load()
    outputs = emit_all(tax)
    stale: list[Path] = []
    for path, new_text in outputs:
        cur = path.read_text() if path.exists() else ""
        if cur != new_text:
            stale.append(path)
            if not check:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(new_text)

    label = "activity taxonomy"
    if check:
        if stale:
            print(f"STALE {label} - regenerate with:")
            print("  (cd tools && uv run python gen_activity_taxonomy.py)")
            for p in stale:
                print(f"  - {p.relative_to(ROOT)}")
            return 1
        print(f"{label}: up to date ({len(tax.rows)} rows)")
        return 0

    if stale:
        print(f"Regenerated {label} in:")
        for p in stale:
            print(f"  - {p.relative_to(ROOT)}")
    else:
        print(f"{label}: already up to date ({len(tax.rows)} rows)")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except GenError as e:
        print(f"gen_activity_taxonomy: ERROR: {e}", file=sys.stderr)
        sys.exit(2)
