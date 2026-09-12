extends RefCounted
## Duck-typed contract for an effect-cast **subsystem** — the runtime that reads
## parsed keyframe data and turns frames into output. There are four: Color,
## Camera, Particle, Sound. The vocabulary lives in CONTEXT.md "Effect
## orchestration"; the wider context is ADR-0011 / 0012 / 0014.
##
## (There is no runtime "track" concept — historical *TrackController class
## names were retired in #31.) Subsystems read parsed data from the
## per-cast JSON files (`camera.json`, `palette.json`, `screen.json`, particle
## channels from `timeline.json`); the on-disk file convention is the only
## surviving mention of the word — see CONTEXT.md "Effect orchestration".
##
## A subsystem is pumped by [EffectTimeline] once per fixed frame via
## [method advance], which broadcasts the current effect frame and the set of
## open phases. The subsystem owns its own keyframe-cursor state — its per-phase
## blocks, channels, and per-channel cursors — and emits its own signals when it
## produces output. The timeline owns clock + phase state only; subsystems own
## everything keyframe-shaped.
##
## ## Conformance
##
## This contract is documented, not enforced. GDScript's single-inheritance
## constrains real conformance: a subsystem that already extends [Node]
## (`ParticleSubsystem`, which holds scene-child emitters) cannot also extend
## `Subsystem`. Such subsystems satisfy the contract duck-style and document
## their conformance in a top-of-file note. Subsystems with no other inheritance
## constraint extend `Subsystem` directly (the color family does — `ColorSubsystem`
## is the base, `PaletteSubsystem` and `ScreenSubsystem` extend it by path per
## the ADR-0004 cache-safety pattern).
##
## See also: [EffectTimeline] (the pump), CONTEXT.md "Effect orchestration"
## cluster (the vocabulary), ADR-0014 (the time-modulation relocation that made
## this contract load-bearing).


func advance(_frame: int, _phase: Array) -> void:
	"""Advance the subsystem to the given effect frame within the given set
	of open phases. The subsystem reads its own keyframes against
	`(frame, phase)` and fires any signals that come due on this tick."""
	push_error("Subsystem.advance must be overridden")


func reset() -> void:
	"""Return the subsystem to its just-initialised state — all cursors at
	zero, all per-channel state cleared, all pending output dropped."""
	push_error("Subsystem.reset must be overridden")


func is_done() -> bool:
	"""Return true once the subsystem has produced its last output and the
	timeline may consider it finished."""
	push_error("Subsystem.is_done must be overridden")
	return false
