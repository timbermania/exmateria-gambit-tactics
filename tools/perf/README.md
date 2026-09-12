# Perf harnesses — GPU Arena investigation (2026-09-05)

Run harnesses behind `../../docs/GPU-ARENA-PERF.md`. **Not part of the game or
the test suite** — `.gdignore` keeps Godot's importer out of this directory.

| script | what it runs |
|---|---|
| `run_arena.sh` | the standard arena harness — seeded, autostarted, `--perf-debug` |
| `run_r13.sh` | display-driver / vsync sweep (that hypothesis is settled and refuted) |
| `run_r16.sh` | time-scale probe for the tick catch-up loop |

The three standalone differential rigs (`vmbench`, `drawbench`, `vsynctest`) are
**not here**: a Godot project cannot nest inside another Godot project without
its `res://` refs resolving against the wrong root. They live at the monorepo
root, `tools/perf-rigs/` — see that directory's README.

## Run logs

Not in git: `.gitignore` ignores `godot-learning/**/logs/` by policy. The seven
runs the original conclusions rest on are parked at
`~/.local/share/fft-perf-logs/` on the investigating machine, and every number
extracted from them is already in the living doc. They also **expire**: the
first ticket of the planning map rebuilds the engine with `dev_build=no`, after
which every absolute figure in them is superseded.

## ⚠ Rig hygiene

Read the "Rig hygiene" section of the living doc before any measurement run.
`misc:render_unfocused_fps` in the user's Hyprland config silently caps
agent-launched windows to ~62 fps and invalidated eleven rounds before it was
caught. Never invoke Godot with `--headless`. Check `/proc/loadavg` before
believing any number.
