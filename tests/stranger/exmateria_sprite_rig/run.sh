#!/usr/bin/env bash
# The stranger rig for `addons/exmateria_sprite_rig`. ADR-0194 dec. 3 puts the
# entry point per addon; `shared/rig.sh` is the one implementation behind all of them.
exec "$(dirname "${BASH_SOURCE[0]}")/../shared/rig.sh" "$(dirname "${BASH_SOURCE[0]}")"
