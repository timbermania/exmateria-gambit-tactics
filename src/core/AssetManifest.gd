extends Node
## Boot-time guard against MISSING GENERATED ASSETS.
##
## ROM-derived parsed assets (sprite/EVTCHR textures, SEQ/SHP/cinematic JSON,
## maps, fonts) are gitignored and regenerated per-machine via
## `tools/bootstrap_assets.sh`. A stale or partial checkout therefore breaks
## features *silently* — the canonical case is a missing `cinematic_seq.json`,
## which makes every EVTCHR cinematic anim (Ovelia's nod, Ramza's kneel) abort
## with only a buried `push_warning`, so the scene plays with no cinematics and
## nobody notices.
##
## This autoload checks a list of REQUIRED generated assets at startup and fails
## LOUDLY (red `push_error` + stderr banner) listing exactly what's missing and
## the command to regenerate it. It does NOT quit — the rest of the game still
## runs — but the failure is impossible to miss.
##
## To cover a new generated asset: add one `path -> regen command` entry to
## REQUIRED. Only list assets whose absence breaks a feature *silently* (no hard
## crash). Hand-authored or optional files (e.g. *_names.json) do NOT belong here
## — listing them would produce false alarms on a correct checkout.

const REQUIRED := {
	"res://assets/sprites/animations/cinematic_seq.json":
		"uv run python tools/parse_cinematic_seq.py",
	"res://assets/sprites/animations/evtchr_frames.json":
		"uv run python tools/parse_evtchr_frames.py",
	"res://assets/sprites/textures/evtchr/segment_000.tga":
		"uv run python tools/bake_evtchr_textures.py",
}


func _ready() -> void:
	var missing: Array = []
	for path in REQUIRED:
		# A generated file counts as present if it exists on disk (JSON) or as an
		# imported resource (TGA). Either check passing means the asset is there.
		if not FileAccess.file_exists(path) and not ResourceLoader.exists(path):
			missing.append(path)
	if missing.is_empty():
		return

	var lines: Array = []
	lines.append("=================================================================")
	lines.append("MISSING GENERATED ASSETS — regenerate with: bash tools/bootstrap_assets.sh")
	lines.append("(these are gitignored & built per-machine; a stale checkout breaks")
	lines.append(" features silently — e.g. no cinematic_seq.json → no EVTCHR cinematics)")
	for path in missing:
		lines.append("  MISSING  %s" % path)
		lines.append("           regenerate: %s" % REQUIRED[path])
	lines.append("=================================================================")
	var banner: String = "\n".join(lines)
	printerr(banner)        # stderr, unmissable in CLI/headful logs
	push_error(banner)      # red in the editor error panel + stack
