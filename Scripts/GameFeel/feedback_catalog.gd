class_name FeedbackCatalog
extends Resource

## Cue-to-profile lookup with a variant fallback chain:
## (cue, variant) then (cue, no variant) then the profile named `fallback_cue_id`.

## Every authored profile. Keep one default (empty variant) per cue.
@export var profiles: Array[FeedbackProfile] = []
## Cue whose default profile answers an unknown cue. An empty catalog resolves to null.
@export var fallback_cue_id: StringName = &"fallback"

func resolve(cue_id: StringName, variant_id: StringName = &"") -> FeedbackProfile:
	var found := _find(cue_id, variant_id)
	if found == null and variant_id != &"":
		found = _find(cue_id, &"")
	if found == null:
		found = _find(fallback_cue_id, &"")
	return found

func _find(cue_id: StringName, variant_id: StringName) -> FeedbackProfile:
	for profile in profiles:
		if profile != null and profile.cue_id == cue_id and profile.variant_id == variant_id:
			return profile
	return null
