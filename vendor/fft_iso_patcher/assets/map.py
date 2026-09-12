"""Map (GNS) resource placement.

Build-side contract (#372): ``build`` emits opaque resource blobs plus the
full GNS with the original LBAs verbatim, and never sees a disc. This
handler owns placement and the GNS ``(lba, length)`` fixup:

- The BATTLE.BIN GNS table (``FUN_800F3638`` indexes it with the map id and
  raw-reads the GNS) locates the GNS; the ISO9660 directory must agree —
  the game reads the table, the pokes target the directory tree.
- Each resource the arrangement references is placed by the music leg's
  rule: in-place when the blob fits the GNS's 2048-multiple allocation,
  relocate when ``allow_relocate``, refuse otherwise.
- The fixed-up bundle GNS is written back in place at its original LBA
  (at most 2 sectors). Type-49 terminators echo the last real record, so
  when that record belongs to this arrangement they are fixed up too.
- Resources whose LBA or byte size changed get their ISO9660 directory
  record poked (both-endian LBA + size words). The game never reads
  these; ``extract``, CDMage, and a re-dump from the patched ISO do.

Full surface spec: ``docs/map-leg-v1.md``.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass
from pathlib import Path

from ..constants import (
    BATTLE_BIN_GNS_TABLE_OFFSET,
    BATTLE_BIN_PATH,
    GNS_MAX_BYTES,
    GNS_RECORD_BYTES,
    GNS_RECORD_MARKER,
    GNS_RECORD_SENTINEL,
    GNS_TYPE_PADDED,
    GNS_VALID_TAGS,
    MAP_DIR_PATH,
    N_MAP_IDS,
)
from ..free_space import FreeSpaceAllocator
from ..iso9660 import find_file, list_dir
from ..iso_sectors import PsxDisc, USER_DATA_SIZE
from ..iso_utils import bytes_to_sectors
from ..manifest import ManifestBuilder
from . import register
from .byte_patch import BytePatch
from .kinds import PatchKind


@dataclass(frozen=True)
class GnsRecord:
    """One 20-byte GNS record."""

    index: int
    raw: bytes
    tag: int
    arrangement: int
    type_low: int
    lba: int
    length: int      # u32 LE; a 2048-multiple

    @property
    def is_padded(self) -> bool:
        return self.type_low == GNS_TYPE_PADDED

    @property
    def is_real(self) -> bool:
        return not self.is_padded


def _parse_gns(data: bytes, label: str) -> tuple[list[GnsRecord], int]:
    """Parse a GNS into ``(records, tail_start)``.

    A GNS file is a contiguous prefix of 20-byte records followed by an
    opaque tail (every GNS on this disc is ≡ 8 mod 20 bytes and the tail
    holds non-zero data). The record count is derived from the contiguous
    valid prefix, not from the file size; the tail is carried verbatim.
    """
    recs: list[GnsRecord] = []
    n_slots = len(data) // GNS_RECORD_BYTES
    for i in range(n_slots):
        raw = data[i * GNS_RECORD_BYTES:(i + 1) * GNS_RECORD_BYTES]
        valid = (
            raw[0] in GNS_VALID_TAGS
            and raw[6:8] == GNS_RECORD_MARKER
            and raw[16:20] == GNS_RECORD_SENTINEL
        )
        if valid:
            lba, length = struct.unpack_from("<II", raw, 8)
            recs.append(GnsRecord(
                index=i, raw=raw, tag=raw[0], arrangement=raw[2],
                type_low=raw[5], lba=lba, length=length,
            ))
        elif recs:
            for later in range(i + 1, n_slots):
                later_raw = data[later * GNS_RECORD_BYTES:
                                 (later + 1) * GNS_RECORD_BYTES]
                if later_raw[16:20] == GNS_RECORD_SENTINEL:
                    raise ValueError(
                        f"{label}: GNS record region is not contiguous: "
                        f"slot {i} carries no sentinel but slot {later} "
                        f"does — malformed GNS"
                    )
            break
    return recs, len(recs) * GNS_RECORD_BYTES


def _resolve_bundle_dir(file_str: str, manifest: ManifestBuilder) -> Path:
    p = Path(file_str)
    if not p.is_absolute():
        p = manifest.recipe_path.parent / p
    p = p.resolve()
    if not p.is_dir():
        raise FileNotFoundError(f"map bundle directory {p} does not exist")
    return p


def _read_gns_table_entry(disc: PsxDisc, map_id: int) -> int:
    """The BATTLE.BIN GNS LBA table entry for `map_id` (0 = no GNS)."""
    if not (0 <= map_id < N_MAP_IDS):
        raise ValueError(f"map id {map_id} out of range [0, {N_MAP_IDS})")
    battle = find_file(disc, BATTLE_BIN_PATH)
    entry_offset = BATTLE_BIN_GNS_TABLE_OFFSET + map_id * 4
    sector_idx, off_in_sector = divmod(entry_offset, USER_DATA_SIZE)
    if off_in_sector + 4 > USER_DATA_SIZE:
        raise NotImplementedError(
            f"GNS table entry for map {map_id} crosses a sector boundary"
        )
    sector = disc.read_user_data(battle.lba + sector_idx, 1)
    return struct.unpack_from("<I", sector, off_in_sector)[0]


def _dir_poke(
    patches: list[BytePatch],
    resource: str,
    label: str,
    containing_lba: int,
    offset_in_containing: int,
    word_offset: int,
    pack: str,
    value: int,
    endian: str,
) -> None:
    """One 4-byte both-endian word poke into a directory record (§2.4)."""
    end = offset_in_containing + word_offset + 4
    if end > USER_DATA_SIZE:
        raise ValueError(
            f"{label}: directory record for {resource} sits at byte "
            f"{offset_in_containing} of its sector; a {endian}-endian poke "
            f"at +{word_offset} would cross the sector boundary"
        )
    patches.append(BytePatch(
        lba=containing_lba,
        offset_in_payload=offset_in_containing + word_offset,
        data=struct.pack(pack, value),
        label=f"{label} dir poke {resource} ({endian} @ +{word_offset})",
    ))


def summary_line(row: dict) -> str:
    """The §4 apply-log summary for a manifest map row.

    ``MAP042 a0: gns@99137, 20 resources, 2 relocated (MAP042.11 -> 224103,
    MAP042.15 -> 224108)`` — a raw resource list would be a wall of text.
    """
    resources = row["resources"]
    relocated = [r for r in resources if r["relocated"]]
    line = (f"MAP{row['map']:03d} a{row['arrangement']}: "
            f"gns@{row['gns']['lba']}, {len(resources)} resources")
    if relocated:
        line += (f", {len(relocated)} relocated ("
                 + ", ".join(f"{r['resource']} -> {r['lba']}" for r in relocated)
                 + ")")
    return line


@register(PatchKind.MAP.value)
def resolve_map(
    entry_config: dict,
    disc: PsxDisc,
    allocator: FreeSpaceAllocator,
    manifest: ManifestBuilder,
) -> list[BytePatch]:
    map_id = int(entry_config["map"])
    arrangement = int(entry_config["arrangement"])
    bundle_dir = _resolve_bundle_dir(entry_config["file"], manifest)
    allow_relocate = bool(entry_config.get("allow_relocate", False))
    label = f"MAP{map_id:03d} a{arrangement}"

    # ---- verification 1: map id in range and the map has a GNS ----------
    table_lba = _read_gns_table_entry(disc, map_id)
    if table_lba == 0:
        raise ValueError(
            f"{label}: BATTLE.BIN GNS table entry for map {map_id} is 0 — "
            f"the map has no GNS on this disc"
        )

    # ---- verification 2: table and directory agree ----------------------
    gns_name = f"MAP{map_id:03d}.GNS"
    gns_rec = find_file(disc, f"/MAP/{gns_name};1")
    if gns_rec.lba != table_lba:
        raise ValueError(
            f"{label}: BATTLE.BIN table says the GNS is at LBA {table_lba}, "
            f"but the ISO9660 directory record for {gns_name};1 is at LBA "
            f"{gns_rec.lba} — the game reads the table, the pokes target "
            f"the directory tree; refusing"
        )

    gns_size = gns_rec.size_bytes
    if gns_size > GNS_MAX_BYTES:
        raise ValueError(
            f"{label}: GNS is {gns_size} bytes; the game's read window is "
            f"{GNS_MAX_BYTES} bytes (hard-coded at 0x800F369C)"
        )
    disc_gns_raw = disc.read_user_data(table_lba, bytes_to_sectors(gns_size))[:gns_size]
    disc_recs, disc_tail = _parse_gns(disc_gns_raw, f"{label} disc GNS")

    bundle_gns_path = bundle_dir / gns_name
    if not bundle_gns_path.is_file():
        raise FileNotFoundError(
            f"{label}: bundle directory {bundle_dir} has no {gns_name}"
        )
    bundle_gns_raw = bundle_gns_path.read_bytes()

    # ---- verification 3: GNS size and record count are invariant --------
    if len(bundle_gns_raw) != len(disc_gns_raw):
        raise ValueError(
            f"{label}: bundle GNS is {len(bundle_gns_raw)} bytes, the disc "
            f"GNS is {len(disc_gns_raw)} bytes — the GNS is written back "
            f"in place; its allocation cannot move"
        )
    bundle_recs, bundle_tail = _parse_gns(bundle_gns_raw, f"{label} bundle GNS")
    if len(bundle_recs) != len(disc_recs):
        raise ValueError(
            f"{label}: bundle GNS has {len(bundle_recs)} records, the disc "
            f"GNS has {len(disc_recs)} — the record count is invariant"
        )

    this_arr = [r for r in bundle_recs if r.arrangement == arrangement and r.is_real]

    # ---- verification 4: verbatim cross-check ---------------------------
    # The disc is the placement authority: this arrangement's records must
    # carry the disc's (lba, length); every other record and the whole
    # opaque tail must be byte-identical to the disc GNS.
    for b, d in zip(bundle_recs, disc_recs):
        if b.arrangement == arrangement and b.is_real:
            if (b.lba, b.length) != (d.lba, d.length):
                raise ValueError(
                    f"{label}: GNS record {b.index} carries (lba, length) = "
                    f"({b.lba}, {b.length}) but the disc GNS says "
                    f"({d.lba}, {d.length}) — the disc is the placement "
                    f"authority; re-dump from the current (patched) ISO and "
                    f"rebuild"
                )
        elif b.raw != d.raw:
            raise ValueError(
                f"{label}: GNS record {b.index} differs from the disc GNS "
                f"outside this arrangement's art-facing fields; every other "
                f"record must be carried verbatim"
            )
    if bundle_gns_raw[bundle_tail:] != disc_gns_raw[disc_tail:]:
        raise ValueError(
            f"{label}: the GNS tail (bytes {bundle_tail}–"
            f"{len(bundle_gns_raw)}) differs from the disc GNS; it must be "
            f"carried verbatim"
        )

    # ---- verification 5: record <-> blob pairing is bijective -----------
    if not this_arr:
        raise ValueError(
            f"{label}: arrangement {arrangement} has no real "
            f"(non-{GNS_TYPE_PADDED}) records in the GNS; there is nothing "
            f"to patch"
        )

    # ---- verification 6: GNS shape sanity -------------------------------
    # (tag, marker, and sentinel are enforced slot-by-slot by _parse_gns;
    # the terminator echo is the remaining shape rule.)
    last_real = next((r for r in reversed(bundle_recs) if r.is_real), None)
    if last_real is not None:
        for rec in bundle_recs:
            if rec.is_padded and (rec.lba, rec.length) != (last_real.lba, last_real.length):
                raise ValueError(
                    f"{label}: GNS record {rec.index} is a type-"
                    f"{GNS_TYPE_PADDED} terminator but does not echo the "
                    f"last real record's (lba, length)"
                )

    map_dir = find_file(disc, MAP_DIR_PATH)
    dir_index = {
        r.lba: r for r in list_dir(disc, map_dir.lba, map_dir.size_bytes)
        if not r.is_dir
    }

    # Records sharing an LBA form one group: one blob, one placement,
    # every record in the group fixed up identically.
    groups: dict[int, list[GnsRecord]] = {}
    for rec in this_arr:
        groups.setdefault(rec.lba, []).append(rec)

    placements: dict[int, dict] = {}
    used_names: set[str] = set()
    for orig_lba, recs in groups.items():
        dir_rec = dir_index.get(orig_lba)
        if dir_rec is None:
            raise ValueError(
                f"{label}: GNS record {recs[0].index} points at LBA "
                f"{orig_lba}, which is not a file under /MAP"
            )
        resource = (
            dir_rec.name[:-2] if dir_rec.name.endswith(";1") else dir_rec.name
        )
        expected_padded = (dir_rec.size_bytes + USER_DATA_SIZE - 1) // USER_DATA_SIZE \
            * USER_DATA_SIZE
        for rec in recs:
            if rec.length != expected_padded:
                raise ValueError(
                    f"{label}: GNS record {rec.index} ({resource}) says "
                    f"{rec.length} bytes but /MAP/{resource};1 is "
                    f"{dir_rec.size_bytes} bytes ({expected_padded} "
                    f"padded); the GNS length is the 2048-padding of the "
                    f"file size"
                )
        blob_path = bundle_dir / resource
        if not blob_path.is_file():
            raise FileNotFoundError(
                f"{label}: bundle has no {resource} blob for LBA {orig_lba}"
            )
        placements[orig_lba] = {
            "resource": resource,
            "dir_rec": dir_rec,
            "blob": blob_path.read_bytes(),
            "gns_length": recs[0].length,
        }
        used_names.add(resource)

    bundle_names = {
        p.name for p in bundle_dir.iterdir()
        if p.is_file() and p.name != gns_name
    }
    orphans = bundle_names - used_names
    if orphans:
        raise ValueError(
            f"{label}: bundle has orphan blobs not referenced by "
            f"arrangement {arrangement}: {sorted(orphans)}"
        )

    # ---- placement decisions (spec §2.2) ---------------------------------
    for orig_lba, info in placements.items():
        blob = info["blob"]
        new_n = bytes_to_sectors(len(blob))
        have_n = info["gns_length"] // USER_DATA_SIZE
        if new_n <= have_n:
            info["target_lba"] = orig_lba
            info["relocated"] = False
            info["new_gns_length"] = info["gns_length"]
        elif allow_relocate:
            info["target_lba"] = allocator.allocate(
                new_n, f"map_{map_id:03d}a{arrangement}_{info['resource']}"
            )
            info["relocated"] = True
            info["new_gns_length"] = new_n * USER_DATA_SIZE
        else:
            raise ValueError(
                f"{label} {info['resource']} has a {have_n}-sector "
                f"({have_n * USER_DATA_SIZE}-byte) allocation; new blob is "
                f"{len(blob)} bytes ({new_n} sectors). Set "
                f"allow_relocate=true and add a [free_space].ranges entry."
            )
        info["new_n"] = new_n

    # ---- GNS fixup and the terminator rule (spec §2.3) ------------------
    fixed = bytearray(bundle_gns_raw)
    for rec in this_arr:
        info = placements[rec.lba]
        struct.pack_into(
            "<II", fixed, rec.index * GNS_RECORD_BYTES + 8,
            info["target_lba"], info["new_gns_length"],
        )
    if last_real is not None and last_real.arrangement == arrangement:
        info = placements[last_real.lba]
        for rec in bundle_recs:
            if rec.is_padded:
                struct.pack_into(
                    "<II", fixed, rec.index * GNS_RECORD_BYTES + 8,
                    info["target_lba"], info["new_gns_length"],
                )

    # ---- patches ----------------------------------------------------------
    patches: list[BytePatch] = []
    # The GNS: written back in place, one sector patch per 2048-byte
    # sector (at most 2). Emitted even when the bytes are unchanged: the
    # chunk is then byte-identical to the disc sector (GNS bytes plus the
    # disc's own post-size padding), so it is a no-op on the ISO while
    # still making two entries for one GNS conflict loudly (spec §6).
    for k in range(bytes_to_sectors(gns_size)):
        chunk = bytearray(fixed[k * USER_DATA_SIZE:(k + 1) * USER_DATA_SIZE])
        # Padding past the GNS end: keep the disc's own bytes rather than
        # zero-filling (the file ends mid-sector; whatever the mastering
        # tool put there is not ours).
        pad_start = gns_size - k * USER_DATA_SIZE
        if pad_start < USER_DATA_SIZE:
            disc_sector = disc.read_user_data(table_lba + k, 1)
            chunk[pad_start:] = disc_sector[pad_start:]
        patches.append(BytePatch(
            lba=table_lba + k,
            offset_in_payload=0,
            data=bytes(chunk),
            label=f"{label} GNS sector {k}",
        ))
    # Resource payloads, then the both-endian directory-record pokes.
    for orig_lba, info in placements.items():
        for k in range(info["new_n"]):
            chunk = info["blob"][k * USER_DATA_SIZE:(k + 1) * USER_DATA_SIZE]
            chunk = chunk + bytes(USER_DATA_SIZE - len(chunk))
            patches.append(BytePatch(
                lba=info["target_lba"] + k,
                offset_in_payload=0,
                data=chunk,
                label=f"{label} {info['resource']} payload sector {k}",
            ))
    for orig_lba, info in placements.items():
        dir_rec = info["dir_rec"]
        if info["target_lba"] != orig_lba:
            _dir_poke(patches, info["resource"], label,
                      dir_rec.containing_lba, dir_rec.offset_in_containing,
                      2, "<I", info["target_lba"], "little")
            _dir_poke(patches, info["resource"], label,
                      dir_rec.containing_lba, dir_rec.offset_in_containing,
                      6, ">I", info["target_lba"], "big")
        if len(info["blob"]) != dir_rec.size_bytes:
            _dir_poke(patches, info["resource"], label,
                      dir_rec.containing_lba, dir_rec.offset_in_containing,
                      10, "<I", len(info["blob"]), "little")
            _dir_poke(patches, info["resource"], label,
                      dir_rec.containing_lba, dir_rec.offset_in_containing,
                      14, ">I", len(info["blob"]), "big")

    # ---- manifest (§3): one nested row per [[patches.map]] entry ---------
    manifest.record_placement(
        kind=PatchKind.MAP.value,
        map=map_id,
        arrangement=arrangement,
        source=str(bundle_dir),
        gns={"lba": table_lba, "size_bytes": gns_size},
        resources=[
            {
                "resource": placements[orig_lba]["resource"],
                "lba": placements[orig_lba]["target_lba"],
                "n_sectors": placements[orig_lba]["new_n"],
                "size_bytes": len(placements[orig_lba]["blob"]),
                "size_padded": placements[orig_lba]["new_n"] * USER_DATA_SIZE,
                "relocated": placements[orig_lba]["relocated"],
                "original_lba": orig_lba,
                "original_size_padded": placements[orig_lba]["gns_length"],
            }
            for orig_lba in placements
        ],
    )

    return patches
