extends GambitScenarioRunner

## Scene wrapper for the gambit scenario suite (issue #57). Aggregates every
## scenario file in [code]tests/gambit_scenarios/[/code] and prints a
## six-state verdict per scenario plus a summary block. The single
## [code][PASS]/[FAIL][/code] line at the tail is what [code]tests/run_all_tests.sh[/code]
## keys off — XFAIL / XPASS are loud-but-green (soft-fail default per #56).
