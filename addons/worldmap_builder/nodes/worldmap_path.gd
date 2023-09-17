@tool
class_name WorldmapPath
extends Node2D

enum PathMode {
	LINE = 0,
	ARC,
	BEZIER,
}

## Emitted when a node on this path receives input.
signal node_gui_input(event : InputEvent, uid : int, resource : WorldmapNodeData)

@export_group("Points")
@export var start := Vector2(INF, INF):
	set(v):
		start = v
		queue_redraw()
@export var end := Vector2(INF, INF):
	set(v):
		end = v
		queue_redraw()
@export var handle_1 := Vector2(INF, INF):
	set(v):
		handle_1 = v
		queue_redraw()
@export var handle_2 := Vector2(0, 0):
	set(v):
		handle_2 = v
		queue_redraw()

@export_group("Path")
@export var mode : PathMode:
	set(v):
		mode = v
		queue_redraw()
@export var bidirectional := false:
	set(v):
		bidirectional = v
		queue_redraw()
@export var end_with_empty := false:
	set(v):
		end_with_empty = v
		queue_redraw()
@export var end_connections : Array[WorldmapPath]:
	set(v):
		end_connections = v
		queue_redraw()

var node_datas : Array[WorldmapNodeData]

var _node_controls : Array[Control] = []
var _arc_changing := false

## Calculate distance between any 2 points, if using a mode that spaces them equally. [br]
## [b]Note:[/b] undefined behaviour for the [code]PathMode.BEZIER[/code] mode.
func get_distance_between_points() -> float:
	var segment_count := node_datas.size() + (1 if end_with_empty else 0)
	if mode == PathMode.ARC:
		var arc_angle := (start - handle_1).angle_to(end - handle_1)
		var chord_length := ((start - handle_1) - (start - handle_1).rotated(arc_angle / segment_count)).length()
		return chord_length

	else:
		return (start - end).length() / segment_count

## Align points so that distance between them equals the specified amount. [br]
## The [member start] point will always stay in place. [br]
## [b]Note:[/b] undefined behaviour for the [code]PathMode.BEZIER[/code] mode.
func set_distance_between_points(value : float):
	var segment_count := node_datas.size() + (1 if end_with_empty else 0)
	if mode == PathMode.ARC:
		var radius := (start - handle_1).length()
		var half_sine := value * 0.5 / radius
		var arc_angle := asin(half_sine) * 2.0 * segment_count
		end = handle_1 + (start - handle_1).rotated(arc_angle)

	elif mode == PathMode.LINE:
		end = start + (end - start).normalized() * value * segment_count


func _enter_tree():
	if end.x == INF:
		end = start + Vector2(64.0, 0.0)
		handle_1 = start + Vector2(0.0, 0.0)
		handle_2 = end + Vector2(0.0, 0.0)

	if position != Vector2.ZERO:
		start += position
		end += position
		handle_1 += position
		if mode != PathMode.BEZIER: handle_2 += position
		position = Vector2.ZERO


func _draw():
	var last_pos := Vector2.ZERO
	var count_nodes := node_datas.size()
	var count_points := count_nodes + (1 if end_with_empty else 0)
	var angle_diff := (start - handle_1).angle_to(end - handle_1)
	var is_editor := Engine.is_editor_hint()
	for x in _node_controls:
		x.hide()

	for i in count_nodes + 1:
		var cur_pos := last_pos
		match mode:
			PathMode.LINE:
				cur_pos = lerp(start, end, float(i) / count_points)

			PathMode.ARC:
				cur_pos = (start - handle_1).rotated(angle_diff * i / count_points) + handle_1

			PathMode.BEZIER:
				cur_pos = start.bezier_interpolate(handle_1, handle_2, end, float(i) / count_points)

		last_pos = cur_pos
		if i == 0 || node_datas[i - 1] == null:
			continue

		var tex := node_datas[i - 1].texture
		var tex_size := tex.get_size()
		var node := _node_controls[i - 1]
		node.position = cur_pos - tex_size * 0.5
		node.size = tex_size
		node.show()
		draw_texture(tex, cur_pos - tex_size * 0.5)


func _set(property : StringName, value) -> bool:
	if property == "node_count":
		node_datas.resize(value)
		notify_property_list_changed()
		queue_redraw()
		while _node_controls.size() < value:
			var new_control := Control.new()
			new_control.gui_input.connect(_on_node_gui_input.bind(_node_controls.size()))
			add_child(new_control)
			_node_controls.append(new_control)

		while _node_controls.size() > value:
			_node_controls.pop_back().queue_free()

		return true

	if property == "node_set_all":
		node_datas.fill(value)
		queue_redraw()
		return true

	if property.begins_with("node_"):
		var name_split := property.trim_prefix("node_").split("/")
		var index := name_split[0].to_int()
		match name_split[1]:
			"data": node_datas[index] = value

		queue_redraw()
		return true

	return false


func _get(property : StringName):
	if property == "node_count":
		return node_datas.size()

	if property == "node_set_all":
		return null

	if property.begins_with("node_"):
		var name_split := property.trim_prefix("node_").split("/")
		var index := name_split[0].to_int()
		match name_split[1]:
			"data": return node_datas[index]

	return null


func _property_can_revert(property : StringName):
	match property:
		&"start":
			return end != start
		&"end":
			return end != start
		&"handle_1":
			return handle_1 != start
		&"handle_2":
			return handle_2 != end


func _property_get_revert(property : StringName):
	match property:
		&"start":
			return end
		&"end":
			return start
		&"handle_1":
			return start
		&"handle_2":
			return end


func _get_property_list() -> Array:
	var result := []
	result.append({
		&"name": "node_count",
		&"type": TYPE_INT,
		&"usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_ARRAY,
		&"hint": PROPERTY_HINT_NONE,
		&"hint_string": "",
		&"class_name": "Path Nodes,node_",
	})
	for i in node_datas.size():
		result.append({
			&"name": "node_%d/data" % i,
			&"type": TYPE_OBJECT,
			&"hint": PROPERTY_HINT_RESOURCE_TYPE,
			&"hint_string": "WorldmapNodeData",
		})
	
	result.append({
		&"name": "node_set_all",
		&"type": TYPE_OBJECT,
		&"hint": PROPERTY_HINT_RESOURCE_TYPE,
		&"hint_string": "WorldmapNodeData",
		&"usage": PROPERTY_USAGE_EDITOR,
	})
	return result


func _on_node_gui_input(event : InputEvent, index : int):
	if node_datas[index] == null:
		return

	node_gui_input.emit(event, index, node_datas[index])