class_name TuneFreedOwnerProbe
extends Node
## Test probe for TuneTest's mid-emit free hazard: an on_update apply Callable bound to THIS
## node (the same shape as UI3Element's `on_update(self, slug, func: ...)`), so freeing the
## node makes the Callable's object invalid — the case Tune.on_update's `apply.is_valid()`
## guard must skip. Records into a shared external sink so the test can observe applies that
## DID land (the freed one must not).

var sink: Array = []


## The on_update apply target — `Callable(self, "on_value")`. Bound to self, so after the node
## is freed the Callable reports is_valid() == false.
func on_value(v: Variant) -> void:
	sink.append(v)
