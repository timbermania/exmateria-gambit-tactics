#!/usr/bin/env bash
# ADR-0194's stranger rig for an IN-WALK addon — ONE implementation, driven by
# `tests/stranger/<addon>/run.sh`, which is a three-line shim naming its own
# directory. #652 slices 2 and 4. Everything below is derived: the addon from the
# rig directory's name, the engine and the dependency set from `plugin.cfg`, the
# subject's file list from the staged tree.
#
# The claim: `addons/exmateria_schema/` works in a project that did nothing for
# it — no autoloads, no bus layout, no assets, no host scripts. The rig stages a
# throwaway project, copies the addon in, imports once, and runs the addon's own
# tests there. Nothing about this is new: it is
# `exmateria-sound/workspace/acceptance/stranger_{sound,spu}/run.sh` generalised
# to the four addons that never left the walk, and it keeps their contract
# exactly — mktemp work dir, staged fresh every run, one import pass before any
# test, verdict = a `^[PASS]` line, and exit 2 for could-not-run, which is
# loudly NOT a pass.
#
# STAGING MODE: SOURCE-COPY (ADR-0194 dec. 5/6). `stranger_sound` stages the
# PUBLISHED tree through the real manifest and therefore buys the strictly
# stronger claim, *"this addon installs the way the ZIP installs"*. There is no
# publication for this addon, and writing a manifest would assert one that does
# not exist. The two rigs buy DIFFERENT claims and blurring them is how goal #5
# gets oversold, so the banner below prints which one this run measured.
#
# ENGINE: DECLARED, AND CHECKED (dec. 7). The engine comes from `plugin.cfg`'s
# `engine=` line — an undeclared addon exits 2 rather than defaulting, because a
# default is how the declaration stops being read. A `fork` declaration also
# boots STOCK once and asserts the fork's compositor primitives are ABSENT
# there, which is what turns "we think this needs the fork" into a checked fact.
#
# Usage:
#   ./run.sh                       # engines resolved from PATH + /usr/bin/godot
#   GODOT_FORK=... GODOT_STOCK=... ./run.sh
#
# Exit 0 = pass, 1 = fail, 2 = could not run.
set -uo pipefail

if [[ $# -ne 1 || ! -d "$1" ]]; then
    echo "usage: rig.sh <tests/stranger/{addon} directory>" >&2
    exit 2
fi
HERE="$(cd "$1" && pwd)"
SHARED="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$SHARED/../../.." && pwd)"
ADDON="$(basename "$HERE")"
SRC_ADDON="$PKG/addons/$ADDON"

if [[ ! -d "$SRC_ADDON" ]]; then
    echo "CANNOT RUN: no addon at $SRC_ADDON" >&2
    exit 2
fi

# --- the declared engine -----------------------------------------------------
ENGINE="$(sed -n 's/^engine="\([a-z]*\)"[[:space:]]*$/\1/p' "$SRC_ADDON/plugin.cfg" | head -1)"
if [[ -z "$ENGINE" ]]; then
    echo "CANNOT RUN: $ADDON/plugin.cfg declares no \`engine=\`." >&2
    echo "  ADR-0194 dec. 7: each addon DECLARES its engine and the rig runs the" >&2
    echo "  declared binary. Defaulting to one would be the rig deciding a fact" >&2
    echo "  about the addon. Add engine=\"stock\" or engine=\"fork\"." >&2
    exit 2
fi
if [[ "$ENGINE" != "stock" && "$ENGINE" != "fork" ]]; then
    echo "CANNOT RUN: $ADDON/plugin.cfg declares engine=\"$ENGINE\", which is not stock or fork" >&2
    exit 2
fi

# --- the declared dependencies ----------------------------------------------
# `deps=` is a space-separated list of sibling addon directory names, and it is a
# DECLARATION in the same sense as `engine=`: CONTEXT.md's *addon-owned test* is a
# test whose reach is its addon, that addon's DECLARED DEPENDENCIES, and its
# documented install steps. An undeclared dep staged anyway would let the rig
# quietly supply something the addon never said it needed, which is the failure
# this whole exercise is about. An addon with no line has no deps; an addon that
# names one that is not there cannot run.
#
# 🔴 THE CLOSURE, NOT THE LINE. Until 2026-09-08 this read one `deps=` line and staged
# exactly those directories, and that was indistinguishable from correct because every
# declared dep in the corpus was a LEAF: `exmateria_platform` and `exmateria_schema`
# declare no deps of their own, and they were the only things anyone depended on.
# `exmateria_catalogue` (#1025 pass 3) is the first addon whose deps have deps, and staging
# the line alone put the rig in a project where a STAGED addon could not parse. That is not
# the subject's defect and must not be reported as one, and it was not a reason to widen the
# subject's own declaration either: at the time the catalogue reached no `ExMateriaSchema`
# symbol, so declaring one would have been a false claim in the file the whole rig treats as
# authoritative.
#
# 🔴 BOTH HALVES OF THAT EXAMPLE HAVE SINCE MOVED, AND THE RULE HAS NOT. The edge was
# `exmateria_catalogue` -> `exmateria_sprite_rig` -> `exmateria_schema`; #1180 gave the
# catalogue a real `ExMateriaSchema` reach (7 arm-5 lines, ADR-0294 dec. 2) so `deps=` now
# names the schema DIRECTLY and truthfully, and #1239 dropped `exmateria_sprite_rig`, which
# had reached nothing since #1071 (ADR-0272). The catalogue is still a non-leaf case —
# `exmateria_almanac` declares `deps="exmateria_platform exmateria_schema"` — so this loop
# is still doing work for it, but read the CLOSURE the run prints rather than this
# paragraph's example, because the example is a 2026-09-08 record and the tree is not. What a
# consumer has to unzip is the TRANSITIVE closure of the declarations, so that is what is
# staged, and the banner prints both — the line and the closure — because a reader who
# sees only the closure cannot tell what this addon actually said about itself.
_deps_line() {   # _deps_line <addon-dir-name>
    sed -n 's/^deps="\(.*\)"[[:space:]]*$/\1/p' "$PKG/addons/$1/plugin.cfg" 2>/dev/null | head -1
}
DEPS="$(_deps_line "$ADDON")"
CLOSURE=""
queue="$DEPS"
while [[ -n "${queue// /}" ]]; do
    next=""
    for d in $queue; do
        case " $CLOSURE " in *" $d "*) continue;; esac
        if [[ ! -d "$PKG/addons/$d" ]]; then
            echo "CANNOT RUN: a plugin.cfg in the dependency closure of $ADDON declares $d, which is not at $PKG/addons/$d" >&2
            exit 2
        fi
        CLOSURE="$CLOSURE $d"
        next="$next $(_deps_line "$d")"
    done
    queue="$next"
done
CLOSURE="${CLOSURE# }"

# 🔴 AND THE ENGINE IS THE CLOSURE'S, NOT THE SUBJECT'S — the same defect one field over.
# `engine=` is a measured claim about the files in ONE addon (ADR-0194 dec. 7), and the
# binary the rig has to boot is the one that can parse everything it STAGES.
# `exmateria_catalogue` declares "stock" truthfully — no file in it names a compositor
# primitive — and its closure contains `exmateria_schema`, which is "fork". (It also held
# `exmateria_sprite_rig`, likewise "fork", until #1239 dropped it as a dependency that
# reached nothing. That drop left the BINARY unchanged only because #1180 had already added
# the schema as a direct dep — so a `deps=` edit is a possible ENGINE change here.
# Since #1241 the coupling IS guarded: `tools/check_addon_portability.py`'s arm 8b prints
# every shared-rig subject's own `engine=` beside its closure's and holds the divergences
# in a NAMED register, so the next `deps=` edit that moves the booted binary reds the
# pre-flight instead of passing in silence. Arm 8 reads the `deps=` line itself the same
# way — both directions against arm 5's measured reach.)
# Booting stock reported five unexplained throws from
# `exmateria_schema/compositing_key/`, which are that addon's declared fork dependency
# arriving as if they were the subject's defect. Promoting the subject's own declaration
# to "fork" would be the other error: it would make the plugin.cfg say the catalogue
# needs a primitive it does not name. So the DECLARATION stays the subject's and the
# RUN follows the closure, and the banner prints both so the two can never be read as one.
# This changes nothing for the six earlier rigs — every one of their closures already
# agreed with its subject — which is why it went unnoticed until an addon depended on
# something that was not a leaf.
SUBJECT_ENGINE="$ENGINE"
for d in $CLOSURE; do
    e="$(sed -n 's/^engine="\([a-z]*\)"[[:space:]]*$/\1/p' "$PKG/addons/$d/plugin.cfg" | head -1)"
    if [[ -z "$e" ]]; then
        echo "CANNOT RUN: $d is in $ADDON's dependency closure and declares no \`engine=\`." >&2
        exit 2
    fi
    [[ "$e" == "fork" ]] && ENGINE="fork"
done

# `godot` on PATH is this repo's 4.8 compositor fork; /usr/bin/godot is the
# distro's stock build. Each is identified by what it REPORTS, never by its path
# — a rig that trusts a filename passes on whichever binary happens to be there.
resolve() {   # resolve <want: fork|stock> <candidate...>
    local want="$1"; shift
    local c v
    for c in "$@"; do
        [[ -n "$c" ]] || continue
        command -v "$c" >/dev/null 2>&1 || continue
        v="$("$c" --version 2>/dev/null)"
        if [[ "$want" == "fork" ]]; then
            [[ "$v" == *custom_build* ]] && { echo "$c"; return 0; }
        else
            [[ "$v" != *custom_build* ]] && { echo "$c"; return 0; }
        fi
    done
    return 1
}

GODOT_FORK="$(resolve fork "${GODOT_FORK:-}" godot)" || GODOT_FORK=""
GODOT_STOCK="$(resolve stock "${GODOT_STOCK:-}" /usr/bin/godot)" || GODOT_STOCK=""

if [[ "$ENGINE" == "fork" ]]; then
    RUN_GODOT="$GODOT_FORK"
else
    RUN_GODOT="$GODOT_STOCK"
fi
if [[ -z "$RUN_GODOT" ]]; then
    echo "CANNOT RUN: $ADDON declares engine=\"$ENGINE\" and no such Godot was found." >&2
    echo "  Set GODOT_FORK / GODOT_STOCK. This is NOT a pass." >&2
    exit 2
fi
if [[ "$ENGINE" == "fork" && -z "$GODOT_STOCK" ]]; then
    echo "CANNOT RUN: a fork declaration needs a STOCK Godot too, for dec. 7's" >&2
    echo "  absence arm. Without it the declaration is unchecked, which is the" >&2
    echo "  state this rig exists to end. Set GODOT_STOCK=<path>." >&2
    exit 2
fi

echo "[stranger:$ADDON] claim:  source-copy — this addon works in a project that did nothing for it"
echo "[stranger:$ADDON]         (NOT the publish-staged claim; there is no publication for this addon)"
if [[ "$ENGINE" == "$SUBJECT_ENGINE" ]]; then
    echo "[stranger:$ADDON] engine: declared \"$SUBJECT_ENGINE\" -> $("$RUN_GODOT" --version)"
else
    echo "[stranger:$ADDON] engine: declared \"$SUBJECT_ENGINE\" by the subject; the dependency"
    echo "[stranger:$ADDON]         closure needs \"$ENGINE\" -> $("$RUN_GODOT" --version)"
fi
echo "[stranger:$ADDON] deps:   declared \"${DEPS:-none}\""
echo "[stranger:$ADDON]         closure \"${CLOSURE:-none}\" — staged beside the subject, and nothing else is"

# --- stage, fresh every run --------------------------------------------------
WORK="$(mktemp -d -t "stranger_${ADDON}_XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
cp "$HERE"/project.godot "$WORK/"
# The harness keeps its repo-relative path inside the staged project, so every
# `res://tests/stranger/...` literal is true in the host tree AND here. Staged
# flat, those literals resolve in neither and `tools/check_res_paths.py` — which
# reads every quoted res:// source path in godot-learning/ — is red on a clean
# checkout. See project.godot's own note.
RIGREL="tests/stranger/$ADDON"
mkdir -p "$WORK/$RIGREL" "$WORK/tests/stranger/shared"
cp "$HERE"/*.gd "$HERE"/*.tscn "$WORK/$RIGREL/" 2>/dev/null || true
# One implementation of the engine arm, not one per rig.
cp "$SHARED"/*.gd "$SHARED"/*.tscn "$WORK/tests/stranger/shared/" 2>/dev/null
mkdir -p "$WORK/addons"
# -L: a symlinked addon is not what a stranger unzips. Dereference into real files.
cp -rL "$SRC_ADDON" "$WORK/addons/$ADDON"
for d in $CLOSURE; do
    cp -rL "$PKG/addons/$d" "$WORK/addons/$d"
done
# The rig's own burn-down, if it has one. Absent = the subject carries no named
# debt, which is a claim the install arm then makes rather than assumes.
[[ -f "$HERE/known_failures.tsv" ]] && cp "$HERE/known_failures.tsv" "$WORK/known_failures.tsv"

# --- one import pass, before any test ---------------------------------------
# A cold global class cache reads as a real parse error: the addon's own
# `class_name`s are not registered until something has imported the project, so
# the first test would fail with `Identifier "ColorRecipe" not declared` and the
# rig would report a portability defect that is entirely its own.
"$RUN_GODOT" --path "$WORK" -e --quit >/dev/null 2>&1

# --- the scenes --------------------------------------------------------------
rc=0
# The SCRIPT ERROR lines this addon's burn-down already explains. Built once from
# known_failures.tsv's signature column; empty when the addon has no burn-down,
# in which case the filter below is a no-op and every throw is the finding.
ALLOW="$WORK/.rig_allowed_errors"
: > "$ALLOW"
if [[ -f "$HERE/known_failures.tsv" ]]; then
    # One row, possibly SEVERAL signatures, `|`-separated. A file can throw more than
    # one parse error and the column is one field: `cast/EffectInstance.gd` emits a
    # missing-preload line for each of three `addons/exmateria_sound/runtime/` files AND
    # an undeclared `ExMateriaEffectSfx`, and no single substring is true of both without
    # being broad enough to excuse the next undeclared identifier too. Splitting the
    # column keeps every signature SPECIFIC, which is the property that makes an
    # unexplained throw the finding. `grep -F` treats each as a fixed string, so a `|`
    # inside a real engine message could never have been matched anyway.
    awk -F'\t' '!/^#/ && NF >= 4 { n = split($3, sig, "|"); for (i = 1; i <= n; i++) print sig[i] }' "$HERE/known_failures.tsv" >> "$ALLOW"
    # A cascade line naming no file and no symbol. A genuinely new defect always
    # emits its own specific line beside it, so this can never be the sole
    # evidence of one.
    echo "Failed to compile depended scripts" >> "$ALLOW"
fi

run_scene() {   # run_scene <godot> <res path> <label> [throws-expected]
    local godot="$1" scene="$2" label="$3" throws="${4:-no}" out
    out="$("$godot" --path "$WORK" --quit-after 900 "$scene" 2>&1)"
    echo "$out" | grep -aE "^\[(ok|FAIL|PASS)\]|[0-9]+ passed, [0-9]+ failed" || true
    if ! echo "$out" | grep -aq "^\[PASS\]"; then
        echo "[FAIL] $label did not report PASS" >&2
        # 🔴 THE SCENE'S OWN FAILING ASSERTION COMES FIRST, AND #909 IS WHY. This block
        # printed `SCRIPT ERROR|ERROR:` only, so a scene that FAILED AN ASSERTION was
        # reported through whatever unrelated `ERROR:` its addon happened to log at load.
        # `EventPathfinderTest` failed on a stale `50 != 64` pin and the rig showed the
        # battlefield addon's "no content root" banner instead — a real line, emitted by a
        # different subsystem, that read as a diagnosis and was filed as one. An ERROR line
        # is EVIDENCE OF AN ERROR, never evidence of THIS failure; the arms' own output is
        # the only thing that says which assertion went red, so it leads.
        # Case-SENSITIVE: an unindented `[FAIL]` is already printed by the grep above, and
        # matching it again prints the scene's verdict line twice while burning a slot of
        # the ten. The indented lowercase forms are the assertion helpers' own output.
        echo "$out" | grep -aE "^[[:space:]]*\[(fail|x)\]" | head -10 >&2
        echo "$out" | grep -aE "SCRIPT ERROR|ERROR:" | head -10 >&2
        rc=1
        return
    fi
    # A suite can report 84/84 while throwing four times. In the host that is a
    # known-tolerated noise floor; here a throw is the finding, because the only
    # thing this project withholds is the host. The ONE exception is the burn-down
    # scene, whose whole job is to load files that are declared not to compile —
    # the throws there are the declaration being true, and the scene's own arms
    # are what score it.
    if [[ "$throws" == "expected" ]]; then
        return
    fi
    local unexplained
    if [[ -s "$ALLOW" ]]; then
        unexplained="$(echo "$out" | grep -a "SCRIPT ERROR" | grep -avFf "$ALLOW")"
    else
        unexplained="$(echo "$out" | grep -a "SCRIPT ERROR")"
    fi
    if [[ -n "$unexplained" ]]; then
        echo "[FAIL] $label reported PASS while throwing something the burn-down does not explain:" >&2
        echo "$unexplained" | head -10 >&2
        rc=1
    fi
}

run_scene "$RUN_GODOT" "res://tests/stranger/shared/stranger_install.tscn" "stranger_install"

# 🔴 THE GATE IS THE ROW COUNT, NOT THE FILE. It used to be `-f known_failures.tsv`,
# and that made this a control that EXPIRES ON SUCCESS — the fifth in this family.
# `stranger_burn_down.gd` checks both directions of a burn-down: a listed file that
# still fails is expected, a listed file that now COMPILES must be deleted from the
# list. With zero rows it has nothing to check, and it says so itself and fails:
# "this scene should not have been run at all, and a run with nothing to check is not
# a pass". That is the scene being right. So the day #689 paid this addon's last two
# rows, the whole rig went RED because the addon got BETTER.
#
# The file is kept when the list empties, deliberately: its header carries the record
# of which rows left and which pass paid them, which is the part a reader needs and
# the part `git rm` would throw away. An addon that never had a burn-down has no file
# and takes the same branch.
if [[ -f "$HERE/known_failures.tsv" ]]; then
    n=$(grep -cve '^\s*#' -e '^\s*$' "$HERE/known_failures.tsv")
    if (( n > 0 )); then
        echo "[stranger:$ADDON] burn-down: $n file(s) DECLARED not to work in a stranger project."
        echo "[stranger:$ADDON]            Goal #5's INSTALL half is unmet for this addon; the rows"
        echo "[stranger:$ADDON]            name the tickets. The reach half is the other conjunct and"
        echo "[stranger:$ADDON]            tools/score_goals.py joins them (ADR-0232)."
        run_scene "$RUN_GODOT" "res://tests/stranger/shared/stranger_burn_down.tscn" "stranger_burn_down" expected
    else
        echo "[stranger:$ADDON] burn-down: EMPTY — no file in this addon is DECLARED to fail in a"
        echo "[stranger:$ADDON]            stranger project, so there is nothing for the burn-down"
        echo "[stranger:$ADDON]            scene to check and it is not run. The claim that every"
        echo "[stranger:$ADDON]            file compiles is made by the install pass above, which"
        echo "[stranger:$ADDON]            reads the same list and is the arm that would catch a"
        echo "[stranger:$ADDON]            regression here."
    fi
fi

shopt -s nullglob
owned=("$WORK/addons/$ADDON/tests"/*.tscn)
shopt -u nullglob
echo "[stranger:$ADDON] addon-owned tests: ${#owned[@]}"
for t in "${owned[@]}"; do
    stem="$(basename "$t" .tscn)"
    run_scene "$RUN_GODOT" "res://addons/$ADDON/tests/$stem.tscn" "$stem"
done

# --- the rig's OWN scenes ----------------------------------------------------
# 🔴 THESE WERE STAGED AND NEVER RUN, from #652 until ADR-0229. The `cp` above has
# always copied `$HERE/*.gd` and `$HERE/*.tscn` into the work dir, and the README's
# "Adding a rig" step 4 has always told the author to add a `stranger` skip row "for
# any scene the rig owns" — so both ends of the contract assumed this loop, and the
# loop was not here. Nobody noticed because all four rigs owned zero scenes: the gap
# is invisible for exactly as long as it costs nothing, which is the shape of every
# control in this repo that has expired quietly.
#
# WHY A RIG-OWNED SCENE RATHER THAN AN ADDON-OWNED ONE, which the loop above already
# ran. An addon-owned test runs in BOTH projects, and the sprite rig's arm asserts what
# the addon does when the host declares no content root — a claim the host FALSIFIES,
# because `godot-learning/project.godot` always declares one. A test that can only be
# true in the stranger project belongs to the stranger project. That is ADR-0194 dec. 4's
# rule read in the other direction, and it is why the arm is here and not in
# `addons/exmateria_sprite_rig/tests/`.
#
# The subject is the STAGED copy, so the paths are the repo-relative ones the staging
# note above preserves.
shopt -s nullglob
rigown=("$WORK/$RIGREL"/*.tscn)
shopt -u nullglob
echo "[stranger:$ADDON] rig-owned scenes: ${#rigown[@]}"
for t in "${rigown[@]}"; do
    stem="$(basename "$t" .tscn)"
    run_scene "$RUN_GODOT" "res://$RIGREL/$stem.tscn" "$stem"
done

# --- dec. 7's absence arm ----------------------------------------------------
# 🔴 THE ARM CHECKS THE RUN ENGINE; ONLY THE RIG KNOWS WHOSE CLAIM THAT IS.
# `stranger_fork_absent.gd` is subject-independent by construction, so it can report
# that the primitives are absent from stock and nothing more. Which DECLARATION that
# fact underwrites depends on SUBJECT_ENGINE vs ENGINE, and only this file holds both.
# Until #1099 the scene ended its PASS line with *"so this addon's `engine="fork"`
# declaration is a checked fact"* and the rig let it stand — a false sentence for
# `exmateria_catalogue`, whose `plugin.cfg` declares "stock". Thirteen lines above,
# this file argues the two must never be read as one; that line read them as one.
if [[ "$ENGINE" == "fork" ]]; then
    echo "[stranger:$ADDON] fork requirement, checked against $("$GODOT_STOCK" --version)"
    # No import pass here on purpose: this arm asks the ENGINE what it has, not
    # the project what it loaded, and importing the addon on stock would fill the
    # log with the very failures the declaration predicts.
    run_scene "$GODOT_STOCK" "res://tests/stranger/shared/stranger_fork_absent.tscn" "stranger_fork_absent"
    if [[ "$SUBJECT_ENGINE" == "fork" ]]; then
        echo "[stranger:$ADDON]         so $ADDON's own engine=\"fork\" declaration is a checked fact"
    else
        echo "[stranger:$ADDON]         ⚠ that underwrites the CLOSURE's fork requirement, NOT this"
        echo "[stranger:$ADDON]         subject's declaration: $ADDON declares engine=\"$SUBJECT_ENGINE\", and"
        echo "[stranger:$ADDON]         nothing here checks it. The install pass used to — it ran on the"
        echo "[stranger:$ADDON]         stock binary — and stopped when the run followed the closure."
        echo "[stranger:$ADDON]         Goal #5 is UNMET on the declaration axis for $ADDON (#1099)."
    fi
fi

exit $rc
