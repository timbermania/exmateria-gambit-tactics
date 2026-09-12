@tool
extends Resource

## One row of the animation resolution map for a parameterless activity.
##
## The activity identity (IDLE / WALKING / DYING / …) is held by the
## Dictionary key in SpriteTypeResource.states — not stored here, so
## there's exactly one source of truth.
##
## Front/back are explicit SEQ slot ids (front variant for camera-relative
## use_back=false, back variant for use_back=true). Unlike attack /
## cast / charge — which derive back as front+1 — state_animations rows
## may carry non-adjacent pairs, so both are stored.

@export var front: int = -1
@export var back: int = -1
