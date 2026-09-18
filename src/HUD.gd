extends CanvasLayer

const LABEL_SIZE := 22
const TITLE_SIZE := 52
const HINT_SIZE := 21
const TEXT_COLOR := Color(0.87, 0.91, 0.98)
const ACCENT_COLOR := Color(0.62, 0.88, 0.48)
const DANGER_COLOR := Color(0.96, 0.51, 0.42)

# One HUD row in the arena's reserved top band.
const ROW_Y := 26.0
const ROW_COLUMNS := [36.0, 210.0, 380.0, 540.0, 730.0]

var time_label: Label
var score_label: Label
var lives_label: Label
var length_label: Label
var speed_label: Label
var title_label: Label
var hint_label: Label
var pause_label: Label


func _make_label(position: Vector2, size: int, color: Color) -> Label:
	var label = Label.new()
	label.position = position
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label


func _make_centered(size: int, color: Color, y: float) -> Label:
	var viewport = get_viewport().get_visible_rect().size
	var label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(viewport.x, size * 2.0)
	label.position = Vector2(0, y)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label


func _ready() -> void:
	time_label = _make_label(Vector2(ROW_COLUMNS[0], ROW_Y), LABEL_SIZE, TEXT_COLOR)
	score_label = _make_label(Vector2(ROW_COLUMNS[1], ROW_Y), LABEL_SIZE, ACCENT_COLOR)
	lives_label = _make_label(Vector2(ROW_COLUMNS[2], ROW_Y), LABEL_SIZE, DANGER_COLOR)
	length_label = _make_label(Vector2(ROW_COLUMNS[3], ROW_Y), LABEL_SIZE, TEXT_COLOR)
	speed_label = _make_label(Vector2(ROW_COLUMNS[4], ROW_Y), LABEL_SIZE, ACCENT_COLOR)

	var middle = get_viewport().get_visible_rect().size.y / 2.0
	title_label = _make_centered(TITLE_SIZE, ACCENT_COLOR, middle - 110)
	hint_label = _make_centered(HINT_SIZE, TEXT_COLOR, middle - 40)
	pause_label = _make_centered(TITLE_SIZE, TEXT_COLOR, middle - 40)
	pause_label.text = "PAUSED"

	title_label.hide()
	hint_label.hide()
	pause_label.hide()


func update_hud(time_text: String, score: int, lives: int, length: int, speed_ratio: float) -> void:
	time_label.text = time_text
	score_label.text = "Score  %d" % score
	lives_label.text = "Lives  %d" % lives
	length_label.text = "Length  %d" % length
	speed_label.text = "Speed  %d%%" % roundi(speed_ratio * 100.0)
	# The readout slides toward red as the snake fattens and drags.
	speed_label.add_theme_color_override(
		"font_color", ACCENT_COLOR.lerp(DANGER_COLOR, clampf(1.0 - speed_ratio, 0.0, 1.0))
	)


func show_title(title: String, hint: String) -> void:
	title_label.text = title
	hint_label.text = hint
	title_label.show()
	hint_label.show()


func hide_overlay() -> void:
	title_label.hide()
	hint_label.hide()


func set_paused(paused: bool) -> void:
	pause_label.visible = paused
