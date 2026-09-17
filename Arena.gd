extends Node2D

const WALL_COLOR := Color(0.62, 0.72, 0.86)
const FLOOR_COLOR := Color(0.10, 0.12, 0.17)
const WALL_WIDTH := 4.0
const MARGIN := 24.0
# The top band is reserved for the HUD so pickups never hide under it.
const TOP_MARGIN := 72.0

var bounds: Rect2

func _ready():
	recalculate()
	get_viewport().size_changed.connect(_on_viewport_resized)

func _on_viewport_resized():
	recalculate()
	queue_redraw()

func recalculate():
	var viewport_size = get_viewport_rect().size
	bounds = Rect2(
		MARGIN,
		TOP_MARGIN,
		viewport_size.x - MARGIN * 2,
		viewport_size.y - TOP_MARGIN - MARGIN
	)

func _draw():
	draw_rect(bounds, FLOOR_COLOR, true)
	draw_rect(bounds, WALL_COLOR, false, WALL_WIDTH)
