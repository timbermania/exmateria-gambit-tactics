extends SceneTree
## ============================================================================
## PROTOTYPE — THROWAWAY. Single-held-particle isolation rig.
## Not production. Delete after the fold color-model audit (/effect-parity) is done.
## Handoff: /tmp/handoff-particle-isolation-rig.md
## ============================================================================
##
## THE QUESTION THIS RIG ANSWERS (methodology, not code):
##   A live DEMI 2 frame is a bad oracle for a COLOR question — dozens of additive
##   particles stack + clamp on top of each other. To attribute a measured pixel to
##   ONE particle's fold-shader math, isolate a SINGLE held particle and take a
##   `with - without` difference on BOTH machines. This is the PORT half.
##
## HOW IT WORKS (zero production edits — everything lives in this throwaway):
##   1. Boot the real EffectViewer, size the window to the 256x240 virtual framebuffer
##      so 1 px == 1 virtual px (matches the PSX oracle), and let the production engine
##      fold attach to the root camera (CompositorAutopilot — Forward+ / 4.8 fork only).
##   2. play_effect(id, parked=true) + seek(N): a deterministic re-pump to frame N
##      (ADR-0070) that then HOLDS — nothing advances, so the particle sits frozen at
##      its natural age for frame N. "Freeze at age" needs no new knob.
##   3. Reach the live pool (eff.manager.get_active_particles()), enumerate every
##      particle's state, and pick exactly ONE survivor.
##   4. Disable the instance's _process (so it stops re-packing the full cloud) and
##      drive the renderer myself: update_particles([survivor]) -> capture WITH;
##      update_particles([]) -> capture WITHOUT. Diff isolates the one particle's
##      display-space additive contribution.
##
## SURFACE THE STATE: it prints a census of every particle at the seek frame (emitter,
## age, lifetime, position, frameset, color-modulate) so the matched PSX age can be
## chosen, then prints the survivor's identity after capture.
##
## CONGRUENCE (2026-07-31): renders NATIVE 256x240 (1px==1vpx), hides the two anchor units
## + the map, holds the emitter-2 seq-2 ADDITIVE particle on frameset 26 (age 7), dither off.
## The visible sky is a static ScreenEffectOverlay quad that CANCELS in with-without, so all
## measurements are the DIFF (pure additive contribution). Congruent target =
## research/working_documents/demi2_fold_audit/README.md (verdict: fold color math is FAITHFUL).
##
## RUN (headful, 4.8 compositor fork only — `godot --version` -> 4.8.dev.custom_build):
##   # from the package root
##   # capture pass (defaults are the congruent DEMI2 additive target):
##   godot --path . --rendering-method forward_plus -s res://tools/proto_single_held_particle.gd -- --effect=46 --seek=32 --emitter=2 --fs=26
##   # discovery first (census across a frame range, no capture):
##   godot --path . --rendering-method forward_plus -s res://tools/proto_single_held_particle.gd -- --scan=20,60,4
##   # controlled fold-math experiment (isolate the pow/gain — gamma is DEAD: srgb_to_linear=false):
##   ... -- --effect=46 --seek=32 --emitter=2 --fs=26 --gamma=1.0 --brightness=2.2
##
## ARGS (all optional): --effect=46 --seek=32 --emitter=2 --fs=26 --keep=0
##   --fs=N            keep only candidates on frameset N (-1 = ignore); the color track selector
##   --bg=128          flat mid-gray level (best-effort; the read is diff-based so exactness is moot)
##   --upscaled        render at the project 1280x960 instead of native 256x240
##   --gamma=/-brightness=  override the global fold uniforms at DRAW time (see NOTE in _stage_survivor)
##   --map=hide|show   (default hide)   --out=/tmp/particle_iso   --enumerate  (census only)
##   --scan=start,end,step     (print per-emitter active counts across frames, then quit)
## Then measure:  uv run --with pillow python /tmp/particle_iso/diff.py \
##                    /tmp/particle_iso/with.png /tmp/particle_iso/without.png

const Particle = preload("res://addons/exmateria_effects/particles/Particle.gd")

const VIEWER := "res://assets/scenes/EffectViewer.tscn"

var _effect := 46
var _seek := 32          # seek where an emitter-2 particle shows frameset 26 (age 7)
var _emitter := 2        # keep ONE particle from this emitter (-1 = pick globally)
var _keep := 0           # which candidate to keep, sorted by age DESC (oldest first)
var _fs := 26            # only keep candidates on this frameset (-1 = ignore frameset)
var _bg := 128           # flat mid-gray background level (matches the PSX oracle screen)
var _native := true      # render at native 256x240 (1 px == 1 virtual px) like the oracle
var _gamma := -1.0       # override global psx_gamma (fold pow exponent); <0 = leave default (1.4)
var _brightness := -1.0  # override global psx_brightness (fold gain); <0 = leave default (2.2)
var _map_hidden := true
var _rng_seed := -1      # pin EffectInstance._rng seed for a deterministic cloud (<0 = randomize)
var _out := "/tmp/particle_iso"
var _enumerate_only := false
var _scan: Array = []    # [start, end, step] discovery mode

var _scene: Node
var _eff = null
var _f := 0
var _phase := "boot"     # boot -> settle -> with -> without -> done
var _wait := 0
var _survivor = null
var _quit := false


func _initialize() -> void:
	_parse_args()
	# Native 256x240 render = 1 px == 1 virtual px, so the port capture is directly
	# pixel-comparable to the PSX oracle (which is a raw 256x240 RGB555 grab). The
	# project runs stretch=viewport at 1280x960; collapse the render + window to the
	# virtual framebuffer so root.get_texture() hands back a native-res image.
	if _native:
		root.content_scale_size = Vector2i(256, 240)
		root.size = Vector2i(256, 240)
	else:
		DisplayServer.window_set_size(Vector2i(256, 240))
	DirAccess.make_dir_recursive_absolute(_out)
	_scene = load(VIEWER).instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("[iso] PROTOTYPE single-held-particle rig | E%03d seek=%d emitter=%s keep=%d map=%s out=%s" % [
		_effect, _seek, str(_emitter), _keep, ("hidden" if _map_hidden else "shown"), _out])


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--effect="): _effect = int(s.substr(9))
		elif s.begins_with("--seek="): _seek = int(s.substr(7))
		elif s.begins_with("--emitter="): _emitter = int(s.substr(10))
		elif s.begins_with("--keep="): _keep = int(s.substr(7))
		elif s.begins_with("--fs="): _fs = int(s.substr(5))
		elif s.begins_with("--bg="): _bg = int(s.substr(5))
		elif s.begins_with("--gamma="): _gamma = float(s.substr(8))
		elif s.begins_with("--brightness="): _brightness = float(s.substr(13))
		elif s.begins_with("--rng-seed="): _rng_seed = int(s.substr(11))
		elif s == "--upscaled": _native = false
		elif s.begins_with("--map="): _map_hidden = (s.substr(6) == "hide")
		elif s.begins_with("--out="): _out = s.substr(6)
		elif s == "--enumerate": _enumerate_only = true
		elif s.begins_with("--scan="):
			var p := s.substr(7).split(",")
			if p.size() == 3:
				_scan = [int(p[0]), int(p[1]), int(p[2])]


func _process(_dt: float) -> bool:
	if _quit:
		quit()
		return true
	return false


func _on_post_draw() -> void:
	_f += 1
	if _phase == "boot":
		var ready: bool = _scene.get("_caster") != null and _scene.get("_target") != null
		if ready and _f > 20:
			_scene.call("play_effect", _effect, true)       # parked -> drive by seek
			_eff = _scene.get("_current_effect")
			if _eff == null:
				print("[iso] FAIL — no _current_effect"); _quit = true; return
			# Determinism override: EffectInstance._rng.randomize()s per process, so the held
			# particle lands at a DIFFERENT world position each run (spawn spread/cone RNG). Pin the
			# per-instance seed BEFORE the first seek so the re-pump reproduces the SAME cloud across
			# processes — required for a byte-exact A/B (old vs new fold math) capture compare.
			if _rng_seed >= 0:
				_eff._rng.seed = _rng_seed
				_eff._rng_seed = _rng_seed
				if _eff.effect_timeline != null:
					_eff.effect_timeline.set_rng(_eff._rng, _rng_seed)
				print("[iso] rng seed pinned to %d (deterministic cloud)" % _rng_seed)
			if _scan.size() == 3:
				_phase = "done"                               # leave boot so it runs once
				_do_scan()                                    # discovery: synchronous, then quit
				_quit = true; return
			_eff.call("seek", _seek)                          # re-pump is synchronous
			_census_and_pick()
			if _enumerate_only or _survivor == null:
				_quit = true; return
			_stage_survivor()                                 # WITH set staged
			_phase = "with"; _wait = 5
		elif _f > 300:
			print("[iso] FAIL — scene never became ready"); _quit = true
		return

	if _phase == "with":
		_wait -= 1
		if _wait <= 0:
			_capture("with")
			_render_set([])                                   # WITHOUT: empty set
			_phase = "without"; _wait = 5
		return

	if _phase == "without":
		_wait -= 1
		if _wait <= 0:
			_capture("without")
			_report_survivor()
			print("[iso] done. measure:")
			print("  uv run --with pillow python /tmp/particle_iso/diff.py %s/with.png %s/without.png" % [_out, _out])
			_quit = true
		return


# --- discovery: per-emitter active counts across a frame range ------------------
func _do_scan() -> void:
	var start: int = _scan[0]; var end: int = _scan[1]; var step: int = _scan[2]
	print("[iso] SCAN E%03d frames %d..%d step %d (per-emitter active particle counts):" % [
		_effect, start, end, step])
	var f := start
	while f <= end:
		_eff.call("seek", f)                                  # synchronous re-pump
		var ps: Array = _eff.manager.get_active_particles()
		var by := {}
		for p in ps:
			by[p.emitter_index] = int(by.get(p.emitter_index, 0)) + 1
		var keys := by.keys(); keys.sort()
		var parts := []
		for k in keys:
			parts.append("e%d:%d" % [k, by[k]])
		print("  f=%3d  total=%3d  %s" % [f, ps.size(), ", ".join(parts)])
		f += step


# --- census at the seek frame + pick the survivor ------------------------------
func _census_and_pick() -> void:
	var ps: Array = _eff.manager.get_active_particles()
	print("[iso] CENSUS at seek=%d — %d active particles:" % [_seek, ps.size()])
	var candidates := []
	for i in range(ps.size()):
		var p = ps[i]
		var col := _modulate_of(p)
		var tag := ""
		var emitter_ok: bool = _emitter < 0 or p.emitter_index == _emitter
		var fs_ok: bool = _fs < 0 or p.frameset_idx == _fs
		if emitter_ok and fs_ok:
			candidates.append(p)
			tag = " <-- candidate"
		print("  [%2d] e%d age=%2d/%s pos=(%.2f,%.2f,%.2f) fs=%d dm=%d col=(%.3f,%.3f,%.3f)%s" % [
			i, p.emitter_index, p.age, str(p.lifetime),
			p.position.x, p.position.y, p.position.z,
			p.frameset_idx, p.depth_mode, col.r, col.g, col.b, tag])
	if candidates.is_empty():
		print("[iso] no candidate for emitter=%s at seek=%d — nothing to isolate." % [str(_emitter), _seek])
		_survivor = null
		return
	candidates.sort_custom(func(a, b): return a.age > b.age)   # oldest first
	var k: int = clampi(_keep, 0, candidates.size() - 1)
	_survivor = candidates[k]
	print("[iso] KEEP candidate #%d of %d (emitter=%s, sorted age DESC)" % [
		k, candidates.size(), str(_emitter)])


func _modulate_of(p) -> Color:
	var r = _eff.sprite_renderer
	if r != null and r.has_method("_compute_color_modulate"):
		return r._compute_color_modulate(p)
	return Color(1, 1, 1)


# --- render control: bypass the instance loop, drive the renderer directly ------
func _stage_survivor() -> void:
	_eff.set_process(false)                                    # stop the cloud re-pack
	# Controlled fold-math experiment: override the global fold uniforms right before the
	# capture (the fold shader reads them at DRAW time). Set here — NOT in _initialize —
	# because PSXDisplay's autoload _ready re-applies the 1.4 default after _initialize.
	# NOTE: psx_brightness was DELETED in the ADR-0074 fold endgame — the fold gain is now baked
	# per-producer (EngineFoldCompositor.POOL_GOURAUD_GAIN / shader-local FOLD_GAIN consts), so
	# --brightness no longer bites and is ignored. --gamma still overrides the (surviving) psx_gamma
	# global, though EngineFoldCompositor forces srgb_to_linear=false so the pow(psx_gamma) branch is
	# dead on the folded particle anyway.
	if _gamma >= 0.0:
		RenderingServer.global_shader_parameter_set(&"psx_gamma", _gamma)
		print("[iso] fold override: psx_gamma=%s" % str(_gamma))
	if _brightness >= 0.0:
		print("[iso] NOTE: --brightness=%s ignored — psx_brightness was deleted (fold gain baked)" % str(_brightness))
	# The PSX oracle's neutral editor screen is a solid fill (no dither); the port's PSX
	# post-dither would checker the flat gray bg. It cancels in with-without, but disabling
	# it makes the captured frames visually congruent with the oracle.
	RenderingServer.global_shader_parameter_set(&"psx_dither_enabled", false)
	_make_congruent_background()
	_render_set([_survivor])


# Congruence with the PSX oracle: the color read must isolate ONE additive particle with
# no other movers in the frame. The confound that actually corrupts the read is the UNIT
# SPRITES (an animating knight leaks into with-without); those we hide. The visible sky is a
# ScreenEffectOverlay screen-space gradient (a `ScreenBackground` quad the map seeds blue) —
# it is STATIC, so it cancels exactly in the with-without difference, which is the rig's
# measurement basis. We do NOT need it flat for the numbers (every reported value is a diff);
# the diff image (pure contribution on black) is the truly congruent artifact vs `oracle-128`.
# We still best-effort flatten the 3D world environment (harmless; the overlay quad sits in
# front of it) and kill PSX dither so the WITH capture eyeballs cleaner.
func _make_congruent_background() -> void:
	if _map_hidden:
		var pmap := _scene.get_node_or_null("ProceduralMap")
		if pmap != null:
			pmap.visible = false
	# Hide the two anchor units — THE confound. They stay in the tree (the effect anchors to
	# their positions) but render nothing, so with-without can't leak an animating sprite.
	for uname in ["Caster", "Target"]:
		var u := _scene.get_node_or_null(uname) as Node3D
		if u != null:
			u.visible = false
	var g := float(_bg) / 255.0
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(g, g, g)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR         # display-space fold requires LINEAR
	env.sdfgi_enabled = false
	env.glow_enabled = false
	env.fog_enabled = false
	root.world_3d.environment = env
	print("[iso] congruent: units+map hidden, dither off. Screen-overlay sky is static → " +
		"cancels in with-without (measure the DIFF).")


func _render_set(particles: Array) -> void:
	# update_particles wants a typed Array[Particle]; rebuild one (works for the
	# one-element WITH set and the empty WITHOUT set alike).
	var r = _eff.sprite_renderer
	if r == null:
		return
	var typed: Array[Particle] = []
	for p in particles:
		typed.append(p)
	r._effect_world_origin = _eff.global_position
	r.update_particles(typed)


func _capture(tag: String) -> void:
	var img := root.get_texture().get_image()
	var path := "%s/%s.png" % [_out, tag]
	img.save_png(path)
	print("[iso] CAPTURED %s (%dx%d) -> %s" % [tag, img.get_width(), img.get_height(), path])


func _report_survivor() -> void:
	var p = _survivor
	var col := _modulate_of(p)
	print("[iso] HELD PARTICLE (match the PSX lifetime to this age): " +
		"emitter=%d age=%d/%s pos=(%.3f,%.3f,%.3f) frameset=%d depth_mode=%d col=(%.3f,%.3f,%.3f)" % [
		p.emitter_index, p.age, str(p.lifetime),
		p.position.x, p.position.y, p.position.z,
		p.frameset_idx, p.depth_mode, col.r, col.g, col.b])
