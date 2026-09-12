class_name GarilandMutationScript
extends RefCounted

## [b]Forwarder — the authored tables are gone (ADR-0216).[/b] This class used to author
## the Gariland roster seed by hand: Ramza + 4 invented generics keyed at `opener:10`.
## The ROM says Gariland grants nobody and the Military Academy (root 7) grants six
## cadets, so that table was measurably wrong and [StoryMutationScript] derives the
## roster from ENTD `join_after_event` flags instead.
##
## What survives is the NAME, for the three consumers that walk no plan and ask for the
## owned seed directly ([GPUArena], [CombatUITestScene], `CharacterRosterParityTest`).
## Prefer [StoryMutationScript] in new code.

## The protagonist's canonical slug. Re-exported so the existing call sites keep reading
## it from here rather than each learning the new home.
const RAMZA_SLUG := StoryMutationScript.RAMZA_SLUG


## The owned roster as it stands when Gariland boots — see
## [method StoryMutationScript.owned_seed_deltas].
static func owned_seed_deltas() -> Array:
	return StoryMutationScript.owned_seed_deltas()
