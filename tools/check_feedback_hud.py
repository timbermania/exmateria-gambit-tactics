#!/usr/bin/env python3
"""Enforce that the over-unit feedback HUD is observation-only (ADR-0063).

ADR-0063's cross-cutting invariant: the battle feedback HUD is an apply-only
consumer of the combat loop's GPU-authoritative signals — it NEVER reads FFT's
ROM `BattleUnitData` and NEVER writes battle state (the ADR-0031 authority line)
— and its over-unit elements render as `combat_visuals` billboards through the
shared Ordering-Table depth seam (ADR-0009), so they sort against battlefield
geometry and ride the ADR-0037 freeze.

This is the cheap text net (mirrors check_no_env_vars / check_par_shaders): it
makes the two ways to break ADR-0063 impossible to ship silently —
  (1) reading ROM state / writing battle state from a feedback-HUD class, and
  (2) an over-unit billboard that forgets the combat_visuals group or the
      OT-depth shader (would mis-sort / not freeze).

Scope = the over-unit feedback-HUD classes only (the screen-space info window is
ordinary ui3 and out of this net). Exit 0 if clean, 1 if any violation. Pure
stdlib; no Godot needed.
"""
import re
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent

# The over-unit billboard classes + their driver (ADR-0063 "over-unit elements").
MANAGER = PROJECT_DIR / "src/ui3/elements/FeedbackHudManager.gd"
BILLBOARDS = [
    PROJECT_DIR / "src/ui3/elements/DamageNumber3D.gd",
    PROJECT_DIR / "src/ui3/elements/StatusBubble3D.gd",
]
SHADER = PROJECT_DIR / "assets/shaders/feedback_hud_sprite.gdshader"
SHADER_RES = "res://assets/shaders/feedback_hud_sprite.gdshader"

# Observation-only: reading the ROM battle struct is banned everywhere in scope.
ROM_STRUCT = re.compile(r"\bBattleUnitData\b")
# Writing battle state is banned: the HUD reads UnitStats, never assigns its HP/MP.
# `=(?!=)` excludes the `==` comparison.
STATE_WRITE = re.compile(r"\bcurrent_(hp|mp)\s*=(?!=)")


def _lines(path: Path) -> list[str]:
    return path.read_text(encoding="utf-8").splitlines()


def check_observation_only(path: Path) -> list[str]:
    """No ROM-struct read, no battle-state write, in any feedback-HUD class."""
    problems = []
    for lineno, line in enumerate(_lines(path), 1):
        code = line.split("#", 1)[0]  # strip comment; prose may mention the name
        if ROM_STRUCT.search(code):
            problems.append(f"{lineno}: reads FFT ROM state (BattleUnitData) — feedback HUD is observation-only: {line.strip()}")
        if STATE_WRITE.search(code):
            problems.append(f"{lineno}: writes battle state (current_hp/mp =) — HUD must not write (ADR-0031): {line.strip()}")
    return problems


def main() -> int:
    violations: dict[str, list[str]] = {}

    def add(path: Path, problems: list[str]) -> None:
        if problems:
            violations.setdefault(str(path.relative_to(PROJECT_DIR)), []).extend(problems)

    # 0. The files must exist (the class-(c) gap this ADR closes).
    for path in [MANAGER, SHADER, *BILLBOARDS]:
        if not path.is_file():
            add(path, ["missing — ADR-0063 over-unit billboard not built"])
    if violations:
        return _report(violations)

    # 1. Observation-only: no ROM read / no state write anywhere in scope.
    for path in [MANAGER, *BILLBOARDS]:
        add(path, check_observation_only(path))

    # 2. The manager consumes the GPU-authoritative signal (apply-only consumer).
    mgr_text = MANAGER.read_text(encoding="utf-8")
    if "hp_changed" not in mgr_text or ".connect(" not in mgr_text:
        add(MANAGER, ["does not connect to CombatLoop.hp_changed — HUD must be a signal consumer (ADR-0063)"])

    # 3. Each over-unit billboard: combat_visuals group (ADR-0037 freeze) + the
    #    OT-depth feedback shader (ADR-0009 sort). Both are load-bearing.
    for path in BILLBOARDS:
        text = path.read_text(encoding="utf-8")
        probs = []
        if 'add_to_group("combat_visuals")' not in text:
            probs.append('not in the "combat_visuals" group — would not sort/freeze with the battle (ADR-0037)')
        if SHADER_RES not in text:
            probs.append(f"does not render through {SHADER_RES} — over-unit billboards need OT depth (ADR-0009)")
        add(path, probs)

    # 4. The shader routes DEPTH through the OT seam (belt-and-suspenders with
    #    check_depth_shaders; keeps the ADR-0063 invariant self-contained).
    shader_text = SHADER.read_text(encoding="utf-8")
    if "ot_depth.gdshaderinc" not in shader_text or "DEPTH = ot_computed_depth" not in shader_text:
        add(SHADER, ["feedback shader does not write DEPTH via the ot_depth seam (ADR-0009)"])

    return _report(violations)


def _report(violations: dict[str, list[str]]) -> int:
    if violations:
        print("ADR-0063 feedback-HUD conformance violations:")
        for rel, problems in violations.items():
            for p in problems:
                print(f"  {rel}:{p}")
        print(
            "\nADR-0063: the over-unit feedback HUD is observation-only (consumes "
            "CombatLoop signals + UnitStats, never reads BattleUnitData, never "
            "writes battle state) and renders as combat_visuals billboards through "
            "the OT-depth seam. See docs/adr/0063-*.md and docs/battle-hud-faithful-spec.md."
        )
        return 1
    print("OK: feedback HUD is observation-only + OT-depth combat_visuals billboards (ADR-0063).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
