class_name Canvas
extends RefCounted
## Abstract 2D path-drawing sink with the subset of the HTML canvas API that js/render.js uses for the line figures.
## Two implementations: RecordingCanvas (logs the calls like the JS fake context, for parity tests) and DrawCanvas
## (draws into a CanvasItem). State does not unwind on restore(): this mirrors the JS test fake, and the figure code
## never relies on restore() resetting properties.

var global_alpha: float = 1.0
var stroke_style: String = "#000"
var fill_style: String = "#000"
var line_width: float = 1.0
## Text state (js ctx.font / textAlign / textBaseline): font_px, bold, align "left"|"center"|"right".
var font_px: float = 10.0
var font_bold: bool = false
var text_align: String = "left"


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


func arc(_x: float, _y: float, _r: float, _a0: float, _a1: float, _ccw: Variant = null) -> void:
	pass


func ellipse(_x: float, _y: float, _rx: float, _ry: float, _rot: float, _a0: float, _a1: float, _ccw: Variant = null) -> void:
	pass


func stroke() -> void:
	pass


## Fill the rect() subpaths of the current path (the only filled shapes the renderer uses are dots).
func fill() -> void:
	pass


func translate(_x: float, _y: float) -> void:
	pass


func scale(_x: float, _y: float) -> void:
	pass


func rotate(_a: float) -> void:
	pass


func fill_rect(_x: float, _y: float, _w: float, _h: float) -> void:
	pass


func fill_text(_text: String, _x: float, _y: float, _max_w: float = -1.0) -> void:
	pass


func stroke_text(_text: String, _x: float, _y: float) -> void:
	pass


## js ctx.measureText(text).width; -1 when the canvas cannot measure (the caller then estimates).
func measure_text(_text: String) -> float:
	return -1.0
