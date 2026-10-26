class_name Style
## Shared look: neo-noir Tokyo palette and pixel fonts.

const VOID := Color("07050f")
const INK := Color("100d24")
const PANEL := Color("0c0a1c")
const CYAN := Color("19f0ff")
const MAGENTA := Color("ff2a8a")
const AMBER := Color("ffb43a")
const VIOLET := Color("7a3cff")
const MINT := Color("3dffa0")
const DIM := Color("8a86b8")
const TEXT := Color("e8e6ff")

static var _pixel: Font
static var _kanji: Font


## Latin pixel font (8px native) with the kanji font as fallback.
static func pixel() -> Font:
	if _pixel == null:
		var f: FontFile = load("res://assets/fonts/PressStart2P-Regular.ttf")
		f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		f.hinting = TextServer.HINTING_NONE
		f.fallbacks = [kanji()]
		_pixel = f
	return _pixel


## 16px pixel font with Japanese glyphs.
static func kanji() -> Font:
	if _kanji == null:
		var f: FontFile = load("res://assets/fonts/DotGothic16-Regular.ttf")
		f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		f.hinting = TextServer.HINTING_NONE
		_kanji = f
	return _kanji


static func box(fill: Color, border: Color, width := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(width)
	s.anti_aliasing = false
	s.content_margin_left = 3
	s.content_margin_right = 3
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	return s


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = pixel()
	t.default_font_size = 8
	t.set_stylebox("normal", "Button", box(PANEL, VIOLET))
	t.set_stylebox("hover", "Button", box(Color("2a0a3a"), MAGENTA))
	t.set_stylebox("pressed", "Button", box(Color("14041f"), CYAN))
	t.set_stylebox("disabled", "Button", box(Color("0a0a12"), Color("2a2a3c")))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", CYAN)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", AMBER)
	t.set_color("font_disabled_color", "Button", Color("4a4a66"))
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("normal", "LineEdit", box(Color("04030c"), VIOLET))
	t.set_stylebox("focus", "LineEdit", box(Color("04030c"), CYAN))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", MAGENTA)
	return t
