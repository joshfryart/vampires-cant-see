class_name Canvas
extends RefCounted
## Abstract 2D path-drawing sink with the subset of the HTML canvas API that js/render.js uses for the line figures.
## Two implementations: RecordingCanvas (logs the calls like the JS fake context, for parity tests) and DrawCanvas
## (draws into a CanvasItem). State does not unwind on restore(): this mirrors the JS test fake, and the figure code
## never relies on restore() resetting properties.

var global_alpha: float = 1.0
var stroke_style: String = "#000"
var line_width: float = 1.0


func set_transform(_a: float, _b: float, _c: float, _d: float, _e: float, _f: float) -> void:
	pass


func save() -> void:
	pass


func restore() -> void:
	pass


func begin_path() -> void:
	pass


func close_path() -> void:
	pass


func move_to(_x: float, _y: float) -> void:
	pass


func line_to(_x: float, _y: float) -> void:
	pass


func quad_to(_cx: float, _cy: float, _x: float, _y: float) -> void:
	pass


func rect(_x: float, _y: float, _w: float, _h: float) -> void:
	pass


func clip() -> void:
	pass


func arc(_x: float, _y: float, _r: float, _a0: float, _a1: float, _ccw: bool = false) -> void:
	pass


func ellipse(_x: float, _y: float, _rx: float, _ry: float, _rot: float, _a0: float, _a1: float, _ccw: bool = false) -> void:
	pass


func stroke() -> void:
	pass
