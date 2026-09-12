#!/usr/bin/env python3
"""Every tunable owner registers ITSELF, and `Tune` names none of them (#535, ADR-0173).

    python3 tools/check_tune_owner_self_registration.py

This is `tools/check_tune_owner_manifest.py` (#534) INVERTED, and the inversion is
the whole point. That guard existed because `Tune.register_all()` held a
hand-maintained list of fifteen owner script paths across seven of the eleven
systems: a `platform` authority enumerating its clients, which is the shape
`BLUEPRINT.md` rejects (*"A handle is opaque, so it enumerates nothing"*). It
could only ask "is the list complete, does every entry resolve" — questions that
exist because there is a list.

#535 deleted the list. `Tune.reset()` no longer clears the registry, so nothing
has to replay anything, so `Tune` names nobody. What carries the weight now is a
narrower claim, and these rules are it: **each owner's binds run from its own
boot path, and `Tune.gd` stays out of it.**

THE RULES, AND WHY EACH DRAWS ITS LINE WHERE IT DOES.

  S1  Every ZERO-ARG STATIC `register_tunables` is called from its OWN file's
      `_static_init()`. Static + zero-arg IS the class-load owner shape. With the
      central replay gone, `_static_init` is the ONLY thing that runs those binds
      — in production it always was (`register_all()` had eight call sites and
      all eight were tests). An owner that declares the method and never calls it
      at class load is a slug set that never registers, and the failure surfaces
      far away, as a `get_value` assert (R5) or an `on_update` that applies null.

  S2  `src/core/Tune.gd` names NO owner: no `res://…​.gd` script path, no
      `/root/…` autoload path. This is the inversion itself, mechanized. It is
      the rule that makes a revert loud instead of convenient — re-adding a
      central replay means re-adding paths here, and this says so. `res://config/…`
      literals are Tune's OWN files (the staging file, the registry snapshot) and
      are not owners; the rule is about script and autoload paths.

  S3  Every autoload whose script declares an INSTANCE `register_tunables` calls
      it from its own `_ready()`. The autoload half of S1. Their binds read
      instance state, so they cannot be static — `_ready` is their class-load
      equivalent, and it is now equally load-bearing.

  S4  A `register_tunables` that TAKES ARGUMENTS is never called argument-lessly
      from `_static_init`/`_ready`. `src/effects/studio/SequenceThumbnail.gd`
      declares `static func register_tunables(owner: Node)` and is the live
      example — it is a scene-scoped owner, correctly out of S1's scope, and this
      rule is what keeps "just add a `_static_init` to every owner" from being a
      mechanical fix that fails at the call. It is #534's R3 finding, kept alive
      after the list it originally guarded is gone.

NOT CHECKED, DELIBERATELY. That an owner's `register_tunables` actually BINDS
something is a runtime property and belongs to
`tests/TuneOwnerSelfRegistrationTest.gd`, which discovers the same owner set by
walking the tree and asserts each one grows the registry. This guard is the
static half: it can prove a boot path is ABSENT or mis-shaped, never that a
present one binds what a reader wants.

MEASURED WHEN THIS WAS WRITTEN (#535, 2026-08-25): 13 zero-arg static owners, all
13 calling `register_tunables()` from `_static_init`; 4 autoload owners, all 4
calling it from `_ready`; 1 arg-taking owner (`SequenceThumbnail`), calling it
from neither. Every rule was clean on arrival, so every rule is seeded —
`tools/seed_tune_owner_self_registration.py`.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TUNE = ROOT / "src" / "core" / "Tune.gd"
SCAN_ROOTS = ("src", "addons", "tests")

DEF = re.compile(r"^\s*(static\s+)?func\s+register_tunables\s*\(([^)]*)\)")
CALLS = re.compile(r"^\s*register_tunables\s*\(\s*\)\s*$")


def _calls_bare_from(text: str, func_name: str) -> bool:
    """Does `func_name`'s body in `text` contain a bare `register_tunables()` call?

    Body = every line after the `func` header that is blank or more-indented, which is
    GDScript's block rule. Deliberately syntactic: this asks whether the call is WRITTEN
    at the boot path, which is exactly what an eyeball reading the file would ask.
    """
    lines = text.splitlines()
    head = re.compile(r"^(\s*)(static\s+)?func\s+%s\s*\(" % re.escape(func_name))
    for i, line in enumerate(lines):
        m = head.match(line)
        if not m:
            continue
        indent = len(m.group(1))
        for body in lines[i + 1:]:
            if body.strip() == "":
                continue
            if len(body) - len(body.lstrip()) <= indent:
                break
            if CALLS.match(body):
                return True
    return False


def owners():
    """(rel, is_static, takes_args, from_static_init, from_ready) per declaring file."""
    out = []
    for top in SCAN_ROOTS:
        for q in sorted((ROOT / top).rglob("*.gd")):
            text = q.read_text(errors="ignore")
            for line in text.splitlines():
                m = DEF.match(line)
                if m:
                    out.append((q.relative_to(ROOT).as_posix(), bool(m.group(1)),
                                m.group(2).strip() != "",
                                _calls_bare_from(text, "_static_init"),
                                _calls_bare_from(text, "_ready")))
                    break
    return out


def tune_literals():
    """The owner-shaped string literals inside `src/core/Tune.gd`, as they are written.

    A script path or an autoload path. `res://config/…` is Tune's own staging file and
    registry snapshot — its own data, not an owner — so the script rule is scoped to `.gd`.
    """
    src = TUNE.read_text()
    return (re.findall(r'"(res://[^"]+\.gd)"', src),
            re.findall(r'"(/root/[^"]*)"', src))


def autoloads():
    block = (ROOT / "project.godot").read_text()
    block = block[block.index("[autoload]"):]
    nxt = block.index("\n[", 1) if "\n[" in block[1:] else len(block)
    return dict(re.findall(r'^(\w+)="\*?res://(.+)"$', block[:nxt], re.M))


def evaluate(found, tune_scripts, tune_roots, auto):
    """The four rules, over inputs rather than over the tree.

    Split out so a mutation seed can prove each rule LIVE without writing to the tree —
    this repo's worktrees are shared, and a seeded control that edits production code to
    prove a guard works is a race, not a control. See
    `tools/seed_tune_owner_self_registration.py`.
    """
    decl = {rel: row for rel, *row in
            [(r, st, args, si, rd) for r, st, args, si, rd in found]}

    s1 = sorted(rel for rel, (st, args, si, _rd) in decl.items()
                if st and not args and not si)
    s2 = [("res://%s" % p if not p.startswith("res://") else p) for p in tune_scripts] \
        + list(tune_roots)
    s3 = []
    for name, script in sorted(auto.items()):
        row = decl.get(script)
        if row is None:
            continue
        st, args, _si, rd = row
        if st or args:
            continue
        if not rd:
            s3.append((name, script))
    s4 = sorted(rel for rel, (_st, args, si, rd) in decl.items() if args and (si or rd))
    return s1, s2, s3, s4


def main() -> int:
    found = owners()
    tune_scripts, tune_roots = tune_literals()
    auto = autoloads()

    static_owners = [r for r, st, args, _, _ in found if st and not args]
    auto_owners = [r for r, st, args, _, _ in found if not st and not args and r in auto.values()]
    print("subject: %d file(s) declaring register_tunables — %d class-load (static, zero-arg), "
          "%d autoload; Tune.gd names %d script path(s) + %d autoload path(s)"
          % (len(found), len(static_owners), len(auto_owners),
             len(tune_scripts), len(tune_roots)))

    s1, s2, s3, s4 = evaluate(found, tune_scripts, tune_roots, auto)
    fail = False
    if s1:
        fail = True
        print("\nS1 — class-load owner does not call register_tunables() from _static_init:")
        for rel in s1:
            print("  %s" % rel)
        print("  Nothing else runs it. `Tune.register_all()` was deleted in #535, and its eight\n"
              "  call sites were all tests — production NEVER replayed. Add\n"
              "  `static func _static_init() -> void: register_tunables()`, or make the owner\n"
              "  instance-scoped and register from its own _ready.")
    if s2:
        fail = True
        print("\nS2 — src/core/Tune.gd names an owner:")
        for p in s2:
            print("  %s" % p)
        print("  platform must enumerate nothing (ADR-0173; BLUEPRINT.md 'a handle is opaque').\n"
              "  If a central replay is coming back, that is an ADR, not an array literal.")
    if s3:
        fail = True
        print("\nS3 — autoload owner does not call register_tunables() from _ready:")
        for name, script in s3:
            print("  %s  (res://%s)" % (name, script))
        print("  An autoload's _ready IS its boot path; with no central replay it is the only one.")
    if s4:
        fail = True
        print("\nS4 — an arg-taking register_tunables is called with no arguments:")
        for rel in s4:
            print("  %s" % rel)
        print("  A scene-scoped owner takes its owner Node; calling it bare is an arity error.")

    if not fail:
        print("\nEvery owner registers itself at its own boot path, and Tune.gd names none of them.")
    print("\nThat an owner's binds actually LAND is NOT checked here — that is\n"
          "tests/TuneOwnerSelfRegistrationTest.gd (the runtime half).")
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
