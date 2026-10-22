class_name IconRect
extends Control
## A hand-drawn icon (render/icons.gd) as a control: redrawn every frame so the line boil runs, for the shop, boon, gift
## and guide cards.

var icon_name: String = "bat"
var t: float = 0.0
var _canvas := DrawCanvas.new()


func _init(name_: String = "bat", px: float = 44.0) -> void:
	icon_name = name_
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _draw() -> void:
	_canvas.reset()
	var px: float = minf(size.x, size.y)
	_canvas.translate(size.x / 2.0, size.y / 2.0)
	Icons.draw(_canvas, icon_name, px, t)
	_canvas.paint(self)
