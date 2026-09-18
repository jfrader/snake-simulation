extends CanvasLayer

const Save = preload("res://src/Save.gd")

const TIME_SIZE := 40
const VALUE_SIZE := 20
const CAPTION_SIZE := 15
const TITLE_SIZE := 54
const DETAIL_SIZE := 22
const HINT_SIZE := 18

const TEXT_COLOR := Color(0.87, 0.91, 0.98)
const DIM_COLOR := Color(0.58, 0.64, 0.75)
const ACCENT_COLOR := Color(0.62, 0.88, 0.48)
const DANGER_COLOR := Color(0.96, 0.51, 0.42)
const PANEL_COLOR := Color(0.043, 0.055, 0.078, 0.94)
const BAR_BACK_COLOR := Color(0.15, 0.18, 0.24, 1.0)

const BAND_HEIGHT := 72.0
const BAR_WIDTH := 170.0
const BAR_HEIGHT := 12.0
const PAD := 36.0

var time_label: Label
var score_label: Label
var best_label: Label
var larder_caption: Label
var larder_fill: ColorRect
var speed_caption: Label
var speed_fill: ColorRect
var pip_row: Control
var pips: Array = []

var title_label: Label
var detail_label: Label
var hint_label: Label
var pause_label: Label
var pause_detail: Label

var _play_nodes: Array = []
var _lives_shown := -1


func _make_label(position: Vector2, size: int, color: Color) -> Label:
	var label = Label.new()
	label.position = position
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label


func _make_bar(origin: Vector2) -> ColorRect:
	var back = ColorRect.new()
	back.position = origin
	back.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	back.color = BAR_BACK_COLOR
	add_child(back)

	var fill = ColorRect.new()
	fill.position = origin
	fill.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	fill.color = ACCENT_COLOR
	add_child(fill)
	return fill


func _make_centered(size: int, color: Color, y: float) -> Label:
	var viewport = get_viewport().get_visible_rect().size
	var label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(viewport.x, size * 1.6)
	label.position = Vector2(0, y)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label


func _ready() -> void:
	_build_hud()
	# Everything built above belongs to the in-run readout.
	_play_nodes = get_children()
	_build_overlay()


func _build_hud() -> void:
	var viewport = get_viewport().get_visible_rect().size
	var panel = ColorRect.new()
	panel.position = Vector2.ZERO
	panel.size = Vector2(viewport.x, BAND_HEIGHT)
	panel.color = PANEL_COLOR
	add_child(panel)

	# Time is the headline: it is the score that matters.
	time_label = _make_label(Vector2(PAD, 10.0), TIME_SIZE, TEXT_COLOR)
	score_label = _make_label(Vector2(PAD + 200.0, 13.0), VALUE_SIZE, ACCENT_COLOR)
	best_label = _make_label(Vector2(PAD + 200.0, 40.0), CAPTION_SIZE, DIM_COLOR)

	pip_row = Control.new()
	pip_row.position = Vector2(PAD + 440.0, 15.0)
	add_child(pip_row)

	larder_caption = _make_label(Vector2(PAD + 440.0, 32.0), CAPTION_SIZE, DIM_COLOR)
	larder_fill = _make_bar(Vector2(PAD + 440.0, 54.0))

	speed_caption = _make_label(Vector2(PAD + 670.0, 32.0), CAPTION_SIZE, DIM_COLOR)
	speed_fill = _make_bar(Vector2(PAD + 670.0, 54.0))


func _build_overlay() -> void:
	var middle = get_viewport().get_visible_rect().size.y / 2.0
	title_label = _make_centered(TITLE_SIZE, ACCENT_COLOR, middle - 150.0)
	detail_label = _make_centered(DETAIL_SIZE, TEXT_COLOR, middle - 70.0)
	hint_label = _make_centered(HINT_SIZE, DIM_COLOR, middle + 80.0)
	pause_label = _make_centered(TITLE_SIZE, TEXT_COLOR, middle - 90.0)
	pause_detail = _make_centered(DETAIL_SIZE, DIM_COLOR, middle - 10.0)

	title_label.hide()
	detail_label.hide()
	hint_label.hide()
	pause_label.hide()
	pause_detail.hide()


# Purely presentational: every value and ratio is computed by the scene.
func update_hud(readout: Dictionary) -> void:
	time_label.text = readout["time"]
	score_label.text = "SCORE  %d" % readout["score"]
	best_label.text = "BEST  " + Save.format_best(readout["best"])
	_set_pips(readout["lives"])

	var starving: bool = readout["starving"]
	larder_fill.size.x = BAR_WIDTH * clampf(readout["larder"], 0.0, 1.0)
	larder_fill.color = DANGER_COLOR if starving else ACCENT_COLOR
	larder_caption.text = "LARDER  %d" % readout["length"]
	if starving:
		larder_caption.text = "LARDER  %d  —  EAT" % readout["length"]
	larder_caption.add_theme_color_override("font_color", DANGER_COLOR if starving else DIM_COLOR)

	var speed_ratio: float = readout["speed"]
	speed_fill.size.x = BAR_WIDTH * clampf(readout["speed_bar"], 0.0, 1.0)
	speed_fill.color = ACCENT_COLOR.lerp(DANGER_COLOR, clampf(1.0 - speed_ratio, 0.0, 1.0))
	speed_caption.text = "SPEED  %d%%" % roundi(speed_ratio * 100.0)


func _set_pips(lives: int) -> void:
	if lives == _lives_shown:
		return
	_lives_shown = lives
	for pip in pips:
		pip.queue_free()
	pips.clear()
	for i in range(maxi(lives, 0)):
		var pip = ColorRect.new()
		pip.position = Vector2(i * 18.0, 0.0)
		pip.size = Vector2(11.0, 11.0)
		pip.color = DANGER_COLOR
		pip_row.add_child(pip)
		pips.append(pip)


# The readout has nothing to say before a run starts.
func set_play_hud_visible(shown: bool) -> void:
	for node in _play_nodes:
		node.visible = shown


func show_title(title: String, detail: String, hint: String) -> void:
	title_label.text = title
	detail_label.text = detail
	hint_label.text = hint
	title_label.show()
	detail_label.show()
	hint_label.show()


func hide_overlay() -> void:
	title_label.hide()
	detail_label.hide()
	hint_label.hide()


func set_paused(paused: bool, detail := "") -> void:
	pause_label.visible = paused
	pause_detail.visible = paused
	if paused:
		pause_label.text = "PAUSED"
		pause_detail.text = detail
