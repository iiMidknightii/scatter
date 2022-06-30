extends Resource


# point must be in global space
func is_point_inside(point: Vector3, global_transform: Transform3D) -> bool:
	return false


# Returns an array of Vector3. This should contain enough points to compute
# a bounding box for the given shape.
func get_corners_global(global_transform: Transform3D) -> Array:
	return []


# Returns a copy of this shape.
# TODO: check later when Godot4 enters beta if we can get rid of this and use
# the built-in duplicate() method properly.
func get_copy() -> Resource:
	return null
