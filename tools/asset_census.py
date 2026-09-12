#!/usr/bin/env python3
"""The asset instrument — bytes per owning system, and per packet class.

ADR-0142 dec. 1: *"an asset belongs to the system that owns its FORMAT"* — the
system that would have to change if the bytes' encoding changed — **not** the
system that calls `load()` on it. A reader that is not the format owner is a
crossing, named like any other crossing.

That ADR's Consequences say outright: *"The asset instrument does not exist.
Every figure here came from an ad-hoc census; there is no committed tool,
deliberately"* — because ADR-0131 lands instrument changes together, before the
baseline. This is that tool. Run from the package root.

    python3 tools/asset_census.py [--packets] [--families <root>]

METHOD, exactly the recipe ADR-0142 left behind:

  1. group a packet's files into FAMILIES by normalising digits to `N` and long
     hex runs to `<h>`, keeping the path relative to the packet root, so
     `E317/frames/007.tga` and `E318/frames/031.tga` are one family;
  2. book each family by grepping `src/` for the quoted filename and running the
     hits through `classify_blueprint.py`;
  3. **then override by FORMAT** where the reader is not the format owner —
     which is the whole point of dec. 1, and the step a read-ownership census
     cannot take by itself.

Byte figures are CONTENT bytes: Godot `.import` sidecars and `.uid` files are
generated and excluded, as in every figure ADR-0142 published.

WHAT IT IS NOT. This says who OWNS the bytes. It does not say whether anything
reads them — that is `closure.py`, and the two disagree by design: a packet can
be wholly owned and wholly unread.
"""
import collections, contextlib, importlib.util, io, os, pathlib, re, sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import _walk_roots  # noqa: E402  -- walk_files, NOT os.walk; see content_files()

FMT = re.compile(r'\d+')
HEX = re.compile(r'[0-9a-f]{8,}')
SKIP = (".import", ".uid")

# The byte universe. `assets/` was the whole of it until prologue pass 6 moved
# fold_layer.tres — the compositing key's resource half — into the kernel addon.
# ADR-0146 dec. 5: an instrument whose roots do not follow the refactor's own
# output reports a relocation as a deletion. `addons/exmateria_sound/` stays out
# for the reason ADR-0131 dec. 8 gives (vendored copy, read canonically).
# ADR-0148: this tuple had the very defect its own comment describes — it named
# the kernel addon by hand, so extraction #1's addon would have gone uncounted
# until someone remembered. It is derived from `classify_blueprint.WALK_ROOTS`
# below, once the classifier is loaded, so each extraction joins one tuple.
ASSET_ROOTS = ()
ASSET_ROOTS_LABEL = "assets/ + the refactor's own addons"

# Packet classes: a directory whose immediate children are sibling packets.
# ADR-0142 measured the first three and said so — *"so far one class of two"*,
# then three. `scenarios/` and `sprites/` are 198 MB it never reached.
PACKET_CLASSES = [
    ("assets/effects", "E###"),
    ("assets/characters/templates", "<key>"),
    ("assets/maps", "MAP###"),
    ("assets/scenarios", "mixed"),
    ("assets/sprites", "mixed"),
]

# ADR-0142 dec. 1's override: the system that owns the ENCODING. Longest prefix
# wins. Everything not named here is booked by its readers, and a family with a
# reader in more than one system is reported as a CROSSING rather than split.
FORMAT_OWNER = [
    ("assets/sprites/", "Sprite Rig"),                    # SPR/SHP/SEQ pixel + palette formats
    ("assets/characters/templates/", "Sprite Rig"),       # ADR-0132's own worked case: "UI owns the frame, not the pixels"
    ("assets/maps/", "Battlefield"),                      # the mesh/terrain/illumination formats
    ("assets/effects/", "Effects"),                       # E###.BIN's frameset + emitter encoding
    ("assets/music/", "Audio"),                           # SMD
    ("assets/audio/", "Audio"),                           # FEDS banks
    ("assets/scenarios/", "Cutscene"),                    # the event-script container
    ("assets/fonts/", "UI"),
    ("assets/ui/", "UI"),
    ("assets/doodads/", "Battlefield"),                   # map props, read by src/map/
    ("assets/projectiles/", "Battle"),
    ("assets/feds_", "Audio"),                            # the three top-level FEDS coverage dumps
    # ADR-0138's membership interface, as a resource. It moved into the kernel
    # addon with Fold.gd in prologue pass 6 (ADR-0146 dec. 2) — a member that
    # preloaded a host path would not be promotable (ADR-0139 dec. 10).
    ("addons/exmateria_schema/compositing_key/fold_layer.tres", "schema"),
    # the hand-authored / extracted FFT tables — CONTEXT.md's "Hand-authored data
    # asset". Their `content` classification is the same call src/data/'s stores get
    # (ADR-0144 dec. 2): the table is FFT's, and per ADR-0110 it stays in the host.
    ("assets/abilities/", "content"),
    ("assets/items/", "content"),
    ("assets/roster/", "content"),
    # `assets/jobs/` and `assets/stats/` were two more rows here until extraction #5
    # (#945, `779bc6636`) moved their three payloads beside the databases that read
    # them — `addons/exmateria_almanac/{jobs,progression}/`. They are RETIRED, not
    # repointed, and that is ADR-0251's decision, not a convenience: *"No FORMAT_OWNER
    # entry was added, because adding one for this root and not the other six states a
    # rule the package does not hold."* The almanac reports under `(NO FORMAT RULE)`
    # with every other addon root, which is where the 2.9 MB of payload JSON has been
    # booked since #945 landed — so deleting these two rows moves ZERO bytes between
    # buckets. A prefix matching nothing books nothing; they had already stopped firing.
    # #990 is the cost of leaving them: `check_tool_paths.py` arm 1 is the SILENT half
    # of #744's register and it went LOUD here, aborting the whole pre-flight at the
    # first red guard, ~40 guards upstream of everything else.
    # each .tres binds one shader and belongs where that shader does; four files,
    # three owners, so there is no directory rule to write.
    ("assets/materials/projectile_vertex_color.tres", "Battle"),
    # `tile_cursor_opaque.tres` and `tile_overlay.tres` were `Battlefield` rows here
    # until ADR-0202 dec. 5 moved them INTO `addons/exmateria_battlefield/`, beside the
    # shaders they bind. An addon member is not a host asset, so they are not rows any
    # more — the same reason the kernel addon's members are not counted below.
    ("assets/materials/unit.tres", "Sprite Rig"),
    ("assets/materials/unit_shadow.png", "Battle"),       # src/units/UnitShadow.gd's blob texture
    # not assets. Shader + .gd source is classify_blueprint.py's; the .tscn files
    # under assets/scenes/ are declared, one row each, in docs/ROOT_SET.tsv and
    # guarded by check_root_set.py. Owning them here would double-count them.
    ("assets/shaders/", None),
    ("assets/scenes/", None),
    # the kernel addon's manifest is not an asset either — it is the addon's
    # identity card (ADR-0139 dec. 9), and its .gd/.gdshaderinc/.tres members are
    # booked above and by classify_blueprint.py.
    ("addons/exmateria_schema/plugin.cfg", None),
    # ...and extraction #1's, for the same reason (ADR-0147 dec. 1). The README is
    # deliberately NOT ruled here: the kernel's has reported as unowned since
    # prologue pass 6 and that is a live finding, so silently ruling this one would
    # hide the second instance of it rather than answer it. Two locations now, same
    # question — is an addon's README a content byte at all?
    ("addons/exmateria_render/plugin.cfg", None),
]


def load_classifier():
    spec = importlib.util.spec_from_file_location("cb", "tools/classify_blueprint.py")
    mod = importlib.util.module_from_spec(spec)
    argv = sys.argv
    sys.argv = ["classify_blueprint.py"]
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            spec.loader.exec_module(mod)
    except SystemExit:
        pass
    finally:
        sys.argv = argv
    return mod


cb = load_classifier()


NOT_AN_ASSET = object()


def format_owner(rel):
    """The owning system, None if no rule reaches it, or NOT_AN_ASSET when a rule
    says these bytes are declared by another instrument."""
    best = None
    for pref, owner in FORMAT_OWNER:
        if rel.startswith(pref) and (best is None or len(pref) > len(best[0])):
            best = (pref, owner)
    if best is None:
        return None
    return NOT_AN_ASSET if best[1] is None else best[1]


def content_files(root):
    """Every content byte under `root`, **descending into symlinked directories**.

    This walked with `os.walk(root)` and its default `followlinks=False` until
    extraction #4 pass 3, and that made the whole census a claim about the
    CHECKOUT rather than about the tree. `tools/link_worktree_godot_assets.sh:52-58`
    symlinks `assets/maps`, `assets/music`, `assets/sprites/textures`,
    `assets/scenarios/chunks`, `assets/characters/templates` and
    `assets/effects/E000` from a populated sibling, and a walk that does not
    follow a link reads **zero** through every one of them. Seeded both arms on
    a scratch tree holding one `.tga` behind a symlinked `assets/sprites/textures`:
    the old body yields `[]`, this one yields the file.

    Scale, on this (rsync-form) checkout -- the total is measured, the linked-form
    figure is that total minus the six link targets' own measured sizes, not a
    reading taken in a linked worktree:

        rsync-form checkout   772,430,163 content bytes
        the six link targets  517,332,397          -- 67.0%, silently unread

    and 199,175,800 of the 212,342,240 bytes this instrument books to
    `Sprite Rig` (93.8%) are behind two of those links -- `assets/sprites/textures`
    and `assets/characters/templates` -- so extraction #4's goal #6 question,
    *does the content move with the addon*, was being answered by an instrument
    that reads ~13 MB of it in the worktrees the refactor loop actually runs in.

    Same defect, same fix, same reason as the three ADR generators #731 routed
    through `_walk_roots.walk_files()`: an instrument rooted at `.` must not
    read a different universe per install form. The `.godot` and sidecar filters
    are unchanged.
    """
    for q in _walk_roots.walk_files(root):
        fp = os.fspath(q)
        if ".godot" in os.path.dirname(fp):
            continue
        if not fp.endswith(SKIP):
            yield fp


def family(rel_in_packet, name):
    k = FMT.sub("N", HEX.sub("<h>", name))
    d = os.path.dirname(rel_in_packet)
    return f"{d}/{k}" if d else k


# --- who NAMES each basename, per system -------------------------------------
# ADR-0146 dec. 5 — the same walk roots the source instrument uses, so a reader
# that moved into an addon this refactor produced does not read as no reader.
ASSET_ROOTS = ("assets",) + tuple(r for r in cb.WALK_ROOTS if r.startswith("addons/"))

gd = [q for root in cb.WALK_ROOTS for q in pathlib.Path(root).rglob("*.gd")]
gdtext = {p.as_posix(): p.read_text(errors="replace") for p in gd}
sysof = {f: (cb.classify(f) or "UNCLASSIFIED") for f in gdtext}


def readers(names):
    out = collections.Counter()
    for f, txt in gdtext.items():
        if any(n in txt for n in names):
            out[sysof[f]] += 1
    return out


def census_class(root, label):
    packets = sorted(d for d in os.listdir(root) if os.path.isdir(os.path.join(root, d)))
    fam_bytes, fam_names = collections.Counter(), collections.defaultdict(set)
    loose = 0
    for entry in sorted(os.listdir(root)):
        full = os.path.join(root, entry)
        if os.path.isfile(full):
            if not entry.endswith(SKIP):
                loose += os.path.getsize(full)
                fam_bytes[family("", entry)] += os.path.getsize(full)
                fam_names[family("", entry)].add(entry)
            continue
        for fp in content_files(full):
            rel = os.path.relpath(fp, full)
            k = family(rel, os.path.basename(fp))
            fam_bytes[k] += os.path.getsize(fp)
            fam_names[k].add(os.path.basename(fp))
    total = sum(fam_bytes.values())
    fo = format_owner(root + "/")
    by_reader, no_reader = collections.Counter(), 0
    for k, b in fam_bytes.items():
        r = readers(sorted(fam_names[k])[:40])
        if not r:
            no_reader += b
        for s, _ in r.items():
            by_reader[s] += b / len(r)
    return dict(root=root, label=label, packets=len(packets), total=total, loose=loose,
                families=len(fam_bytes), fo=fo, by_reader=by_reader, no_reader=no_reader,
                fam_bytes=fam_bytes, fam_names=fam_names)


def human(n):
    return f"{n:,}"


if "--families" in sys.argv:
    root = sys.argv[sys.argv.index("--families") + 1]
    c = census_class(root.rstrip("/"), "")
    print(f"{root} — {c['families']} families, {human(c['total'])} content bytes")
    for k, b in c["fam_bytes"].most_common():
        r = readers(sorted(c["fam_names"][k])[:40])
        who = ", ".join(f"{s}:{n}" for s, n in r.most_common(3)) or "NO READER IN src/"
        print(f"  {b:>14,}  {k:<44}{who}")
    sys.exit(0)

print("PACKET CLASSES — content bytes, format owner (ADR-0142 dec. 1) vs readers")
print(f"{'class':<30}{'packets':>8}{'families':>10}{'content bytes':>16}  {'format owner':<14} readers")
print("-" * 108)
rows = []
for root, label in PACKET_CLASSES:
    if not os.path.isdir(root):
        continue
    c = census_class(root, label)
    rows.append(c)
    top = ", ".join(f"{s} {b / c['total'] * 100:.1f}%" for s, b in c["by_reader"].most_common(3))
    print(f"{root:<30}{c['packets']:>8}{c['families']:>10}{c['total']:>16,}  {str(c['fo']):<14} {top}")
    if c["no_reader"]:
        print(f"{'':<30}{'':>8}{'':>10}{'':>16}  {'':<14} no reader in src/: "
              f"{c['no_reader']:,} ({c['no_reader'] / c['total'] * 100:.1f}%)")

print("\nWHOLE TREE — every content byte under %s, by FORMAT owner" % ASSET_ROOTS_LABEL)
print("-" * 108)
owned = collections.Counter()
unowned = collections.Counter()
declared_elsewhere = 0
for fp in (f for root in ASSET_ROOTS for f in content_files(root)):
    rel = pathlib.Path(fp).as_posix()
    if pathlib.Path(rel).suffix in cb.SOURCE_SUFFIXES:
        continue                                   # source, not an asset: classify_blueprint.py has it
    o = format_owner(rel)
    b = os.path.getsize(fp)
    if o is NOT_AN_ASSET:
        declared_elsewhere += b
        continue
    if o:
        owned[o] += b
    else:
        seg = rel.split("/")
        unowned["/".join(seg[:2]) + ("/" if len(seg) > 2 else "")] += b
tot = sum(owned.values()) + sum(unowned.values())
for s, b in owned.most_common():
    print(f"  {s:<24}{b:>16,}{b / tot * 100:>8.1f}%")
for d, b in unowned.most_common():
    print(f"  {'(NO FORMAT RULE)':<24}{b:>16,}{b / tot * 100:>8.1f}%   {d}")
print(f"  {'TOTAL':<24}{tot:>16,}")
print(f"  {'(declared elsewhere)':<24}{declared_elsewhere:>16,}          "
      f"assets/scenes/*.tscn — docs/ROOT_SET.tsv owns these, one row each")
if unowned:
    print(f"\n  {len(unowned)} location(s) have NO format rule. That is the finding, not a default —"
          f"\n  add a FORMAT_OWNER entry or say why the bytes belong to nobody.")
print("\nFORMAT ownership answers WHO OWNS THE BYTES. Whether anything reads them is")
print("closure.py's question, and the two disagree by design.")
