@tool
extends Node3D


signal shape_changed


const ScatterUtil := preload('./common/scatter_util.gd')
const ModifierStack := preload("./stack/modifier_stack.gd")
const TransformList := preload("./common/transform_list.gd")
const ScatterItem := preload("./scatter_item.gd")
const ScatterShape := preload("./scatter_shape.gd")
const Domain := preload("./common/domain.gd")


@export var global_seed := 0:
	set(val):
		global_seed = val
		rebuild()

@export var use_instancing := true:
	set(val):
		use_instancing = val
		rebuild(true)

var undo_redo: UndoRedo
var modifier_stack: ModifierStack:
	set(val):
		modifier_stack = val.get_copy() # Enfore uniqueness
		modifier_stack.owner = self
		modifier_stack.value_changed.connect(rebuild)
		modifier_stack.stack_changed.connect(rebuild)

var domain: Domain:
	set(val):
		domain = Domain.new() # Enforce uniqueness

var items: Array[ScatterItem]
var total_item_proportion: int
var output_root: Node3D

var _rebuilt_this_frame := false


func _ready() -> void:
	_perform_sanity_check()
	set_notify_transform(true)
	child_exiting_tree.connect(_on_child_exiting_tree)
	rebuild(true)


func _get_property_list() -> Array:
	var list := []
	list.push_back({
		name = "ProtonScatter",
		type = TYPE_NIL,
		usage = PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_SCRIPT_VARIABLE,
	})
	list.push_back({
		name = "modifier_stack",
		type = TYPE_OBJECT,
		hint_string = "ScatterModifierStack",
	})
	return list


func _get_configuration_warning() -> String:
	var warning = ""
	if items.is_empty():
		warning += "At least one ScatterItem node is required.\n"
	if domain.is_empty():
		warning += "At least one ScatterShape node in inclusive mode is required.\n"
	return warning


func _notification(what):
	match what:
		NOTIFICATION_TRANSFORM_CHANGED:
			domain.compute_bounds()
			rebuild()


func _set(property, _value):
	if not Engine.is_editor_hint():
		return false

	# Workaround to detect when the node was duplicated from the editor.
	if property == "transform":
		call_deferred("_on_node_duplicated")

	return false


# Only used for type checking.
# Useful to other scripts which can't preload this due to cyclic references.
func is_scatter_node() -> bool:
	return true


func full_rebuild():
	_clear_output()
	_rebuild(true)


# A wrapper around the _rebuild function. Ensure it's not called more than once
# per frame. (Happens when the Scatter node is moved, which triggers the
# TRANSFORM_CHANGED notification in every children, which in turn notify the
# parent Scatter node back about the changes.
func rebuild(force_discover := false) -> void:
	if not is_inside_tree():
		return

	if _rebuilt_this_frame:
		return

	_rebuilt_this_frame = true

	force_discover = true # TMP while we fix the other issues
	_rebuild(force_discover)

	await get_tree().process_frame
	_rebuilt_this_frame = false


# Re compute the desired output.
# This is the main function, scattering the objects in the scene.
# Scattered objects are stored under a Position3D node called "ScatterOutput"
# DON'T call this function directly outside of the 'rebuild()' function above.
func _rebuild(force_discover) -> void:
	if force_discover:
		_discover_items()
		domain.discover_shapes(self)

	if items.is_empty() or domain.is_empty():
		return

	var transforms: TransformList = modifier_stack.update()
	if use_instancing:
		_update_multimeshes(transforms)
	else:
		_update_duplicates(transforms)


func _discover_items() -> void:
	items.clear()
	total_item_proportion = 0

	for c in get_children():
		if c is ScatterItem:
			items.push_back(c)
			total_item_proportion += c.proportion

	if is_inside_tree():
		get_tree().node_configuration_warning_changed.emit(self)


# Creates one MultimeshInstance3D for each ScatterItem node.
func _update_multimeshes(transforms: TransformList) -> void:
	var offset := 0
	var transforms_count: int = transforms.size()
	var inverse_transform := global_transform.affine_inverse()

	for item in items:
		var item_root = ScatterUtil.get_or_create_item_root(item)
		var count = int(round(float(item.proportion) / total_item_proportion * transforms_count))
		var mmi = ScatterUtil.get_or_create_multimesh(item, count)
		if not mmi:
			return
		var c = 0.0
		var c_increments = 1.0 / count

		var t: Transform3D
		for i in count:
			# Extra check because of how 'count' is calculated
			if (offset + i) >= transforms_count:
				mmi.multimesh.instance_count = i - 1
				return

			t = item.process_transform(transforms.list[offset + i])
			mmi.multimesh.set_instance_transform(i, inverse_transform * t)
			mmi.multimesh.set_instance_color(i, Color(c, c, c))
			c += c_increments

		offset += count


func _update_duplicates(transforms: TransformList) -> void:
	pass


# Deletes what the Scatter node generated.
func _clear_output() -> void:
	ScatterUtil.ensure_output_root_exists(self)
	for c in output_root.get_children():
		c.queue_free()


# Enforce the Scatter node has its required variables set.
func _perform_sanity_check() -> void:
	if not modifier_stack:
		modifier_stack = ModifierStack.new()

	if not domain:
		domain = Domain.new()


func _on_node_duplicated() -> void:
	_perform_sanity_check()
	full_rebuild() # Otherwise we get linked multimeshes or other unwanted side effects


func _on_child_exiting_tree(node: Node) -> void:
	if node is ScatterShape or node is ScatterItem:
		call_deferred("rebuild", true)
