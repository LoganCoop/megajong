class_name TileView
extends Control
## A neo-noir mahjong tile: dark lacquer with neon glyphs, drawn procedurally.

signal clicked(view: TileView)

const W := 36
const H := 48
const SUIT_COLORS := [Color("19f0ff"), Color("3dffa0"), Color("ff3d8a")]
const NUMERALS := ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
const FACE := Color("17142e")
const GOLD_FACE := Color("3a2a0a")
const THIEF_FACE := Color("2a0f3a")
const SIDE := Color("2c2a5c")
const EDGE := Color("04030a")

var tile: int = 11
var face_down := false:
	set(v):
		face_down = v
		queue_redraw()
var selected := false
var lift := 0.0:
	set(v):
		lift = v
		queue_redraw()
var flash := 0.0:
	set(v):
		flash = v
		queue_redraw()
var hovered := false:
	set(v):
		hovered = v
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(W, H)
	size = Vector2(W, H)
	pivot_offset = Vector2(W, H) / 2.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func() -> void: hovered = true)
	mouse_exited.connect(func() -> void: hovered = false)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)


func set_selected(value: bool) -> void:
	selected = value
	var tw := create_tween()
	tw.tween_property(self, "lift", -9.0 if value else 0.0, 0.08)


func _draw() -> void:
	var o := Vector2(0, lift + (-2.0 if hovered and not selected else 0.0))
	draw_rect(Rect2(Vector2(2, 4), Vector2(W, H)), Color(0, 0, 0, 0.45))
	draw_rect(Rect2(o, Vector2(W, H)), EDGE)
	if face_down:
		_draw_back(o)
		return

	var power := Meld.power_of(tile)
	var suit := Meld.suit_of(tile)
	var rank := Meld.rank_of(tile)
	var accent: Color = SUIT_COLORS[suit]
	var face := FACE
	if power == Meld.GOLD:
		face = GOLD_FACE
		accent = Style.AMBER
	elif power == Meld.THIEF:
		face = THIEF_FACE
	elif power == Meld.WILD:
		accent = Style.MAGENTA

	draw_rect(Rect2(o + Vector2(1, 1), Vector2(W - 2, H - 2)), SIDE)
	draw_rect(Rect2(o + Vector2(1, 1), Vector2(W - 2, H - 5)), face.lerp(Color.WHITE, flash))
	# Neon inner frame in the tile's accent color.
	draw_rect(Rect2(o + Vector2(2, 2), Vector2(W - 4, H - 7)), accent.darkened(0.45), false, 1.0)
	if selected:
		draw_rect(Rect2(o - Vector2(1, 1), Vector2(W + 2, H + 2)), Style.AMBER, false, 1.0)

	if power == Meld.WILD:
		_draw_wild(o)
		return
	if power == Meld.GOLD:
		_draw_badge(o, "金", Color("b8860b"))
	elif power == Meld.THIEF:
		_draw_badge(o, "盗", Color("8a1fb8"))

	var col: Color = accent if power == Meld.GOLD else SUIT_COLORS[suit]
	var area := Rect2(o + Vector2(5, 5), Vector2(W - 10, H - 15))
	match suit:
		0:
			_draw_grid(area, rank, func(p: Vector2, big: bool) -> void:
				var r := 6.0 if big else 3.0
				draw_circle(p, r, col.darkened(0.35))
				draw_circle(p, r - 1.0, col)
				draw_circle(p, maxf(r - 2.5, 1.0), face)
			)
		1:
			_draw_grid(area, rank, func(p: Vector2, big: bool) -> void:
				var h := 14.0 if big else 8.0
				draw_rect(Rect2(p - Vector2(1.5, h / 2.0), Vector2(3, h)), col)
				draw_rect(Rect2(p - Vector2(1.5, h / 2.0), Vector2(1, h)), col.lightened(0.5))
				draw_rect(Rect2(p + Vector2(-2, -1), Vector2(4, 1)), face)
			)
		2:
			var f := Style.pixel()
			draw_string(f, o + Vector2(0, 25), str(rank), HORIZONTAL_ALIGNMENT_CENTER, W, 16, col)
			draw_string(f, o + Vector2(0, 38), "CH", HORIZONTAL_ALIGNMENT_CENTER, W, 8, col.darkened(0.25))


func _draw_back(o: Vector2) -> void:
	draw_rect(Rect2(o + Vector2(1, 1), Vector2(W - 2, H - 2)), Color("120a2a"))
	draw_rect(Rect2(o + Vector2(3, 3), Vector2(W - 6, H - 6)), Style.MAGENTA.darkened(0.4), false, 1.0)
	for i in 4:
		draw_rect(Rect2(o + Vector2(6, 8 + i * 9), Vector2(W - 12, 1)), Style.VIOLET.darkened(0.2))
	draw_string(Style.kanji(), o + Vector2(0, 29), "麻", HORIZONTAL_ALIGNMENT_CENTER, W, 16, Style.CYAN)


func _draw_wild(o: Vector2) -> void:
	var colors := [Style.MAGENTA, Style.AMBER, Style.MINT, Style.CYAN]
	for i in colors.size():
		draw_rect(Rect2(o + Vector2(4 + i * 7, 4), Vector2(7, H - 13)), (colors[i] as Color).darkened(0.55))
	draw_string(Style.kanji(), o + Vector2(0, 31), "龍", HORIZONTAL_ALIGNMENT_CENTER, W, 16, Color.WHITE)


func _draw_badge(o: Vector2, glyph: String, color: Color) -> void:
	draw_rect(Rect2(o + Vector2(W - 13, 2), Vector2(11, 11)), color)
	draw_string(Style.kanji(), o + Vector2(W - 13, 12), glyph, HORIZONTAL_ALIGNMENT_CENTER, 11, 10, Color.WHITE)


func _draw_grid(area: Rect2, n: int, painter: Callable) -> void:
	if n == 1:
		painter.call(area.get_center(), true)
		return
	var cols := 1 if n <= 3 else (2 if n <= 6 else 3)
	var rows := ceili(float(n) / cols)
	for i in n:
		var row := i / cols
		var in_row := mini(cols, n - row * cols)
		var k := i - row * cols
		var p := Vector2(
			area.position.x + area.size.x * (k + 1) / (in_row + 1),
			area.position.y + area.size.y * (row + 1) / (rows + 1))
		painter.call(p, false)
