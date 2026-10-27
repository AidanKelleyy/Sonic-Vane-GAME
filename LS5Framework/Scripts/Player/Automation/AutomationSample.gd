@tool
extends RefCounted
class_name AutomationSample

var valid: bool = false
var revision: int = 0
var segment: int = -1
var distance: float = 0.0
var position: Vector3 = Vector3.ZERO
var tangent: Vector3 = Vector3.FORWARD
var normal: Vector3 = Vector3.RIGHT
var up: Vector3 = Vector3.UP
var spatial_error: float = INF
var recovered: bool = false


func get_transform() -> Transform3D:
	return Transform3D(Basis(normal, up, -tangent), position)
