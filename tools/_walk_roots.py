"""The one walk, for the guards that scan source.

`classify_blueprint.WALK_ROOTS` is the single definition of "the source this
refactor owns" (ADR-0146 dec. 5): `src/`, `assets/`, and each addon the refactor
itself produced. It deliberately EXCLUDES `addons/exmateria_sound/`, which is a
vendored copy of another package (issue #326).

Extraction #1 found that the GUARDS have the hole ADR-0146 dec. 5 closed for the
census instruments. A scan root of `assets/shaders` or `src` stops covering a
file the moment that file is extracted, and it does so SILENTLY — the guard goes
green because it no longer looks. Reproduced before it was fixed:
`depth_debug.gdshader` moved into `addons/exmateria_render/`, and a raw
`DEPTH = 0.5;` with the seam `#include` deleted passed `check_depth_shaders.py`.

Scanning `addons/` wholesale is NOT the fix, and this was measured too: it drags
in the vendored sound addon, whose asset-path resolver legitimately reads eight
environment variables, and `check_no_env_vars.py` went red immediately. The
question "which source does this refactor own" already has one answer; the guards
read it rather than re-answering it once per guard.

`classify_blueprint.py` ends in `sys.exit()` and walks relative paths, so it is
exec'd from PROJECT_DIR with that exit caught — the pattern `tools/touch_matrix.py`
established. Pure stdlib.

AND THE OTHER HALF: `extracted_roots()`, WHERE THE SOURCE THAT LEFT WENT.

`WALK_ROOTS` answers "which source does this refactor own". A system that extracts
into a PUBLISHED PACKAGE leaves it — `exmateria-sound/addons/exmateria_sound/` is
outside the walk and stays outside it — and **five instruments go blind at that
boundary**: `check_baseline.py --delta`, `closure.py`/`residue.py`,
`score_goals.py`, `check_addon_portability.py` and
`check_debug_panel_tunables.py`. Each needs the same fact, "where did system X
actually go", and three of them had already begun hardcoding the path in prose.
Answering it three times is how three answers drift apart, so it is answered once,
here, beside the exclusion that creates the need for it.

**It is DECLARED, not derived, and that is deliberate.** The obvious derivation is
the `addons/exmateria_sound` symlink in the host — and that symlink is a
per-worktree artifact in `.git/info/exclude`, written by
`tools/link_worktree_godot_assets.sh`. Deriving from it means a fresh clone
derives an EMPTY list and every consumer reports clean, which is the exact defect
this table exists to close.

**A declared path that does not exist is LOUD.** `extracted_roots()` raises rather
than skipping: an entry that silently drops is worse than no entry, because the
consumers read a short list as "nothing to check".
"""
import contextlib, io, os, pathlib, re

PROJECT_DIR = pathlib.Path(__file__).resolve().parent.parent


def walk_files(root):
    """Every file under `root`, **descending into symlinked directories**.

    `pathlib.Path.rglob` does not follow a symlinked directory — it `scandir`s
    the root, then recurses only where `entry.is_dir() and not
    entry.is_symlink()`. That is the right default for a general glob and the
    wrong one for every instrument here, because the host's
    `addons/exmateria_sound` is a REAL directory in the canonical worktree
    (rsync'd by `tools/sync_exmateria_sound.sh`) and a SYMLINK in every worktree
    built by `tools/link_worktree_godot_assets.sh:161`. Measured, same commit:

        linked worktree     `Path(".").rglob("*.gd")`   ->    8 addon .gd
        canonical worktree  `Path(".").rglob("*.gd")`   ->  164 addon .gd

    So an instrument rooted at `.` reads a DIFFERENT universe depending on which
    checkout it runs in, and the smaller reading is the quiet one: `closure.py`
    printed `SEED MISSING - addons/exmateria_sound/runtime/audio_engine.gd` to
    stderr and carried on, which made `scoped_tests.py --depth 3 --run` silently
    under-report the reachable test set in exactly the worktrees the refactor
    loop runs in. Same failure class as `check_addon_portability.py` going green
    because it stopped looking (ADR-0148).

    Rooting a walk AT the symlink is not affected — `Path("addons/exmateria_sound")
    .rglob("*")` scandirs that path directly and sees all 156 files. It is only
    a walk that has to *pass through* the link that goes blind, which is why
    `score_goals.py` and `check_addon_portability.py` were always correct here
    and `closure.py` / `check_root_set.py` were not.

    Cycles: following links can revisit a directory forever, so each directory
    is entered once by its resolved identity.
    """
    root = pathlib.Path(root)
    seen = set()
    for dirpath, dirnames, filenames in os.walk(root, followlinks=True):
        key = os.path.realpath(dirpath)
        if key in seen:
            dirnames[:] = []
            continue
        seen.add(key)
        for name in filenames:
            q = pathlib.Path(dirpath) / name
            if q.is_file():          # drops broken symlinks, as rglob+is_file did
                yield q


def walk_roots() -> list[pathlib.Path]:
    """Absolute paths of classify_blueprint.WALK_ROOTS, in its order."""
    src = (PROJECT_DIR / "tools" / "classify_blueprint.py").read_text(encoding="utf-8")
    ns = {"__name__": "cbmod"}
    cwd = os.getcwd()
    try:
        os.chdir(PROJECT_DIR)
        with contextlib.redirect_stdout(io.StringIO()):
            try:
                exec(compile(src, "classify_blueprint.py", "exec"), ns)
            except SystemExit:
                pass
    finally:
        os.chdir(cwd)
    return [PROJECT_DIR / r for r in ns["WALK_ROOTS"]]


def addon_roots() -> list[pathlib.Path]:
    """Just the addon members of the walk — the refactor's own output."""
    return [p for p in walk_roots() if p.parent.name == "addons"]


# (system, paths relative to PROJECT_DIR in preference order, why not the host's
# copy). TWO paths per row since the extraction: the SIBLING package when this is
# the monorepo, and `vendor/` when it is the standalone bring-your-own-ISO repo,
# where `../exmateria-sound/` does not exist. First one present wins; the vendored
# copy is checked against the sibling by tools/check_vendor_sync.py whenever both
# are there, so "which one resolved" can never change what is read.
# One row per system that has left the walk. `docs/BASELINE.tsv` already carries
# the row CLASS — `exmateria_sound  extracted  152  15961` — measured from this
# path and not from the host's drifted copy; what it does not carry is the path
# itself or which system it is. That is what this adds.
EXTRACTED = (
    ("Audio", ("../exmateria-sound/addons/exmateria_sound", "vendor/exmateria_sound"),
     "ADR-0131 dec. 8 — BASELINE.tsv's `extracted` row is read from the canonical "
     "package. The host's `addons/exmateria_sound` is a DEPLOYMENT COPY of it, "
     "gitignored at godot-learning/.gitignore:3 and written by "
     "tools/sync_exmateria_sound.sh (a real rsync'd directory in the canonical "
     "worktree; a symlink in a secondary one, from link_worktree_godot_assets.sh). "
     "Walking it would double-count (#326)"),
    ("Audio", ("../exmateria-sound/addons/exmateria_spu", "vendor/exmateria_spu"),
     "#384 split the generic PSX SPU out of the sound addon. Same deployment-copy "
     "story as the row above and the same gitignore/sync/link path — and it is a "
     "HARD dependency of it, because `Spu` is a global class_name the sound addon "
     "names in 11 files. Syncing one without the other is a parse-error cascade, "
     "so both rows exist and both are checked"),
)


class Extracted:
    """One system that has left the walk: `.system`, `.path`, `.why`.

    DELIBERATELY NOT A TUPLE, and the reason is a collision that actually
    happened. Extraction #2 independently built an `extracted_roots()` in this
    same module returning `(name, path, present: bool)` while this one returned
    `(system, path, why: str)`. Same module, same function name, both 3-tuples —
    so whichever survived a merge would unpack positionally into the other's
    consumers and bind a **string** to `present`, which is always truthy, and the
    "package is absent from this checkout" branch would die **without a word**.
    Git conflicts on neither: the two definitions sit in different parts of the
    file, and the call sites are in different files entirely.

    An object that cannot be unpacked turns that into a `TypeError` on the first
    line that tries. A list of these read as "nothing to check" is the failure
    this whole table exists to prevent; reproducing it *inside* the table would
    have been the joke writing itself.
    """
    __slots__ = ("system", "path", "why")

    def __init__(self, system: str, path: pathlib.Path, why: str):
        self.system, self.path, self.why = system, path, why

    def __repr__(self) -> str:
        return f"Extracted({self.system!r}, {self.path.as_posix()!r})"


def extracted_roots() -> list["Extracted"]:
    """Every system that has left the walk, as `Extracted` records.

    Raises if a declared path is missing. A consumer reads a short list as
    "nothing more to check", so an entry that quietly disappears is worse than an
    entry that was never written.
    """
    out = []
    for system, rels, why in EXTRACTED:
        for rel in rels:
            q = (PROJECT_DIR / rel).resolve()
            if q.is_dir():
                out.append(Extracted(system, q, why))
                break
        else:
            tried = ", ".join(rels)
            raise FileNotFoundError(
                f"_walk_roots.EXTRACTED names {system} at none of [{tried}], so it "
                f"resolved nowhere under {PROJECT_DIR}. Fix a path or remove the row "
                f"— do not let it fail quietly, because every consumer reads a short "
                f"list as 'nothing to check'. In a standalone checkout the second "
                f"path is the vendored copy; run tools/vendor_packages.sh to make it.")
    return out


# --- THE TIER, DECLARED ------------------------------------------------------
# The four tiers an addon root can belong to. A tier is a fact about the PACKAGE,
# so it is declared in the package's own `plugin.cfg` beside `engine=` (ADR-0194
# dec. 7) and `deps=` — both of which sit there for the same reason: a rig that
# STAGES this addon can read them, and a table in `tools/` does not travel with
# the package. ADR-0202 dec. 4's shape — `plugin.cfg` could not express a
# dependency, so the README carried the claim, and a claim stated nowhere is one
# the next installer discovers by crash.
#
# 🔴 IT REPLACES A MAJORITY VOTE THAT WAS WRONG BY CONSTRUCTION (#1059).
# `check_addon_portability._system_of` used to answer "is this addon one of the
# eleven" by taking the modal `classify()` bucket over the addon's own files.
# `classify()` books a file to the system that CONSUMES it (ADR-0243 dec. 3), so
# a package of tables inherits the names of its READERS, and the proxy agreed
# with the intent only while the only non-system addons were the kernel and the
# port. Measured 2026-09-09 at `c6549fd4c` over `addons/exmateria_almanac`:
# Battle 14 / content 11 / UI 5 / infrastructure 2 / generated 2 — so the vote
# called the almanac "the Battle system's addon" while SEVEN of the eleven
# systems reach it (Battle 274 lines, UI 265, Character Catalogue 56, Cutscene 8,
# Audio 6, Effects 6, Campaign 3, plus `assembler` 69 and `content` 11, which are
# buckets and not systems) and its top two consumers are 3.4% apart.
#
# AND IT IS BLIND IN THE OTHER DIRECTION TOO, which the almanac's row hides. Both
# extracted roots classify to `None` for ALL 163 of their source files, because they sit
# outside `classify_blueprint`'s walk entirely: on the vote alone
# `exmateria_sound` reads as a non-system, which is the FREE set. Only
# `EXTRACTED` above stops that, and it stops it for two roots by name. The vote
# has never once answered this question for a package it had not been told about.
TIERS = ("kernel", "port", "system", "rules")

# The two tiers every addon is allowed to name: a shared vocabulary is not
# coupling, and neither is reaching the platform port. The rule is STATED in
# ADR-0202 dec. 2; ADR-0139 dec. 8 says `the kernel is not a system` and none of
# its fourteen decisions says the rest, so do not re-cite the `dec. 9, dec. 12`
# pair the older comments in this tree carry (ADR-0271 dec. 10). This is the set `check_addon_portability`'s arms 1, 2b, 4b and 5 all
# meant by `system_of[addon] is None`.
#
# `rules` is OUTSIDE it, deliberately: a fourth tier is not automatically a free
# one. Freeing the whole package would blind arm 5 to a surface that is measurably
# SHARED rather than owned — of the almanac's 698 consumed lines, 581 (83%) sit on
# members that two or more of the eleven reach, and only 40% of the total is a
# `*Database`. `GambitCondition` is UI 44 / Battle 30, `Gambit` is Battle 35 /
# UI 22, `TargetSelector` is Battle 43 / UI 34: ADR-0115 dec. 6's warning that a
# feature threads SYSTEMS, not ADR-0115 dec. 4's content shadow. (Dec. 6's own
# count is THREE and its own example is gambits; `two` here was a paraphrase
# nobody had opened the file to check -- ADR-0273 dec. 6.)
#
# #1059 phase 2 (ADR-0273) did NOT resolve that by widening this set. It asks the
# free question of the MEMBER instead — see `MEMBER_FREE_KINDS` below — so this
# frozenset still holds exactly the two tiers that are free WHOLESALE.
PORTABLE_TIERS = frozenset(("kernel", "port"))

# --- #1059 phase 2: free-ness inside the `rules` tier is per MEMBER ----------
#
# `PORTABLE_TIERS` frees a whole PACKAGE, and the two it holds earn that: every
# member of the kernel is shared vocabulary and every member of the port is the
# platform seam. `rules` cannot be freed that way and ADR-0271 dec. 5 priced it
# rather than arguing it -- of the almanac's ~700 consumed lines, 83% sit on
# members two or more of the eleven reach, so a wholesale free verdict would
# silence ADR-0115 dec. 6's warning that a feature threads SYSTEMS -- dec. 6's own
# example is gambits and its own count is THREE, not the two the older comments in
# this tree paraphrase (ADR-0273 dec. 6). Adding
# `rules` here is ADR-0271's REJECTED alternative and the pricing arm in
# `test_check_addon_portability.py` still fires on it.
#
# What ADR-0115 dec. 7 draws instead is a line INSIDE the package -- *"the driver
# ships, the banks are content"*:
#
#   table  a bank. Every answer it returns is STORED -- a ROM table, a projection
#          of one, or a fixed vocabulary. A system reading it is reading its own
#          content shadow, which ADR-0115 dec. 4 says is expected. FREE.
#   rule   a driver. It COMPUTES an answer the ROM computes rather than stores.
#          Two systems sharing one is dec. 6's threaded feature. PRINTED.
#   state  per-playthrough state, which is not a rule about the game at all and
#          is the membership defect ADR-0271 soft spot S4 names. PRINTED, and the
#          printing is what kept #1059 phase 3 / #1060 visible until both were
#          RULED: ADR-0280 dec. 2 refuses #1060's move and ADR-0300 refuses phase
#          3's, so the printing now holds an accepted price with a floor of 13
#          rather than a pending pass.
#
# 🔴 TIES GO TO `rule`, AND THE ASYMMETRY IS THE REASON. A member wrongly called
# `rule` costs a printed line somebody can falsify; one wrongly called `table`
# costs SILENCE, and ADR-0271 dec. 5's own sentence is that *"a wrong bucket is a
# claim someone can falsify, and silence is not"*. Declare the member's PRIMARY
# answer and take `rule` where the two readings are close.
MEMBER_KINDS = ("table", "rule", "state")
MEMBER_FREE_KINDS = frozenset(("table",))

# `const MEMBER_KINDS := { "Name": "kind", ... }` on a facade. Deliberately as
# strict as `_TIER_RE`, and for the same reason: a reader that accepted a looser
# spelling than the file's own would let a declaration land that nothing else can
# see. The pairs are matched inside the brace span rather than by a single
# multiline pattern, so a stray `}` in a comment cannot silently truncate the map.
_MEMBER_KINDS_OPEN = re.compile(r'^const\s+MEMBER_KINDS\s*:?=\s*\{[ \t]*$', re.M)
_MEMBER_KIND_PAIR = re.compile(r'^\s*"([A-Za-z_][A-Za-z0-9_]*)"\s*:\s*"([a-z]+)"\s*,\s*$')


def declared_member_kinds(root: pathlib.Path) -> dict:
    """`{member: kind}` the facade of this addon root DECLARES. RAISES if it does not.

    `declared_tier()`'s rule one level in, for its reason. The tier says which
    QUESTION a package answers; inside `rules` the free set is per member, so a
    consumer that read a missing or malformed map as a default would be scoring an
    enforcing arm on an inference -- which is the whole defect #1059 removes.

    The facade is folder-named (ADR-0212 dec. 1), so its address is derivable and
    is not a second thing to declare. RECONCILIATION AGAINST THE PUBLISHED LIST IS
    THE CALLER'S, and it is not optional: this function cannot see
    `published_members()`, so on its own it would happily return a map that named
    six of thirty-one. `check_addon_portability` holds both directions.
    """
    facade = root / (root.name + ".gd")
    if not facade.is_file():
        raise FileNotFoundError(
            f"_walk_roots.declared_member_kinds: {_p(root)} has no folder-named facade "
            f"at {facade.name}, so its members declare no kind. ADR-0212 dec. 1 makes "
            f"the facade's address the folder's name; a `rules`-tier package without "
            f"one cannot be scored per member.")
    txt = facade.read_text(encoding="utf-8", errors="replace")
    m = _MEMBER_KINDS_OPEN.search(txt)
    if m is None:
        raise ValueError(
            f"_walk_roots.declared_member_kinds: {_p(facade)} declares no "
            f"`const MEMBER_KINDS := {{`. Every member a `rules`-tier facade publishes "
            f"must declare one of {MEMBER_KINDS} -- {sorted(MEMBER_FREE_KINDS)} is free "
            f"and the rest stay printed, so an undeclared member is a silent verdict.")
    out = {}
    for ln in txt[m.end():].splitlines():
        if ln.startswith("}"):
            break
        if not ln.strip() or ln.lstrip().startswith("#"):
            continue
        pair = _MEMBER_KIND_PAIR.match(ln)
        if pair is None:
            raise ValueError(
                f"_walk_roots.declared_member_kinds: {_p(facade)} has a line inside "
                f"MEMBER_KINDS this reader cannot parse: {ln!r}. The spelling is "
                f'`    "Name": "kind",` -- one pair per line, trailing comma, nothing '
                f"else. A looser reader here than the file writes is how a declaration "
                f"lands that nothing checks.")
        name, kind = pair.group(1), pair.group(2)
        if kind not in MEMBER_KINDS:
            raise ValueError(
                f"_walk_roots.declared_member_kinds: {_p(facade)} declares "
                f'"{name}": "{kind}", which is not one of {MEMBER_KINDS}.')
        if name in out:
            raise ValueError(
                f"_walk_roots.declared_member_kinds: {_p(facade)} declares "
                f'"{name}" twice -- the second wins in GDScript and the reader would '
                f"pick a kind by file order.")
        out[name] = kind
    if not out:
        raise ValueError(
            f"_walk_roots.declared_member_kinds: {_p(facade)}'s MEMBER_KINDS is EMPTY. "
            f"An empty map frees nothing and reads exactly like a package whose members "
            f"are all `rule`, which is a verdict rather than an absence.")
    return out

# The `engine=`/`deps=` spelling verbatim: a bare key at column 0, one quoted
# lower-case word, nothing else on the line. `tests/stranger/shared/rig.sh` reads
# its two keys with exactly this shape (`sed -n 's/^engine="\([a-z]*\)"...'`), and
# a reader that accepted a looser spelling here than the rig does there would let
# a declaration land that the rig cannot see.
_TIER_RE = re.compile(r'^tier\s*=\s*"([a-z]+)"[ \t]*$', re.M)


def declared_tier(root: pathlib.Path) -> str:
    """The `tier=` this addon root's own `plugin.cfg` declares. RAISES if it does not.

    Loud on absence, on `extracted_roots()`'s rule and for its reason. A consumer
    that reads a missing declaration as a default reads it as ONE OF THE FOUR
    ANSWERS, and three of the four move an ENFORCING guard's verdict: `kernel` and
    `port` free every reach INTO the package, `system` and `rules` do not. An
    addon that joins the walk without a tier is precisely the case this exists to
    catch — #1059 is that case, four years of it — so it fails at the first read
    rather than being scored as whatever the default happened to be.
    """
    cfg = root / "plugin.cfg"
    if not cfg.is_file():
        raise FileNotFoundError(
            f"_walk_roots.declared_tier: {_p(root)} has no plugin.cfg, so it declares "
            f"no tier. Every addon root the guards walk must declare one of {TIERS} — "
            f"an undeclared root is scored by inference, which is the defect #1059 "
            f"exists to remove.")
    m = _TIER_RE.search(cfg.read_text(encoding="utf-8", errors="replace"))
    if m is None:
        raise ValueError(
            f"_walk_roots.declared_tier: {_p(root)}/plugin.cfg declares no `tier=`. "
            f"Add one of {TIERS} on its own line, with the reasoning inline the way "
            f"`engine=` and `deps=` carry theirs. Do NOT default it: `kernel`/`port` "
            f"free every reach into this package and `system`/`rules` do not, so a "
            f"default is a silent verdict on an enforcing guard.")
    if m.group(1) not in TIERS:
        raise ValueError(
            f"_walk_roots.declared_tier: {_p(root)}/plugin.cfg declares "
            f'tier="{m.group(1)}", which is not one of {TIERS}.')
    return m.group(1)


def tiers() -> dict:
    """`{resolved addon root: tier}` for every root the portability guards walk.

    In-walk roots and extracted ones alike, and the pairing is the point: the two
    populations are declared in different places (`classify_blueprint.WALK_ROOTS`
    and `EXTRACTED` above) and are read here through ONE map, so a caller cannot
    ask the question of one population and silently miss the other. That is the
    shape `rigs()` below already uses for its own join.
    """
    roots = addon_roots() + [e.path for e in extracted_roots()]
    return {r.resolve(): declared_tier(r) for r in roots}


# --- THE ENGINE AND THE DEPENDENCIES, DECLARED -------------------------------
# `engine=` (ADR-0194 dec. 7) and `deps=` sit in `plugin.cfg` for `tier=`'s reason:
# they are facts about the PACKAGE, stated where a rig that STAGES the package can
# read them, and a table in `tools/` does not travel with the package.
#
# 🔴 UNTIL #1241 NOTHING IN `tools/` READ EITHER ONE. `tests/stranger/shared/rig.sh`
# was the SOLE consumer of both keys — `check_addon_portability.py`,
# `check_addon_globals.py` and this module mentioned `deps=` in comments and nowhere
# else — so the only instrument that could see a `deps=` edit was a rig that boots
# Godot twice. #1239 is what that costs: `exmateria_catalogue` declared
# `exmateria_sprite_rig` as a dependency it had not reached since #1071, the claim
# survived 474 commits, and finding it took a session of hand-verification.
#
# THESE ARE THE SECOND READING OF A FILE THE RIG ALREADY READS, and the rule is
# `_TIER_RE`'s above, applied literally: the spelling here is `rig.sh`'s `sed`
# VERBATIM — a bare key at column 0, one double-quoted value, nothing else on the
# line. A reader that accepted a looser spelling than the rig does would let a
# declaration land that the rig cannot see, which is a guard green on a key its
# consumer ignores. `test_the_python_reader_and_the_rigs_sed_agree` diffs the two
# readings on every `plugin.cfg` in the tree rather than trusting this paragraph
# (`known_failure_rows` above carries the same two-readings rule for
# `known_failures.tsv`; that one is held by a comment because the other reader is
# GDScript, and this one is held by a test because the other reader is `sed`).
ENGINES = ("stock", "fork")

# `sed -n 's/^engine="\([a-z]*\)"[[:space:]]*$/\1/p'` and
# `sed -n 's/^deps="\(.*\)"[[:space:]]*$/\1/p'`, which is what `rig.sh` runs. Note
# `engine=` takes `[a-z]*` and `deps=` takes `.*`: a deps line is a space-separated
# LIST, so the value is not one lower-case word and must not be read as one.
_ENGINE_RE = re.compile(r'^engine="([a-z]*)"[ \t]*$', re.M)
_DEPS_RE = re.compile(r'^deps="(.*)"[ \t]*$', re.M)


def declared_engine(root: pathlib.Path) -> str:
    """The `engine=` this addon root's own `plugin.cfg` declares. RAISES if it does not.

    Loud on absence, on `declared_tier()`'s rule and for the same reason — and here
    the rule is not this module's invention: `rig.sh` itself exits 2 rather than
    defaulting, *"because a default is how the declaration stops being read"*. A
    Python reader that returned `"stock"` for a missing key would answer a question
    the rig refuses to answer, and the two instruments would disagree about which
    binary an addon needs.
    """
    cfg = root / "plugin.cfg"
    if not cfg.is_file():
        raise FileNotFoundError(
            f"_walk_roots.declared_engine: {_p(root)} has no plugin.cfg, so it declares "
            f"no engine. `tests/stranger/shared/rig.sh` exits 2 on this; so does this.")
    m = _ENGINE_RE.search(cfg.read_text(encoding="utf-8", errors="replace"))
    if m is None:
        raise ValueError(
            f"_walk_roots.declared_engine: {_p(root)}/plugin.cfg declares no `engine=`. "
            f"Add one of {ENGINES} on its own line with the measurement inline, the way "
            f"the shipped ones carry theirs (ADR-0194 dec. 7). Do NOT default it: the "
            f"rig boots the declared binary, and a default is the rig deciding a fact "
            f"about the addon.")
    if m.group(1) not in ENGINES:
        raise ValueError(
            f"_walk_roots.declared_engine: {_p(root)}/plugin.cfg declares "
            f'engine="{m.group(1)}", which is not one of {ENGINES}.')
    return m.group(1)


def declared_deps(root: pathlib.Path) -> list[str]:
    """The `deps=` list this addon root declares — sibling addon DIRECTORY NAMES.

    `[]` FOR AN ABSENT KEY, and that is the one place this reader is deliberately
    quiet where `declared_engine` is loud. The difference is `rig.sh`'s own: *"an
    addon with no line has no deps; an addon that names one that is not there cannot
    run"*. An absent `engine=` leaves the rig with no binary to boot, so it is
    unanswerable; an absent `deps=` has one correct answer and four of the nine roots
    in this tree give it.

    RAISES on a named dep with no directory, which is `rig.sh`'s second sentence and
    its exit 2. Resolved against `PROJECT_DIR/addons/` rather than against the root's
    own parent, because that is the address the rig stages from (`$PKG/addons/$d`) —
    for an EXTRACTED root the two differ, and the rig's is the one that decides.
    """
    cfg = root / "plugin.cfg"
    if not cfg.is_file():
        raise FileNotFoundError(
            f"_walk_roots.declared_deps: {_p(root)} has no plugin.cfg, so it declares "
            f"no dependencies. An addon root the guards walk has one.")
    m = _DEPS_RE.search(cfg.read_text(encoding="utf-8", errors="replace"))
    names = m.group(1).split() if m else []
    for d in names:
        if not (PROJECT_DIR / "addons" / d).is_dir():
            raise ValueError(
                f"_walk_roots.declared_deps: {_p(root)}/plugin.cfg declares "
                f'deps="{m.group(1)}", and `{d}` is not at addons/{d}. '
                f"`tests/stranger/shared/rig.sh` exits 2 on this; so does this.")
    return names


def dep_closure(root: pathlib.Path) -> list[str]:
    """The TRANSITIVE closure of `deps=` — what a consumer has to unzip, in rig order.

    🔴 THE CLOSURE, NOT THE LINE, and `rig.sh` carries the finding at length: until
    2026-09-08 it staged the declared line alone, which was indistinguishable from
    correct while every declared dep was a LEAF. `exmateria_catalogue` (#1025 pass 3)
    is the first addon whose deps have deps, and staging the line alone put the rig in
    a project where a STAGED addon could not parse.

    Breadth-first with the dedup taken at POP time, which is `rig.sh`'s loop verbatim
    — the ORDER is part of the answer, because the rig prints this list in its banner
    and a reader diffing the banner against this guard's report needs the two to be
    the same string, not the same set.
    """
    closure: list[str] = []
    queue = list(declared_deps(root))
    while queue:
        nxt: list[str] = []
        for d in queue:
            if d in closure:
                continue
            closure.append(d)
            nxt.extend(declared_deps(PROJECT_DIR / "addons" / d))
        queue = nxt
    return closure


def closure_engine(root: pathlib.Path) -> str:
    """The engine the RIG BOOTS for this root: `fork` if the subject or ANY closure
    member declares `fork`, else `stock`.

    🔴 THE BINARY FOLLOWS THE CLOSURE AND THE DECLARATION STAYS THE SUBJECT'S, and
    the two are different facts (`rig.sh`, "AND THE ENGINE IS THE CLOSURE'S, NOT THE
    SUBJECT'S"). `engine=` is a measured claim about the files in ONE addon; the
    binary has to parse everything the rig STAGES. So a `deps=` edit is a possible
    ENGINE change, which is #1241's defect: dropping `exmateria_sprite_rig` (`fork`)
    from the catalogue would have flipped that rig to a stock binary, and it did not
    only because #1180 had already added `exmateria_schema` (also `fork`) as a direct
    dep. Unchanged by accident, not by design, with nothing announcing either way.
    """
    engine = declared_engine(root)
    for d in dep_closure(root):
        if declared_engine(PROJECT_DIR / "addons" / d) == "fork":
            engine = "fork"
    return engine


# (addon root, its stranger rig's `run.sh`, why the rig lives there). Both paths
# are relative to PROJECT_DIR. ONE ROW PER ADDON ROOT, and the rows ARE the join
# ADR-0229 dec. 8 filed as missing: `_runner_tests.stranger_rigs()` globs
# `tests/stranger/*/run.sh`, `addon_roots()` and `EXTRACTED` above list the roots,
# and until this table nothing said which root a rig belonged to. That gap is how
# the fifth rig went unnoticed while `tests/stranger/README.md` still said "All
# four", and it is the same two-registers-no-join shape that let `docs/GOALS.tsv`
# score `Sprite Rig` goal #5 `met` while the rig printed UNMET (ADR-0232).
#
# TWO HOMES, DECLARED RATHER THAN RELOCATED. `EXTRACTED` above is the precedent:
# when `Audio` left the walk this repo declared the second home WITH ITS REASON
# instead of moving the source back. The two `Audio` rigs cannot simply move into
# `tests/stranger/` -- measured, not assumed:
#
#   * they run STOCK Godot on purpose. `run.sh` requires `GODOT_STOCK` and refuses
#     to fall back to `godot` on PATH, because that is the game's 4.8 compositor
#     fork and the whole claim these rigs buy is the opposite one. Every
#     `tests/stranger/*/run.sh` runs the fork.
#   * they need `publish/publish.sh exmateria-sound stage` and a scons-built
#     native library (`addons/exmateria_spu/bin/libexmateria_spu.*`), and exit 2
#     -- "could not run" -- without them. `tests/stranger/` rigs need neither, and
#     the suite's final phase treats a non-zero rig as a FAIL.
#   * they compute `PKG`/`ROOT`/`DIST`/`SRC_ADDON` by walking up from their own
#     location, so the move is a path rewrite in every one of them.
#   * they carry their own `../shared/` -- `readme_check.gd` and
#     `facade_lookup.gd` -- which is a DIFFERENT shared directory from
#     `tests/stranger/shared/`'s four-arm contract, and `stranger_rigs()` excludes
#     `shared/` by name, so the two cannot sit side by side unmerged.
#   * `stranger_rigs()` keys a rig by DIRECTORY NAME = ADDON NAME, which is what
#     makes this table a lookup at all. `stranger_sound` and `stranger_spu` are
#     not addon names, and `exmateria_spu` under `tests/stranger/` would name a
#     root that lives outside `godot-learning/` entirely.
#   * `exmateria-sound/` is deliberately outside the walk (see the module
#     docstring: walking it turns `check_no_env_vars.py` red), and `run.sh` reads
#     `GODOT_STOCK` from the environment.
#
# So `in_suite` below is FALSE for those two and every consumer must say so rather
# than read their empty debt as a passing run.
RIGS = (
    ("addons/exmateria_battlefield", "tests/stranger/exmateria_battlefield/run.sh", ""),
    ("addons/exmateria_platform", "tests/stranger/exmateria_platform/run.sh", ""),
    ("addons/exmateria_render", "tests/stranger/exmateria_render/run.sh", ""),
    ("addons/exmateria_schema", "tests/stranger/exmateria_schema/run.sh", ""),
    ("addons/exmateria_sprite_rig", "tests/stranger/exmateria_sprite_rig/run.sh", ""),
    ("addons/exmateria_almanac", "tests/stranger/exmateria_almanac/run.sh", ""),
    ("addons/exmateria_catalogue", "tests/stranger/exmateria_catalogue/run.sh", ""),
    ("addons/exmateria_effects", "tests/stranger/exmateria_effects/run.sh", ""),
    ("../exmateria-sound/addons/exmateria_sound",
     "../exmateria-sound/workspace/acceptance/stranger_sound/run.sh",
     "the package left the walk (EXTRACTED above) and its rig left with it; stock "
     "Godot + a staged publish, so the suite does not run it"),
    ("../exmateria-sound/addons/exmateria_spu",
     "../exmateria-sound/workspace/acceptance/stranger_spu/run.sh",
     "same package, and #384 split the SPU out with its own rig; additionally needs "
     "a scons-built native library, so the suite does not run it"),
)


class Rig:
    """One addon root's stranger rig: `.root`, `.run_sh`, `.why`, `.in_suite`.

    Not a tuple, for the reason `Extracted` above spells out at length.
    """
    __slots__ = ("root", "run_sh", "why")

    def __init__(self, root: pathlib.Path, run_sh: pathlib.Path, why: str):
        self.root, self.run_sh, self.why = root, run_sh, why

    def __repr__(self) -> str:
        return f"Rig({self.root.name!r}, {self.run_sh.as_posix()!r})"

    @property
    def in_suite(self) -> bool:
        """True iff `_runner_tests.stranger_rigs()`' glob finds this rig.

        The suite's final phase runs THAT glob, so a rig outside `tests/stranger/`
        is declared here and run by hand. A consumer that reports "no declared
        debt" without reporting this is reporting a file, not a run.
        """
        return self.run_sh.parent.parent == (PROJECT_DIR / "tests" / "stranger").resolve()

    @property
    def known_failures(self):
        """The rig's `known_failures.tsv`, or None if it declares no debt."""
        q = self.run_sh.parent / "known_failures.tsv"
        return q if q.is_file() else None

    def known_failure_rows(self) -> list:
        """`[(res_path, ticket), ...]` -- the rig's DECLARED portability debt.

        \U0001f534 THE PARSE RULE IS MIRRORED FROM `stranger_burn_down.gd._rows()`
        AND MUST STAY THAT WAY: skip blank lines and `#` comments, and require at
        least FOUR tab-separated fields. The field count is not defensive tidiness
        -- the GDScript drops a short row silently, so a Python reader that
        accepted three fields would report debt the rig itself never checks, and
        the two instruments would disagree about the same file. Two readings of
        one file is what this repo diffs rather than trusts (ADR-0147/0148); they
        are in different languages, so the diff is this comment.

        `rig.sh` counts the same file with a looser rule (`grep -cve '^\\s*#' -e
        '^\\s*$'`, no field-count clause), so a THREE-field row makes it run the
        burn-down scene, which then finds no rows and prints `[FAIL] ... a run with
        nothing to check is not a pass`. The divergence is therefore loud rather
        than silent, and this reader stays aligned with the scene that grades.
        """
        q = self.known_failures
        if q is None:
            return []
        out = []
        for line in q.read_text(encoding="utf-8").splitlines():
            if not line.strip() or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) >= 4:
                path = parts[0]
                out.append((path if path.startswith("res://") else "res://" + path,
                            parts[1]))
        return out


def rigs(table=None, stranger_dir: pathlib.Path = None) -> list["Rig"]:
    """Every addon root's stranger rig, as `Rig` records. Checks THREE directions.

    `table` and `stranger_dir` are injection points for `tools/test_score_goals.py`
    and exist for one reason: all three arms below are RAISES, and an arm nobody
    can seed red is an arm nobody has proven fires. Same shape as
    `_runner_tests.stranger_rigs(stranger_dir=None)` and `addon_roots(addons_dir)`.

    A one-directional register is the defect this table was written for, so it
    raises when:

      1. a declared `run.sh` does not exist -- the `extracted_roots()` rule, for
         the same reason: a consumer reads a short list as "nothing to check".
      2. an addon root has NO row -- a brand-new addon that never grew a rig is
         exactly what went unnoticed before, and the scorecard needs to know the
         difference between "installs clean" and "nobody ever asked".
      3. a `tests/stranger/*/run.sh` exists that no row names -- the sixth rig
         landing without a row would otherwise be invisible here while being run
         by the suite, which is arm 2 with the arrows reversed.

    Arm 3 is deliberately scoped to `tests/stranger/` and not to every path in the
    table: it is the DIFF between this declaration and `_runner_tests`' glob, and
    the glob only looks there.
    """
    out, seen_roots = [], set()
    for root_rel, run_rel, why in (RIGS if table is None else table):
        root = (PROJECT_DIR / root_rel).resolve()
        run_sh = (PROJECT_DIR / run_rel).resolve()
        if not run_sh.is_file():
            raise FileNotFoundError(
                f"_walk_roots.RIGS names a rig for {root_rel} at {run_rel}, which does "
                f"not exist ({run_sh}). Fix the path or remove the row -- do not let it "
                f"fail quietly, because every consumer reads a short list as 'nothing "
                f"to check'.")
        seen_roots.add(root)
        out.append(Rig(root, run_sh, why))
    missing = [_p(r) for r in addon_roots() + [e.path for e in extracted_roots()]
               if r.resolve() not in seen_roots]
    if missing:
        raise AssertionError(
            "_walk_roots.RIGS has no row for %d addon root(s): %s. Every root either "
            "has a stranger rig or is declared as having none -- an absent row reads "
            "as 'installs clean' to tools/score_goals.py goal #5, which is the "
            "ADR-0229 dec. 8 gap this table closes." % (len(missing), ", ".join(missing)))
    sdir = stranger_dir or (PROJECT_DIR / "tests" / "stranger")
    globbed = sorted(sdir.glob("*/run.sh"))
    named = {r.run_sh for r in out}
    stray = [_p(g) for g in globbed if g.parent.name != "shared" and g.resolve() not in named]
    if stray:
        raise AssertionError(
            "%s holds %d rig(s) no _walk_roots.RIGS row names: %s. The suite's final "
            "phase runs them via _runner_tests.stranger_rigs(); this table is the join "
            "that says which addon each one is about."
            % (_p(sdir), len(stray), ", ".join(stray)))
    return out


def rig_for(root: pathlib.Path):
    """The `Rig` for one addon root, or None if the table declares none.

    `None` means NOBODY HAS ASKED whether this addon installs outside the host --
    it does not mean it installs clean. `score_goals.mechanical(5)` turns that
    into `unscorable` rather than into a 0.
    """
    q = root.resolve()
    return next((r for r in rigs() if r.root == q), None)


def _p(q: pathlib.Path) -> str:
    try:
        return q.relative_to(PROJECT_DIR).as_posix()
    except ValueError:
        return q.as_posix()
