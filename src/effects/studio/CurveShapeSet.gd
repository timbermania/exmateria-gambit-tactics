extends RefCounted
## The **distinct curve shapes** in one effect (ADR-0089 curve-ownership amendment,
## decision 4) — and, because they are the same thing, the effect's PSX budget gauge.
##
## A [curve shape] is a distinct 160-sample sequence, as opposed to a
## [use site]'s curve, which is an INSTANCE of one. After the explode an effect holds a
## median of 22 curves carrying a median of 8 distinct shapes (max 15). Counting the array
## where you mean the shape set is the mistake this design is most likely to grow, so the
## two are named apart everywhere: `EffectData.curves.size()` is never a budget.
##
## Shapes are what the picker shows and what the compiler emits, so **distinct shapes =
## curves the compiler must emit = consumption against 15**. One number, two purposes, no
## second mechanism to keep in sync. An untouched effect is ≤15 by construction; authoring
## is what can overrun it, and the overrun is visible in the picker before export rather
## than discovered after.
##
## The dedup is BY VALUE on the quantized 0-255 bytes — the bytes the compiler will
## actually write — so the count here cannot flatter the count there.
##
## One honest edge the gauge does not model: [residue] (curves nothing references) also
## occupies ROM slots, so an effect whose 15 slots are mostly padding has less byte-exact
## headroom than `15 − distinct-in-use` suggests. Spending a residue slot costs
## byte-exactness, not correctness, and it is the compiler's call to make — the ADR's own
## spare-slot measurements count distinct-in-use, and this follows them.
##
## No `class_name` (ADR-0004) — preloaded by path.

const CurveExplode = ExMateriaEffects.CurveExplode
const CurveChannel = preload("res://src/effects/studio/CurveChannel.gd")

## The ROM's curve-table size — what the compiler has to fit into. Not a tunable: it is
## the 4-bit nibble's reach, and enforcing it ANYWHERE upstream of the compiler is the
## thing this amendment exists to stop.
const BUDGET := 15


## The distinct shapes referenced by `data`'s use sites, in first-use order.
## Each entry is `{key, grid, sites, index}`:
##   • `grid`  — the shape as 0-255 ints (the picker draws it, the compiler emits it)
##   • `sites` — every use site drawing it, as `{emitter_index, slot, kind}`
##   • `index` — the private curve index of the FIRST site drawing it (a painter address)
## Use sites with no curve contribute nothing: "no curve" is not a shape, it is the
## absence of one, and it costs no slot.
static func shapes(data) -> Array:
	var by_key := {}
	var out: Array = []
	if data == null or data.curves == null:
		return out
	for site in CurveExplode.use_sites(data):
		var idx: int = int(site["index"])
		if idx < 0 or idx >= data.curves.size():
			continue
		var grid: Array = CurveChannel.to_grid(data.curves[idx])
		var k: String = key(grid)
		if not by_key.has(k):
			by_key[k] = {"key": k, "grid": grid, "sites": [], "index": idx}
			out.append(by_key[k])
		by_key[k]["sites"].append({"emitter_index": int(site["emitter_index"]),
			"slot": str(site["slot"]), "kind": str(site["kind"])})
	return out


## The dedup key for a 0-255 grid — the exact bytes, not a hash of them, so two shapes are
## the same shape only when the compiler would emit one record for both.
static func key(grid: Array) -> String:
	var bytes := PackedByteArray()
	bytes.resize(grid.size())
	for i in range(grid.size()):
		bytes[i] = clampi(int(grid[i]), 0, 255)
	return bytes.hex_encode()


## Which shape (position in `shape_list`) a use site currently draws, or -1 when it has no
## curve. The picker's face reads this: after the explode a use site's INDEX is a private
## array position that means nothing to an author, but "which shape is this" does.
static func ordinal_for(shape_list: Array, emitter_index: int, slot: String, kind: String) -> int:
	for i in range(shape_list.size()):
		for site in shape_list[i]["sites"]:
			if int(site["emitter_index"]) == emitter_index and str(site["slot"]) == slot \
					and str(site["kind"]) == kind:
				return i
	return -1


## The live budget: `{count, budget, spare, over}`. `over` is what the deferred compiler
## turns into a refusal — more than 15 distinct shapes is a COMPILE ERROR that names the
## overrun, never a silent merge (a merged colour curve is a visual regression a numeric
## tell cannot convey). Refusing is only fair because this number is watchable while
## authoring, which is the whole reason it is computed here and not only at export.
static func gauge(data) -> Dictionary:
	var n: int = shapes(data).size()
	return {"count": n, "budget": BUDGET, "spare": BUDGET - n, "over": n > BUDGET}


## The gauge as the one-line label the studio shows: "Shapes 8/15", with the overrun said
## out loud rather than left to the reader to subtract.
static func gauge_text(data) -> String:
	var g: Dictionary = gauge(data)
	var s := "Shapes %d/%d" % [int(g["count"]), int(g["budget"])]
	if bool(g["over"]):
		s += "  — %d over the PSX table" % (int(g["count"]) - int(g["budget"]))
	return s
