# `template.json` schema + template folder layout

**Status:** locked 2026-07-18 (wayfinder [#200](https://github.com/timbermania/fft-monorepo/issues/200), map [#197](https://github.com/timbermania/fft-monorepo/issues/197)) · concretizes **[ADR-0072](adr/0072-a-template-is-a-derived-folder-per-key-asset-packet-that-is-the-runtime-read-surface.md) dec.3**.

This is the contract the **character-alignment transform** ([#201](https://github.com/timbermania/fft-monorepo/issues/201)) emits and the **runtime loaders** (`SpriteLayerManager`, `UIPortrait`, [#203](https://github.com/timbermania/fft-monorepo/issues/203)) read. Design is settled in ADR-0072 — this doc pins the concrete filenames, JSON shape, and physical storage; it does **not** re-open the design.

---

## 1. Physical storage — generated, gitignored, regenerable

A template is a **derived folder**, one per template key. The tree lives at:

```
res://assets/characters/templates/<token>/
```

- `<token>` is the folder token from the **residue manifest**
  (`addons/exmateria_catalogue/templates/template_residue.json`,
  `ResidueManifest.folder_of()`):
  `<slug>_<special_name>`, e.g. `ramza_3`, `agrias_52`.
  `ResidueManifest.TEMPLATE_ROOT` is no longer a baked literal: extraction #6
  (#1025 pass 3) moved the manifest into `addons/exmateria_catalogue/`, and an
  addon may not name a host content path, so the root now comes from the host
  through `exmateria_catalogue/content_root` (ADR-0202 dec. 5). The VALUE is
  unchanged — `project.godot` sets it to `res://assets/` and the subpath is
  `characters/templates/` — so `res://assets/characters/templates/<token>/` above
  is still where the tree lives.
- The whole subtree is **gitignored** (`/assets/characters/templates/`) — it is
  ROM-derived, git-lfs-sized, and **not committed** (user decision 2026-07-17).
- A fresh checkout **regenerates** it by running the transform (like
  `project-assets/`), then `godot --path . --import` to build the `.tga` `.import`
  sidecars. Until the transform runs the folders are **absent** — so the loaders'
  flat-store fallback (`assets/sprites/textures/NN.tga`) stays **load-bearing**
  (ADR-0072 consequence; generics resolve through job tables regardless).

Consistent with ADR-0066/0072 "derived + regenerable, never hand-owned as source."

---

## 2. Folder layout

Every visual is a **sliced, owned, self-contained** file — the moddable read
surface: replace a file to re-skin the unit. Each indexed image carries its
**own palette** file (`.palette.tga`). The one genuinely-shared asset —
animation `TYPE` (154 ids → ~8 files) — is **referenced by name, never copied**.

```
ramza_3/
  body.tga            body.palette.tga          # in-game body sheet (owned, 1:1)
  portrait.tga        portrait.palette.tga       # embedded menu portrait (owned, 1:1)
  formation.tga       formation.palette.tga      # formation-screen cell (owned; contents = RE gap*)
  events/
    face/
      00.tga          00.palette.tga             # EVTFACE dialogue portrait — indexed collection
      01.tga          01.palette.tga             #   (blink / mouth talking frames)
    chr/
      00.tga          00.palette.tga             # EVTCHR cinematic frames — indexed collection
      01.tga          01.palette.tga             #   (contents = RE gap*)
  template.json
```

\* **RE gaps (shape locked):** which `UNIT.BIN` cell + palette maps to a template's
`formation` sprite is still undecoded — open in `FORMATION_SCREEN.md`; the transform
emits that field's *shape* and its *contents* land as the RE cracks. The
`events.{chr,face}` **contents are now derived** (wayfinder #204): the
`character ↔ (segment, frame_id)` / `(row, col)` binding is recovered by replaying
the event instruction stream (`tools/event_asset_derivation.py`) and the frames/
cells are sliced into the folder (`tools/event_asset_slicing.py`). The recovered
`segment → character` residue is transform-internal (`event_asset_map.json`), kept
OUT of `template.json` per the coord-free read-surface rule (§3.3).

---

## 3. `template.json` shape

```jsonc
{
  // --- descriptive header (NOT load-bearing for resolution) ---
  // Resolution is upstream: ResidueManifest.has(special_name) picks unique vs
  // job-routed; the folder is addressed by token, never by reading this file.
  // These fields are for legibility / modding / debugging only.
  "template_key": "3",              // the key this folder answers to (unique: special_name; generic: "job/gender")
  "category":     "unique",         // "unique" | "generic-human" | "generic-monster"

  // --- OWNED 1:1 assets (sliced into this folder). Omit a key entirely = absent. ---
  "body":      { "sprite": "body.tga",      "palette": "body.palette.tga" },
  "portrait":  { "sprite": "portrait.tga",  "palette": "portrait.palette.tga" },
  "formation": { "sprite": "formation.tga", "palette": "formation.palette.tga" },

  // --- OWNED, sliced, INDEXED event collections. Omit `events` (or a sub-key) = absent. ---
  "events": {
    "face": [
      { "index": 0, "tag": "neutral", "sprite": "events/face/00.tga", "palette": "events/face/00.palette.tga" },
      { "index": 1, "tag": "blink",   "sprite": "events/face/01.tga", "palette": "events/face/01.palette.tga" }
    ],
    "chr": [
      { "index": 0, "tag": "carry_pose", "sprite": "events/chr/00.tga", "palette": "events/chr/00.palette.tga" },
      { "index": 1,                       "sprite": "events/chr/01.tga", "palette": "events/chr/01.palette.tga" }
    ]
  },

  // --- REFERENCED shared asset: animation TYPE by name (never copied). ---
  // SEQ and SHP families are INDEPENDENT — they diverge (e.g. TYPE2.SHP uses
  // TYPE3.SEQ), so both are named separately. Resolves to
  // assets/sprites/animations/<seq>_seq.json + <shp>_shp.json.
  "animation": { "seq": "type1", "shp": "type1" },

  // --- scalars (per-sprite, from parse_sprite_types.py) ---
  "flying": false,
  "height": 40
}
```

### 3.1 Field reference

| Field | Kind | Shape | Optional? | Notes |
|-------|------|-------|-----------|-------|
| `template_key` | metadata | string | recommended | Descriptive only — not read for resolution. |
| `category` | metadata | `"unique"` \| `"generic-human"` \| `"generic-monster"` | recommended | Matches the resolver's dispatch category. |
| `body` | owned | `{ sprite, palette }` | **yes** | In-game body sheet + its CLUT. |
| `portrait` | owned | `{ sprite, palette }` | **yes** | Menu portrait, sliced from the sprite sheet's portrait region; its own palette file (was body-palette row 8 in the flat pipeline). |
| `formation` | owned | `{ sprite, palette }` | **yes** | Formation-screen cell, sliced from `EVENT/UNIT.BIN`. **Contents = RE gap.** |
| `events.face[]` | owned | `[{ index, tag?, sprite, palette }]` | **yes** | EVTFACE dialogue portrait(s), sliced + indexed. |
| `events.chr[]` | owned | `[{ index, tag?, sprite, palette }]` | **yes** | EVTCHR cinematic frames, sliced + indexed. Contents derived from the event stream (#204). |
| `animation` | reference | `{ seq, shp }` | **yes** | Family names into `assets/sprites/animations/`. `seq`/`shp` independent. |
| `flying` | scalar | bool | **yes** | |
| `height` | scalar | int | **yes** | |

### 3.2 Optionality — every field individually optional

A field is present iff its key is present; **omit the key entirely to mean
"absent."** This lets any combination exist:

- A **generic** resolves through job tables ([#198](https://github.com/timbermania/fft-monorepo/issues/198)) and gets **no folder** today — the schema is category-agnostic so a generic folder is *expressible*, but the current build emits folders only for **uniques** (the residue set). See "gold consolidation" in the map's Not-yet-specified.
- A **story-only** unit (e.g. Balbanes-death) may have `events` + `portrait` and **no `body`**.
- Inside an event collection, `tag` is optional per entry: `index` (source-order slot) is always present and addressable now; `tag` names the frame's meaning where RE knows it, and is authored/derived as meaning is cracked.

### 3.3 Index keys — ordinal + optional semantic tag

Each `events.*[]` entry is keyed by a stable integer `index` (its source-order
slot) **plus** an optional `tag` naming its meaning (`"neutral"`, `"blink"`,
`"carry_pose"`). The loader can address a frame by `index` immediately and by
`tag` once populated. Native source addresses (EVTFACE `row/col`, EVTCHR
`segment/frame`) are **not** leaked into this surface — provenance stays in the
transform's own manifests.

---

## 4. Why event assets are OWNED, not referenced

ADR-0072 originally grouped EVTFACE/EVTCHR with animation TYPE as "references."
[#200](https://github.com/timbermania/fft-monorepo/issues/200) **refines that**:
only **animation TYPE** stays a reference. The anti-duplication rule that made
animation a reference is a **20:1 structural share** (154 sprite_ids → ~8 TYPE
files); copying it per template is real duplication. EVTFACE/EVTCHR have **no such
share** — a character's dialogue face and cinematic frames are *theirs*, ~1:1 — so
slicing them into the folder duplicates nothing genuinely shared, and it buys the
same self-containment + moddability that slicing the menu portrait does. So they
are **owned, sliced, indexed collections**, not pointers into the shared stores.

---

## 5. Regeneration

```bash
# 1. Emit the template tree (transform — #201; generalizes the extract pipeline).
uv run python tools/<character_alignment_transform>.py     # emits res://assets/characters/templates/
# 2. Build Godot .import sidecars for the freshly-emitted .tga files.
godot --path . --import
```

The tree is gitignored, so this runs on a fresh checkout exactly like the other
regenerable asset trees (`chunks/`, `graphics/`, `faces/`, …). Loaders fall back
to the flat store when a folder is absent.
