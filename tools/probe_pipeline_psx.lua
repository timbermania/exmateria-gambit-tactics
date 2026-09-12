-- [PSX pipeline-layer probe] Dumps the coordinate/position state at EVERY stage
-- of the PSX unit-sprite pipeline (see docs/PSX_TO_GODOT_SPRITE_PIPELINE.md) for
-- the scenario-6 carry units Delita(5) and Ovelia(12), from the settled-carry
-- savestate. The Godot analog dump is tools/probe_pipeline_layers.gd; run both
-- and diff layer-by-layer.
--
-- Layers dumped (§ = doc section):
--   A frame-select (§1-3): anim id +0x1DC, anim_state +0x1D8 (+0x04 id/+0x08 frame)
--   B subframe/pieces (§4-5): unit+0x204 buffer header + 7-byte pieces
--   C world-vec/anchor (§8-9): +0x40/42/44 base, +0x50/52/54 move, +0x60/62/64 off, +0x76
--   D projection (§10-11): screen +0x120/+0x122, OT depth +0x128
--   misc: render_flags +0x12, v_offset +0x7A, mount +0x130
--
-- Usage (pcsx-redux Lua console or PcsxAgent.exec_file):
--   dofile("<repo>/godot-learning/tools/probe_pipeline_psx.lua")
-- Loads reference-assets/scenario6_carry_over_shoulder.sstate (pause first).

PCSX.pauseEmulator()
-- $FFT_SSTATE, else reference-assets/ beside this repo. The old literal named
-- `fft-monorepo-game`, a worktree that is not a safe anchor (CLAUDE.md: a hub
-- must be branch-stable and permanent, and a feature worktree is neither).
local SSTATE = os.getenv("FFT_SSTATE")
    or "reference-assets/scenario6_carry_over_shoulder.sstate"
local f = Support.File.open(SSTATE, "READ")
local z = Support.File.zReader(f); PCSX.loadSaveState(z); f:close()

local mem = PCSX.getMemPtr()
local band = bit.band
local function r8(a)  return mem[band(a, 0x1fffff)] end
local function r16(a) return r8(a) + r8(a + 1) * 256 end
local function s16(a) local v = r16(a); if v >= 32768 then v = v - 65536 end; return v end
local function s8(a)  local v = r8(a);  if v >= 128 then v = v - 256 end;    return v end
local function u32(a) return r8(a) + r8(a+1)*256 + r8(a+2)*65536 + r8(a+3)*16777216 end
local function s32(a) local v = u32(a); if v >= 2147483648 then v = v - 4294967296 end; return v end

-- Unit array base 0x800B7308, stride 0x440. scn6: Delita=slot for 0x800B8848,
-- Ovelia=0x800BA608 (verified addresses, see MEMORY).
local UNITS = { { name = "Delita(5)",  base = 0x800B8848 },
                { name = "Ovelia(12)", base = 0x800BA608 } }

local out = {}
local function p(s) out[#out+1] = s end

for _, U in ipairs(UNITS) do
  local b = U.base
  p(string.format("===== %s  (unit struct @0x%08X) =====", U.name, b))

  -- Layer A — frame select
  p(string.format("A frame-select: anim_id[+0x1DC]=%d(0x%X)  state.id[+0x1DC.. ]=%d  state.frame[+0x1E0]=%d",
    r16(b+0x1DC), r16(b+0x1DC), r16(b+0x1DC), r16(b+0x1E0)))

  -- Layer B — sprite buffer (unit+0x204)
  local buf = u32(b + 0x204)
  p(string.format("B pieces: buffer_ptr[+0x204]=0x%08X", buf))
  if buf ~= 0 then
    local tint  = r16(buf + 0x00)
    local count = r8(buf + 0x03)
    local tpage = r16(buf + 0x04)
    local clut  = r16(buf + 0x06)
    local sx    = r16(buf + 0x08)
    local sy    = r16(buf + 0x0A)
    local rot   = r16(buf + 0x0C)
    p(string.format("  header: count=%d tpage=0x%04X clut=0x%04X scale=(%d,%d)/0x1000 rot=0x%04X tint=0x%04X",
      count, tpage, clut, sx, sy, rot, tint))
    if count > 8 then count = 8 end
    for i = 0, count - 1 do
      local pc = buf + 0x0E + i * 7
      local flags = r8(pc + 6)
      p(string.format("  piece[%d] shift=(%d,%d) wh=(%dx%d) UV=(%d,%d) flags=0x%02X [semitrans=%d flipX=%d flipY=%d split=%d]",
        i, s8(pc+0), s8(pc+1), r8(pc+2), r8(pc+3), r8(pc+4), r8(pc+5), flags,
        band(flags,1), band(band(flags,2),2)~=0 and 1 or 0,
        band(band(flags,4),4)~=0 and 1 or 0, band(band(flags,0x80),0x80)~=0 and 1 or 0))
    end
  end

  -- Layer C — world vector inputs (§8-9). world = base + move + off (+0x76 into Y)
  p(string.format("C world-vec: base[+0x40/42/44]=(%d,%d,%d) move[+0x50/52/54]=(%d,%d,%d) off[+0x60/62/64]=(%d,%d,%d) yExtra[+0x76]=%d",
    s16(b+0x40), s16(b+0x42), s16(b+0x44),
    s16(b+0x50), s16(b+0x52), s16(b+0x54),
    s16(b+0x60), s16(b+0x62), s16(b+0x64), s16(b+0x76)))
  p(string.format("  => world VECTOR = (%d, %d, %d)",
    s16(b+0x40)+s16(b+0x60)+s16(b+0x50),
    s16(b+0x42)+s16(b+0x62)+s16(b+0x52)+s16(b+0x76),
    s16(b+0x44)+s16(b+0x64)+s16(b+0x54)))

  -- Layer D — projected screen + OT depth (§10-11)
  p(string.format("D projection: screen[+0x120/+0x122]=(%d,%d) OT_depth[+0x128]=%d",
    s16(b+0x120), s16(b+0x122), s32(b+0x128)))

  -- misc render inputs
  p(string.format("misc: render_flags[+0x12]=0x%04X (flipH=%d flipV=%d)  v_offset[+0x7A]=%d  mount[+0x130]=%d",
    r16(b+0x12), band(band(r16(b+0x12),2),2)~=0 and 1 or 0,
    band(band(r16(b+0x12),4),4)~=0 and 1 or 0, r16(b+0x7A), r8(b+0x130)))
  p("")
end

-- Camera matrix (R@0x80098A24) + scale (§10)
p("===== camera (§10) =====")
local R = {}; for i = 0, 8 do R[i] = s16(0x80098A24 + i*2) end
p(string.format("R row0(sx): %d %d %d", R[0], R[1], R[2]))
p(string.format("R row1(sy): %d %d %d", R[3], R[4], R[5]))
p(string.format("R row2(dep):%d %d %d", R[6], R[7], R[8]))
p(string.format("scale[0x800C7CA0]: %d %d %d", s16(0x800C7CA0), s16(0x800C7CA2), s16(0x800C7CA4)))

return table.concat(out, "\n")
