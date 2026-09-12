"""Pass-1 selection sweep: every system's outbound debt, all arms, on THIS tree.

Thin wrapper over `tools/arm7_membership.py` (calibrated three ways, ADR-0243 dec. 11).
The only NEW thing here is membership construction -- files grouped by
`score_goals._tables()["sysof"]` -- and that is calibrated against
`classify_blueprint.py`'s own FILES/LINES column, row for row, by --calibrate.

Usage:  uv run python tools/selection_sweep.py [--calibrate] [--system=NAME]
Run from the package root.
"""
import sys, pathlib, collections
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import arm7_membership as A

ns = A._load()
t = ns["_tables"]()
sysof = t["sysof"]
ADDON = A._ADDON_RE

def members_by_system():
    out = collections.defaultdict(list)
    for path, sysname in sysof.items():
        out[sysname].append(path)
    return {k: sorted(v) for k, v in out.items()}

def linecount(p):
    try:
        return len(pathlib.Path(p).read_text(errors="ignore").splitlines())
    except OSError:
        return 0

def report(name, members):
    host = [m for m in members if not ADDON.match(m)]
    hits = A.arm7(host)
    n7 = sum(len(h["lines"]) for h in hits.values())
    inside = tuple(sorted({m.rsplit("/", 1)[0] + "/" for m in host}))
    shapes = A.all_shapes(host, inside)
    esc = {k: v for k, v in shapes.items() if not ADDON.match(k[2])}
    by_kind = collections.Counter()
    for (kind, _tg, _dst, _b), v in esc.items():
        by_kind[kind] += len(v)
    auto_in = sorted(k for k, p in t["auto"].items() if p in set(host))
    return {
        "system": name,
        "files": len(host),
        "lines": sum(linecount(m) for m in host),
        "arm7_names": len(hits),
        "arm7_lines": n7,
        "autoload_lines": by_kind.get("autoload", 0) + by_kind.get("/root/ reach", 0),
        "res_lines": by_kind.get("preload", 0) + by_kind.get("const path", 0)
                     + by_kind.get("#include", 0),
        "autoloads_inside": auto_in,
        "hits": hits,
    }

def main(argv):
    bysys = members_by_system()
    if "--calibrate" in argv:
        print("CALIBRATION -- membership construction vs classify_blueprint's own table")
        print("%-26s %6s %9s" % ("BUCKET", "FILES", "LINES"))
        for k in sorted(bysys):
            ms = bysys[k]
            print("%-26s %6d %9d" % (k, len(ms), sum(linecount(m) for m in ms)))
        return 0
    want = [a.split("=", 1)[1] for a in argv if a.startswith("--system=")]
    rows = []
    for k in sorted(bysys):
        if want and k not in want:
            continue
        rows.append(report(k, bysys[k]))
    rows.sort(key=lambda r: -r["arm7_lines"])
    print("%-24s %5s %8s | %5s %6s | %6s %6s | %s" %
          ("SYSTEM", "FILES", "LINES", "A7-N", "A7-L", "A2-L", "A6-L", "AUTOLOADS INSIDE"))
    print("-" * 108)
    for r in rows:
        print("%-24s %5d %8d | %5d %6d | %6d %6d | %s" %
              (r["system"], r["files"], r["lines"], r["arm7_names"], r["arm7_lines"],
               r["autoload_lines"], r["res_lines"],
               ", ".join(r["autoloads_inside"]) or "-"))
    print("-" * 108)
    print("A7 = arm 7 (class_name outside every addon root) -- the selection instrument.")
    print("A2 = arm 2 (host autoload reaches, incl. /root/).  A6 = arm 6 (res:// paths).")
    print("A2 and A6 are NOT in the arm-7 figure; the real guard's number can only go UP.")
    if want:
        for r in rows:
            print("\n=== %s arm-7 detail ===" % r["system"])
            for cn, h in sorted(r["hits"].items(), key=lambda kv: -len(kv[1]["lines"])):
                print("    %-28s %3d  %s  [%s]" % (cn, len(h["lines"]), h["path"],
                                                   t["sysof"].get(h["path"])))
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv))
