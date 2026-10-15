extends GraphEdit
## GraphEditExt — GraphEdit that also accepts brick drops from the palette.
##
## The palette starts a drag carrying {"kind": ..., "from_palette": true}. When
## dropped here we emit `brick_dropped(kind, position)` so the main UI can
## create the brick at that spot. GraphEdit's own node-drag behaviour is
## untouched (we only add the palette-drop path).

signal brick_dropped(kind: String, at_position: Vector2)

func _can_drop_data(at_position: Vector2, data) -> bool:
	if data is Dictionary and data.get("from_palette", false) and data.has("kind"):
		# convert to graph-local coords for the drop position
		return true
	return false

func _drop_data(at_position: Vector2, data) -> void:
	if data is Dictionary and data.get("from_palette", false) and data.has("kind"):
		# at_position is in GraphEdit local space; scroll_offset maps to content
		var content_pos := at_position + scroll_offset
		brick_dropped.emit(str(data["kind"]), content_pos)
