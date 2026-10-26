extends Control
## Megajong table UI. Seat 0 is the local human; everyone else is a bot for now.
## All rules live in TableGame; this script only animates and forwards input as actions.

const SLOT_W := 41
const HAND_Y := 190.0
const CENTER_Y := 64.0
const MAX_SELECT := 5
const GOLD := Style.AMBER
const CHIP_BLUE := Style.CYAN
const MULT_RED := Style.MAGENTA
const BOTS := [["KAI", "rusher"], ["MEI", "collector"], ["ROK", "schemer"]]

const PORT := 7777
const BOT_PERSONALITIES := ["rusher", "collector", "schemer"]

signal ui_acted
signal continue_pressed
signal picked(id: String)
signal remote_acted

var game: TableGame
var mode := "solo" # solo | local | host | client
var view_seat := 0
var hotseat := false
var seat_peer: Dictionary = {} # host only: seat index -> peer id
var lobby_peers: Array[Dictionary] = [] # host only: {id, character}
var host_character := ""
var net_queue: Array[Dictionary] = []
var pumping := false
var last_err := ""
var net_busy := false
var left := false
var menu_btn: Button
var views: Array[TileView] = []
var center_views: Array[TileView] = []
var shown_totals: Array[float] = []
var panels: Array[Dictionary] = []
var sort_by_rank := false
var busy := false
var animating := false
var human_turn := false

var world: Control
var bg: ColorRect
var crt: ColorRect
var overlay: Control
var title_label: Label
var hint_label: Label
var wall_label: Label
var discard_label: Label
var meld_label: Label
var chips_label: Label
var mult_label: Label
var total_label: Label
var message_label: Label
var char_label: Label
var round_label: Label
var wall_view: TileView
var discard_view: TileView
var meld_btn: Button
var discard_btn: Button
var sort_btn: Button
var hint_btn: Button
var power_btn: Button
var hint_index := 0
var rule_choice := "mega"
var sfx: Sfx
var score_nodes: Array[CanvasItem] = []
var signs: Array[Label] = []


func _ready() -> void:
	theme = Style.make_theme()
	sfx = Sfx.new()
	add_child(sfx)
	_build_ui()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_show_main_menu()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode == KEY_M:
		sfx.toggle_mute()
		return
	if event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE and not left:
		_leave_to_menu()


func _process(_delta: float) -> void:
	if is_instance_valid(title_label):
		# Neon sign: steady magenta with the odd cyan glitch flicker.
		var t := Time.get_ticks_msec()
		var glitch := (t / 90) % 37 == 0 or (t / 70) % 53 == 0
		title_label.modulate = Style.CYAN if glitch else Style.MAGENTA.lightened(0.25)
	for s in signs:
		var n := (Time.get_ticks_msec() / 110 + int(s.position.y)) % 41
		s.modulate.a = 0.35 if n == 0 else 1.0


# ---------------------------------------------------------------- UI building


func _label(text: String, font_size: int, color: Color, pos: Vector2, width := 0.0, align := HORIZONTAL_ALIGNMENT_LEFT, parent: Control = null) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	if width > 0.0:
		l.size.x = width
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent else world).add_child(l)
	return l


func _rect(pos: Vector2, rect_size: Vector2, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = pos
	r.size = rect_size
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(r)
	return r


func _button(text: String, rect: Rect2, callback: Callable, parent: Control = null) -> Button:
	var b := Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	b.pressed.connect(callback)
	b.pressed.connect(func() -> void: sfx.play("ui"))
	(parent if parent else world).add_child(b)
	return b


func _build_ui() -> void:
	world = Control.new()
	world.set_anchors_preset(Control.PRESET_FULL_RECT)
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(world)

	bg = ColorRect.new()
	bg.position = Vector2(-8, -8)
	bg.size = Vector2(496, 286)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/background.gdshader")
	bg.material = mat
	world.add_child(bg)

	for i in 4:
		var x := 2 + i * 119
		var p := Panel.new()
		p.position = Vector2(x, 3)
		p.size = Vector2(117, 44)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		world.add_child(p)
		var rows := {}
		for k in 4:
			var l := _label("", 8, Style.TEXT, Vector2(x + 3, 5 + k * 10), 112)
			l.clip_text = true
			rows["l%d" % (k + 1)] = l
		rows["l2"].add_theme_color_override("font_color", Style.CYAN)
		rows["l3"].add_theme_color_override("font_color", Style.DIM)
		rows["panel"] = p
		panels.append(rows)

	hint_label = _label("", 8, Style.TEXT, Vector2(0, 50), 480, HORIZONTAL_ALIGNMENT_CENTER)

	# Vertical neon signs flanking the table.
	var sign_defs := [["麻\n雀", Vector2(10, 78), Style.MAGENTA], ["電\n脳", Vector2(454, 78), Style.CYAN]]
	for d in sign_defs:
		var s := _label(d[0], 16, d[2], d[1], 16, HORIZONTAL_ALIGNMENT_CENTER)
		s.add_theme_font_override("font", Style.kanji())
		s.add_theme_constant_override("line_spacing", 0)
		signs.append(s)

	wall_view = TileView.new()
	wall_view.face_down = true
	wall_view.position = Vector2(48, CENTER_Y)
	wall_view.clicked.connect(func(_v: TileView) -> void: _human_action({"type": "draw", "from": "wall"}))
	world.add_child(wall_view)
	discard_view = TileView.new()
	discard_view.position = Vector2(396, CENTER_Y)
	discard_view.clicked.connect(func(_v: TileView) -> void: _human_action({"type": "draw", "from": "discard"}))
	world.add_child(discard_view)
	wall_label = _label("", 8, Style.DIM, Vector2(26, 114), 80, HORIZONTAL_ALIGNMENT_CENTER)
	discard_label = _label("DISCARD", 8, Style.DIM, Vector2(374, 114), 80, HORIZONTAL_ALIGNMENT_CENTER)

	meld_label = _label("", 16, Color.WHITE, Vector2(0, 118), 480, HORIZONTAL_ALIGNMENT_CENTER)
	score_nodes = [
		_rect(Vector2(139, 160), Vector2(92, 1), CHIP_BLUE),
		_rect(Vector2(139, 154), Vector2(1, 7), CHIP_BLUE),
		_rect(Vector2(249, 160), Vector2(92, 1), MULT_RED),
		_rect(Vector2(340, 154), Vector2(1, 7), MULT_RED),
		_label("DATA", 8, CHIP_BLUE.darkened(0.2), Vector2(139, 135), 92, HORIZONTAL_ALIGNMENT_RIGHT),
		_label("SURGE", 8, MULT_RED.darkened(0.1), Vector2(249, 135), 92, HORIZONTAL_ALIGNMENT_LEFT),
	]
	chips_label = _label("0", 16, CHIP_BLUE.lightened(0.5), Vector2(140, 143), 90, HORIZONTAL_ALIGNMENT_RIGHT)
	score_nodes.append(_label("//", 16, GOLD, Vector2(230, 143), 20, HORIZONTAL_ALIGNMENT_CENTER))
	mult_label = _label("0", 16, MULT_RED.lightened(0.5), Vector2(250, 143), 90, HORIZONTAL_ALIGNMENT_LEFT)
	total_label = _label("", 16, GOLD, Vector2(0, 163), 480, HORIZONTAL_ALIGNMENT_CENTER)
	message_label = _label("", 16, Color.WHITE, Vector2(0, 96), 480, HORIZONTAL_ALIGNMENT_CENTER)

	char_label = _label("", 8, Style.DIM, Vector2(4, 252), 94)
	char_label.clip_text = true
	round_label = _label("", 8, GOLD, Vector2(374, 130), 80, HORIZONTAL_ALIGNMENT_CENTER)
	hint_btn = _button("HINT", Rect2(100, 246, 42, 18), _on_hint)
	meld_btn = _button("MELD", Rect2(146, 246, 60, 18), _on_meld)
	discard_btn = _button("DISCARD", Rect2(210, 246, 68, 18), _on_discard)
	sort_btn = _button("BY SUIT", Rect2(282, 246, 68, 18), _on_sort)
	power_btn = _button("PWR x0", Rect2(354, 246, 54, 18), _on_power)
	menu_btn = _button("MENU", Rect2(412, 246, 44, 18), _leave_to_menu)

	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	crt = ColorRect.new()
	crt.set_anchors_preset(Control.PRESET_FULL_RECT)
	crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var crt_mat := ShaderMaterial.new()
	crt_mat.shader = load("res://shaders/crt.gdshader")
	crt.material = crt_mat
	layer.add_child(crt)

	_set_table_visible(false)


func _set_table_visible(on: bool) -> void:
	for d in panels:
		for k in d:
			d[k].visible = on
	for c: CanvasItem in score_nodes:
		c.visible = on
	for s in signs:
		s.visible = on
	for c: CanvasItem in [hint_label, wall_view, discard_view, wall_label, discard_label, meld_label,
			chips_label, mult_label, total_label, char_label, round_label, meld_btn, discard_btn, sort_btn, hint_btn, power_btn, menu_btn]:
		c.visible = on


func _panel_box(active: bool, accent: Color) -> StyleBoxFlat:
	var s := Style.box(Color(0.03, 0.02, 0.09, 0.9), accent if active else accent.darkened(0.6))
	if active:
		s.set_border_width_all(2)
	return s


# ---------------------------------------------------------------- Menus

func _open_menu_screen(subtitle: String) -> void:
	_set_table_visible(false)
	_clear_hand_views()
	_clear_center()
	_open_overlay("")
	title_label = _label("MEGAJONG", 16, Color.WHITE, Vector2(0, 12), 480, HORIZONTAL_ALIGNMENT_CENTER, overlay)
	if subtitle != "":
		_label("- %s -" % subtitle, 8, GOLD, Vector2(0, 62), 480, HORIZONTAL_ALIGNMENT_CENTER, overlay)


func _close_overlay() -> void:
	if is_instance_valid(overlay):
		overlay.get_parent().queue_free()


func _show_main_menu() -> void:
	_open_menu_screen("MAIN MENU")
	var entries := [
		["SOLO VS BOTS", _menu_solo],
		["LOCAL PASS & PLAY", _menu_local],
		["HOST ONLINE GAME", _menu_host],
		["JOIN ONLINE GAME", _menu_join],
		["HOW TO PLAY", _show_rules],
		["QUIT", get_tree().quit],
	]
	for i in entries.size():
		_button(entries[i][0], Rect2(150, 78 + i * 24, 180, 20), entries[i][1], overlay)


func _show_rules() -> void:
	_close_overlay()
	_open_menu_screen("HOW TO PLAY")
	_label("DRAW FROM THE WALL OR THE DISCARD\nPILE, LAY MELDS OF 3-5 TILES, THEN\nDISCARD ONE TO END YOUR TURN.\n\nEVERY MELD SCORES DATA // SURGE.\nEACH EXTRA MELD IN A TURN ADDS +1 SURGE.\nEMPTY YOUR HAND TO GO OUT FOR +%d.\nBEST TOTAL AFTER %d ROUNDS WINS.\n\nMEGA/MARATHON: MELDS REFILL YOUR HAND,\nMELDS PER TURN ARE CAPPED, AND ONLY A\nMELD CAN GO OUT FOR THE BONUS.\n\n龍 WILD   金 GOLD +%d DATA   盗 THIEF -%d PTS" % [TableGame.OUT_BONUS, TableGame.ROUNDS, TableGame.GOLD_CHIPS, TableGame.THIEF_STEAL],
		8, Style.TEXT, Vector2(0, 62), 480, HORIZONTAL_ALIGNMENT_CENTER, overlay).add_theme_constant_override("line_spacing", 2)
	_button("BACK", Rect2(190, 248, 100, 18), func() -> void:
		_close_overlay()
		_show_main_menu(), overlay)


## Shows the character grid and returns the chosen id, or "" if the player went back.
func _pick_character(prompt: String, taken: Array) -> String:
	_close_overlay()
	_open_menu_screen(prompt)
	for i in Characters.ALL.size():
		var c: Dictionary = Characters.ALL[i]
		var b := _button("%s\n\n%s\n\n%s" % [c.kana, c.name, c.desc], Rect2(7 + i * 118, 84, 108, 84), func() -> void: picked.emit(c.id), overlay)
		b.disabled = taken.has(c.id)
		b.add_theme_color_override("font_color", c.color)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_stylebox_override("normal", Style.box(Style.PANEL, (c.color as Color).darkened(0.5)))
		b.add_theme_stylebox_override("hover", Style.box(Color("1a0a2a"), c.color))
	_button("BACK", Rect2(190, 190, 100, 20), func() -> void: picked.emit(""), overlay)
	var id: String = await picked
	_close_overlay()
	return id


func _free_characters(taken: Array) -> Array[String]:
	var out: Array[String] = []
	for c: Dictionary in Characters.ALL:
		if not taken.has(c.id):
			out.append(c.id)
	out.shuffle()
	return out


## Builds a seat list: humans first, then bots in any remaining seats.
func _make_setup(human_chars: Array, human_names: Array) -> Dictionary:
	var seats: Array[Dictionary] = []
	for i in human_chars.size():
		seats.append({"name": human_names[i], "character": human_chars[i], "bot": ""})
	var free := _free_characters(human_chars)
	var b := 0
	while seats.size() < 4:
		seats.append({"name": BOTS[b][0], "character": free[b], "bot": BOTS[b][1]})
		b += 1
	return {"seats": seats, "rules": rule_choice}


## Lets the player pick a game mode; returns its id, or "" if they went back.
func _pick_rules(prompt: String) -> String:
	_close_overlay()
	_open_menu_screen(prompt)
	for i in TableGame.RULE_IDS.size():
		var id: String = TableGame.RULE_IDS[i]
		var r: Dictionary = TableGame.RULESETS[id]
		_button("%s\n%s" % [r.name, r.desc], Rect2(90, 84 + i * 36, 300, 30), func() -> void: picked.emit(id), overlay)
	_button("BACK", Rect2(190, 84 + TableGame.RULE_IDS.size() * 36, 100, 20), func() -> void: picked.emit(""), overlay)
	var res: String = await picked
	_close_overlay()
	return res


func _menu_solo() -> void:
	var rid := await _pick_rules("CHOOSE GAME MODE")
	if rid == "":
		_show_main_menu()
		return
	rule_choice = rid
	var id := await _pick_character("CHOOSE YOUR CHARACTER", [])
	if id == "":
		_show_main_menu()
		return
	mode = "solo"
	_close_overlay()
	_begin_game(_make_setup([id], ["YOU"]), 0)
	_run_game()


func _menu_local() -> void:
	var rid := await _pick_rules("CHOOSE GAME MODE")
	if rid == "":
		_show_main_menu()
		return
	rule_choice = rid
	_close_overlay()
	_open_menu_screen("HUMAN PLAYERS")
	var count := 0
	var counts := [2, 3, 4]
	for i in counts.size():
		_button("%d PLAYERS" % counts[i], Rect2(150, 90 + i * 26, 180, 20), func() -> void: picked.emit(str(counts[i])), overlay)
	_button("BACK", Rect2(150, 90 + 3 * 26, 180, 20), func() -> void: picked.emit(""), overlay)
	var res: String = await picked
	if res == "":
		_show_main_menu()
		return
	count = int(res)
	var chars: Array = []
	var names: Array = []
	for p in count:
		var id := await _pick_character("PLAYER %d: CHOOSE" % (p + 1), chars)
		if id == "":
			_show_main_menu()
			return
		chars.append(id)
		names.append("P%d" % (p + 1))
	mode = "local"
	hotseat = true
	_close_overlay()
	_begin_game(_make_setup(chars, names), 0)
	_run_game()


# ---------------------------------------------------------------- Online lobby

func _menu_host() -> void:
	var rid := await _pick_rules("HOST: CHOOSE GAME MODE")
	if rid == "":
		_show_main_menu()
		return
	rule_choice = rid
	var id := await _pick_character("HOST: CHOOSE YOUR CHARACTER", [])
	if id == "":
		_show_main_menu()
		return
	host_character = id
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT, 3) != OK:
		_show_notice("COULD NOT OPEN PORT %d" % PORT, _show_main_menu)
		return
	multiplayer.multiplayer_peer = peer
	mode = "host"
	lobby_peers.clear()
	_show_lobby()


func _local_addresses() -> String:
	var out: Array[String] = []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return "  ".join(out.slice(0, 2)) if not out.is_empty() else "127.0.0.1"


func _lobby_lines() -> Array:
	var lines: Array = [["1. P1 - %s (HOST)" % Characters.get_by_id(host_character).name, host_character]]
	for i in lobby_peers.size():
		var cid: String = lobby_peers[i].character
		lines.append(["%d. P%d - %s" % [i + 2, i + 2, Characters.get_by_id(cid).name], cid])
	return lines


func _show_lobby() -> void:
	_close_overlay()
	_open_menu_screen("HOSTING ON PORT %d" % PORT)
	_label("FRIENDS JOIN WITH:\n%s" % _local_addresses(), 8, Style.CYAN, Vector2(0, 80), 480, HORIZONTAL_ALIGNMENT_CENTER, overlay)
	var lines := _lobby_lines()
	for i in lines.size():
		_label(lines[i][0], 8, Characters.get_by_id(lines[i][1]).color, Vector2(0, 108 + i * 12), 480, HORIZONTAL_ALIGNMENT_CENTER, overlay)
	_label("EMPTY SEATS ARE FILLED WITH BOTS", 8, Style.DIM, Vector2(0, 168), 480, HORIZONTAL_ALIGNMENT_CENTER, overlay)
	var start := _button("START GAME", Rect2(120, 190, 110, 20), _host_start, overlay)
	start.disabled = lobby_peers.is_empty()
	_button("BACK", Rect2(250, 190, 110, 20), _leave_to_menu, overlay)
	_broadcast_lobby()


func _broadcast_lobby() -> void:
	var lines: Array = []
	for l in _lobby_lines():
		lines.append(l)
	for p in lobby_peers:
		_rpc_lobby.rpc_id(p.id, lines)


func _menu_join() -> void:
	var id := await _pick_character("JOIN: CHOOSE YOUR CHARACTER", [])
	if id == "":
		_show_main_menu()
		return
	host_character = id
	_show_join_form("")


func _show_join_form(note: String) -> void:
	_close_overlay()
	_open_menu_screen("JOIN A GAME")
	_label("HOST ADDRESS (IP OR IP:PORT)", 8, Style.DIM, Vector2(0, 96), 480, HORIZONTAL_ALIGNMENT_CENTER, overlay)
	var edit := LineEdit.new()
	edit.text = "127.0.0.1"
	edit.position = Vector2(140, 110)
	edit.size = Vector2(200, 20)
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.add_child(edit)
	if note != "":
		_label(note, 8, Style.MAGENTA, Vector2(0, 140), 480, HORIZONTAL_ALIGNMENT_CENTER, overlay)
	_button("CONNECT", Rect2(120, 170, 110, 20), func() -> void: _connect_to(edit.text.strip_edges()), overlay)
	_button("BACK", Rect2(250, 170, 110, 20), _show_main_menu, overlay)


func _connect_to(address: String) -> void:
	var port := PORT
	var host := address
	if ":" in address:
		host = address.get_slice(":", 0)
		port = int(address.get_slice(":", 1))
	var peer := ENetMultiplayerPeer.new()
	if host == "" or peer.create_client(host, port) != OK:
		_show_join_form("INVALID ADDRESS")
		return
	multiplayer.multiplayer_peer = peer
	mode = "client"
	_close_overlay()
	_open_menu_screen("CONNECTING...")
	_button("CANCEL", Rect2(190, 150, 100, 20), _leave_to_menu, overlay)


func _show_notice(text: String, then: Callable) -> void:
	_close_overlay()
	_open_menu_screen("")
	_label(text, 8, Style.MAGENTA, Vector2(0, 110), 480, HORIZONTAL_ALIGNMENT_CENTER, overlay)
	_button("OK", Rect2(190, 150, 100, 20), func() -> void: then.call(), overlay)


func _leave_to_menu() -> void:
	if left:
		return
	left = true
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	get_tree().reload_current_scene.call_deferred()


func _on_peer_connected(_id: int) -> void:
	pass


func _on_peer_disconnected(id: int) -> void:
	if mode != "host":
		return
	for i in lobby_peers.size():
		if lobby_peers[i].id == id:
			lobby_peers.remove_at(i)
			_show_lobby()
			return
	for si: int in seat_peer.keys():
		if seat_peer[si] == id:
			seat_peer.erase(si)
			var s := game.seats[si]
			s.is_bot = true
			s.personality = "collector"
			s.name += "*"
			_update_all()
			remote_acted.emit()


func _on_connected_to_server() -> void:
	_rpc_hello.rpc_id(1, host_character)
	_close_overlay()
	_open_menu_screen("CONNECTED - WAITING FOR HOST")
	_button("LEAVE", Rect2(190, 190, 100, 20), _leave_to_menu, overlay)


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	mode = "solo"
	_show_join_form("COULD NOT CONNECT")


func _on_server_disconnected() -> void:
	if left:
		return
	_show_notice("HOST DISCONNECTED", _leave_to_menu)


# ---------------------------------------------------------------- Network messages

@rpc("any_peer", "call_remote", "reliable")
func _rpc_hello(character_id: String) -> void:
	if mode != "host" or game != null:
		return
	var id := multiplayer.get_remote_sender_id()
	var taken: Array = [host_character]
	for p in lobby_peers:
		taken.append(p.character)
	if Characters.get_by_id(character_id).is_empty() or taken.has(character_id):
		character_id = _free_characters(taken)[0]
	lobby_peers.append({"id": id, "character": character_id})
	_show_lobby()


@rpc("authority", "call_remote", "reliable")
func _rpc_lobby(lines: Array) -> void:
	if mode != "client" or game != null:
		return
	_close_overlay()
	_open_menu_screen("WAITING FOR HOST")
	for i in lines.size():
		_label(str(lines[i][0]), 8, Characters.get_by_id(str(lines[i][1])).color, Vector2(0, 90 + i * 12), 480, HORIZONTAL_ALIGNMENT_CENTER, overlay)
	_button("LEAVE", Rect2(190, 190, 100, 20), _leave_to_menu, overlay)


@rpc("authority", "call_remote", "reliable")
func _rpc_start(setup: Dictionary, seat: int) -> void:
	if mode != "client":
		return
	_close_overlay()
	_begin_game(setup, seat)


@rpc("authority", "call_remote", "reliable")
func _rpc_round(snap: Dictionary) -> void:
	net_queue.append({"kind": "round", "snap": snap})
	_client_pump()


@rpc("authority", "call_remote", "reliable")
func _rpc_event(si: int, res: Dictionary, snap: Dictionary) -> void:
	net_queue.append({"kind": "event", "si": si, "res": res, "snap": snap})
	_client_pump()


@rpc("authority", "call_remote", "reliable")
func _rpc_round_end(over: bool, snap: Dictionary) -> void:
	net_queue.append({"kind": "end", "over": over, "snap": snap})
	_client_pump()


@rpc("authority", "call_remote", "reliable")
func _rpc_reject(err: String) -> void:
	busy = false
	sfx.play("error")
	_shake(2.5)
	_show_message(err.to_upper(), MULT_RED)
	_refresh()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_action(action: Dictionary) -> void:
	if mode != "host" or game == null:
		return
	var id := multiplayer.get_remote_sender_id()
	var si := -1
	for k: int in seat_peer.keys():
		if seat_peer[k] == id:
			si = k
	var clean := _sanitize_action(action)
	if si < 0 or clean.is_empty() or net_busy:
		_rpc_reject.rpc_id(id, "Not allowed")
		return
	net_busy = true
	var ok := await _do_action(si, clean)
	net_busy = false
	if ok:
		remote_acted.emit()
	else:
		_rpc_reject.rpc_id(id, last_err)


func _sanitize_action(action: Dictionary) -> Dictionary:
	match str(action.get("type", "")):
		"draw":
			return {"type": "draw", "from": "discard" if str(action.get("from", "")) == "discard" else "wall"}
		"meld":
			var tiles: Array = []
			var raw: Variant = action.get("tiles", [])
			if raw is Array and (raw as Array).size() <= MAX_SELECT:
				for t: Variant in raw:
					if t is int:
						tiles.append(t)
					else:
						return {}
				return {"type": "meld", "tiles": tiles}
		"discard":
			if action.get("tile", null) is int:
				return {"type": "discard", "tile": action.tile}
		"power":
			var id := str(action.get("id", ""))
			var raw_tiles: Variant = action.get("tiles", [])
			if TableGame.POWER_IDS.has(id) and raw_tiles is Array and (raw_tiles as Array).size() <= MAX_SELECT \
					and action.get("target", 0) is int:
				var ptiles: Array = []
				for t: Variant in raw_tiles:
					if not t is int:
						return {}
					ptiles.append(t)
				return {"type": "power", "id": id, "tiles": ptiles, "target": action.get("target", 0)}
	return {}


func _host_start() -> void:
	if lobby_peers.is_empty():
		return
	var chars: Array = [host_character]
	var names: Array = ["P1"]
	for i in lobby_peers.size():
		chars.append(lobby_peers[i].character)
		names.append("P%d" % (i + 2))
	var setup := _make_setup(chars, names)
	_close_overlay()
	seat_peer.clear()
	for i in lobby_peers.size():
		seat_peer[i + 1] = lobby_peers[i].id
	for si: int in seat_peer.keys():
		_rpc_start.rpc_id(seat_peer[si], setup, si)
	var local_setup := setup.duplicate(true)
	local_setup.seats[0].name = "YOU"
	_begin_game(local_setup, 0)
	_run_game()


func _snapshot(for_seat: int) -> Dictionary:
	var seats_a: Array = []
	for i in game.seats.size():
		var s := game.seats[i]
		var hand: Array = s.hand.duplicate() if i == for_seat else s.hand.map(func(_t: int) -> int: return -1)
		seats_a.append({"hand": hand, "total": s.total, "meld_count": s.meld_count, "last": s.last,
			"bot": s.is_bot, "name": s.name, "powerups": s.powerups.duplicate()})
	return {"seats": seats_a, "wall": game.wall.size(), "discard": game.discard.duplicate(),
		"current": game.current, "phase": int(game.phase), "round": game.round_number,
		"turn_melds": game.turn_melds, "surge_next": game.surge_next, "last_kind": game.last_kind, "end_info": game.end_info.duplicate()}


func _load_snapshot(snap: Dictionary) -> void:
	for i in game.seats.size():
		var d: Dictionary = snap.seats[i]
		var s := game.seats[i]
		s.hand.assign(d.hand)
		s.total = d.total
		s.meld_count = d.meld_count
		s.last = d.last
		s.powerups.assign(d.powerups)
		s.is_bot = d.bot
		if i != view_seat:
			s.name = d.name
	game.wall.resize(int(snap.wall))
	game.discard.assign(snap.discard)
	game.current = snap.current
	game.phase = snap.phase
	game.round_number = snap.round
	game.turn_melds = snap.turn_melds
	game.surge_next = snap.surge_next
	game.last_kind = snap.last_kind
	game.end_info = snap.end_info


func _broadcast_event(si: int, res: Dictionary) -> void:
	for seat: int in seat_peer.keys():
		var r := res.duplicate()
		if r.type == "draw" and r.from == "wall" and seat != si:
			r.erase("tile")
		if r.type == "meld" and seat != si:
			r.erase("refill")
		if r.type == "power" and seat != si and seat != int(r.get("target", -1)):
			if r.id == "swap" or r.id == "draw3":
				r.erase("gave")
				r.erase("got")
				r.erase("tiles")
		_rpc_event.rpc_id(seat_peer[seat], si, r, _snapshot(seat))


func _broadcast_round(end_over: Variant) -> void:
	for seat: int in seat_peer.keys():
		if end_over == null:
			_rpc_round.rpc_id(seat_peer[seat], _snapshot(seat))
		else:
			_rpc_round_end.rpc_id(seat_peer[seat], end_over, _snapshot(seat))


func _client_pump() -> void:
	if pumping:
		return
	pumping = true
	while not net_queue.is_empty() and not left:
		var m: Dictionary = net_queue.pop_front()
		_load_snapshot(m.snap)
		match m.kind:
			"round":
				_close_overlay()
				_clear_hand_views()
				_reconcile_hand(true)
				_refresh()
				sfx.play("round")
				_show_message("ROUND %d" % game.round_number, GOLD)
				await get_tree().create_timer(0.9).timeout
			"event":
				await _play(m.si, m.res)
			"end":
				await _sync_scores()
				await _show_round_result(m.over)
		busy = false
		human_turn = game.current == view_seat and game.phase != TableGame.Phase.ENDED
		_refresh()
	pumping = false


func _begin_game(setup: Dictionary, seat: int) -> void:
	left = false
	view_seat = seat
	game = TableGame.new()
	game.set_rules(str(setup.get("rules", "mega")))
	for i in setup.seats.size():
		var d: Dictionary = setup.seats[i]
		var seat_name: String = d.name
		if mode == "client" and i == seat:
			seat_name = "YOU"
		game.add_seat(seat_name, d.character, d.bot)
	shown_totals.assign([0.0, 0.0, 0.0, 0.0])
	_set_table_visible(true)
	char_label.text = "" if hotseat else str(game.seats[view_seat].character.tag)


func _run_game() -> void:
	while true:
		game.start_round()
		_clear_hand_views()
		if not hotseat:
			_reconcile_hand(true)
		_refresh()
		_broadcast_round(null)
		sfx.play("round")
		_show_message("ROUND %d" % game.round_number, GOLD)
		await get_tree().create_timer(0.9).timeout
		while game.phase != TableGame.Phase.ENDED:
			var si := game.current
			if game.seats[si].is_bot:
				await _bot_turn(si)
			elif seat_peer.has(si):
				await _remote_turn(si)
			else:
				await _human_turn(si)
		await _sync_scores()
		var over := game.is_over()
		_broadcast_round(over)
		await _show_round_result(over)
		if over:
			break
	_leave_to_menu()


func _human_turn(si: int) -> void:
	if hotseat:
		await _pass_screen(si)
		view_seat = si
		char_label.text = str(game.seats[si].character.tag)
		_reconcile_hand(true)
	human_turn = true
	_refresh()
	while game.current == si and game.phase != TableGame.Phase.ENDED:
		await ui_acted
	human_turn = false
	if hotseat:
		_clear_hand_views()
	_refresh()


func _pass_screen(si: int) -> void:
	_open_overlay("")
	var seat := game.seats[si]
	_label("PASS THE DEVICE TO", 8, Style.DIM, Vector2(0, 90), 480, HORIZONTAL_ALIGNMENT_CENTER, overlay)
	_label("%s - %s" % [seat.name, seat.character.name], 16, seat.character.color, Vector2(0, 108), 480, HORIZONTAL_ALIGNMENT_CENTER, overlay)
	_button("I AM READY", Rect2(170, 150, 140, 20), func() -> void: continue_pressed.emit(), overlay)
	await continue_pressed
	_close_overlay()


func _remote_turn(si: int) -> void:
	_refresh()
	while game.current == si and game.phase != TableGame.Phase.ENDED and not game.seats[si].is_bot:
		await remote_acted
	_refresh()


func _bot_turn(si: int) -> void:
	_refresh()
	await get_tree().create_timer(0.6).timeout
	while game.current == si and game.phase != TableGame.Phase.ENDED:
		var action := Bot.decide(game, si)
		if not await _do_action(si, action):
			push_warning("Bot action rejected: %s" % [action])
			var fallback := {"type": "draw", "from": "wall"}
			if game.phase == TableGame.Phase.ACT:
				fallback = {"type": "discard", "tile": game.seats[si].hand[0]}
			await _do_action(si, fallback)
		await get_tree().create_timer(0.4).timeout


func _show_round_result(over: bool) -> void:
	_open_overlay("FINAL RESULT" if over else "ROUND %d COMPLETE" % game.round_number)
	var lines: Array[String] = []
	if game.end_info.reason == "out":
		var pts := int(game.end_info.get("bonus", TableGame.OUT_BONUS))
		lines.append("%s WENT OUT!%s\n" % [game.seats[game.end_info.winner].name, "  +%d" % pts if pts > 0 else ""])
	else:
		lines.append("WALL EMPTY - NOBODY WENT OUT\n")
	var rank := 1
	for i in game.standings():
		lines.append("%d. %-5s %5d" % [rank, game.seats[i].name, game.seats[i].total])
		rank += 1
	var info := _label("\n".join(lines), 8, Color.WHITE, Vector2(0, 84), 480, HORIZONTAL_ALIGNMENT_CENTER, overlay)
	info.add_theme_font_size_override("font_size", 8)
	if mode == "client":
		# The host advances the game; the next round message closes this overlay.
		if over:
			_button("MENU", Rect2(190, 190, 100, 20), _leave_to_menu, overlay)
		else:
			_label("WAITING FOR HOST...", 8, Style.DIM, Vector2(0, 196), 480, HORIZONTAL_ALIGNMENT_CENTER, overlay)
		return
	_button("MENU" if over else "NEXT ROUND", Rect2(190, 190, 100, 20), func() -> void: continue_pressed.emit(), overlay)
	await continue_pressed
	_close_overlay()


# ---------------------------------------------------------------- Hand views

func _add_view(tile: int) -> TileView:
	var v := TileView.new()
	v.tile = tile
	v.position = Vector2(240, -60)
	v.clicked.connect(_on_tile_clicked)
	world.add_child(v)
	views.append(v)
	return v


func _clear_hand_views() -> void:
	for v in views:
		v.queue_free()
	views.clear()


func _sort_key(a: TileView, b: TileView) -> bool:
	var ta := a.tile % 100
	var tb := b.tile % 100
	if sort_by_rank:
		var ra := Meld.rank_of(ta)
		var rb := Meld.rank_of(tb)
		return ra < rb or (ra == rb and ta < tb)
	return ta < tb or (ta == tb and a.tile < b.tile)


func _layout_hand(staggered := false) -> void:
	views.sort_custom(_sort_key)
	var slot := minf(float(SLOT_W), 468.0 / maxi(views.size(), 1))
	var start_x := (480.0 - (views.size() * slot - (slot - TileView.W))) / 2.0
	for i in views.size():
		views[i].z_index = i
		var tw := create_tween()
		if staggered:
			tw.tween_interval(i * 0.05)
		tw.tween_property(views[i], "position", Vector2(start_x + i * slot, HAND_Y), 0.28) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Makes the tile views match the human's hand: removes spent tiles, adds new ones.
func _reconcile_hand(staggered := false) -> void:
	var remaining: Array[int] = game.seats[view_seat].hand.duplicate()
	var keep: Array[TileView] = []
	for v in views:
		var i := remaining.find(v.tile)
		if i >= 0:
			remaining.remove_at(i)
			keep.append(v)
		else:
			v.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var tw := create_tween()
			tw.tween_property(v, "scale", Vector2.ZERO, 0.15)
			tw.tween_callback(v.queue_free)
	views = keep
	for t in remaining:
		_add_view(t)
	_layout_hand(staggered)


func _selected_tiles() -> Array:
	var out: Array = []
	for v in views:
		if v.selected:
			out.append(v.tile)
	return out


# ---------------------------------------------------------------- HUD

func _refresh() -> void:
	_update_all()
	_update_buttons()
	_update_hint_marks()
	_update_preview()


func _update_all() -> void:
	if game == null:
		return
	for i in game.seats.size():
		var s := game.seats[i]
		var d: Dictionary = panels[i]
		d.l1.text = "%s - %s" % [s.name, s.character.name]
		d.l1.add_theme_color_override("font_color", s.character.color)
		d.l2.text = "SCORE %d" % int(shown_totals[i])
		d.l3.text = "H%d M%d PWR %d" % [s.hand.size(), s.meld_count, s.powerups.size()]
		d.l4.text = s.last
		d.panel.add_theme_stylebox_override("panel", _panel_box(i == game.current and game.phase != TableGame.Phase.ENDED, s.character.color))
	round_label.text = "ROUND %d/%d" % [game.round_number, TableGame.ROUNDS]
	wall_label.text = "WALL %d" % game.wall.size()
	discard_view.visible = not game.discard.is_empty()
	if not game.discard.is_empty():
		discard_view.tile = game.discard.back()
		discard_view.queue_redraw()
	if game.phase == TableGame.Phase.ENDED:
		hint_label.text = ""
	elif game.current == view_seat:
		if game.phase == TableGame.Phase.DRAW:
			hint_label.text = "YOUR TURN - CLICK THE WALL OR DISCARD TO DRAW"
			if not game.discard.is_empty():
				var with_top: Array = game.seats[view_seat].hand.duplicate()
				with_top.append(game.discard.back())
				if not Bot.best_meld(with_top, game.discard.back()).is_empty():
					hint_label.text = "THE DISCARD COMPLETES A MELD FOR YOU!"
		else:
			var n := game.hints(view_seat).size()
			hint_label.text = ("%d MELD%s IN HAND - GREEN TILES, OR PRESS HINT" % [n, "" if n == 1 else "S"]) if n > 0 \
				else "NO MELDS YET - DISCARD 1 TILE TO END YOUR TURN"
	else:
		hint_label.text = "%s IS PLAYING..." % game.seats[game.current].name


func _update_buttons() -> void:
	var can := game != null and human_turn and not busy and game.phase == TableGame.Phase.ACT
	meld_btn.disabled = not can
	discard_btn.disabled = not can
	hint_btn.disabled = not can
	var owned := 0
	if game != null and view_seat < game.seats.size():
		owned = game.seats[view_seat].powerups.size()
	power_btn.text = "PWR x%d" % owned
	power_btn.disabled = not can or owned == 0


## Outlines every tile that is part of at least one meld the hand can lay right now.
func _update_hint_marks() -> void:
	var usable := {}
	if game != null and human_turn and game.phase == TableGame.Phase.ACT:
		for h in game.hints(view_seat):
			for t: int in h.tiles:
				usable[t] = true
	for v in views:
		v.hint = usable.has(v.tile)


func _on_hint() -> void:
	if not human_turn or busy or game.phase != TableGame.Phase.ACT:
		return
	var list := game.hints(view_seat)
	if list.is_empty():
		_show_message("NO MELDS - DISCARD A TILE", MULT_RED)
		return
	var h: Dictionary = list[hint_index % list.size()]
	hint_index += 1
	for v in views:
		if v.selected:
			v.set_selected(false)
	var pool: Array[TileView] = views.duplicate()
	for t: int in h.tiles:
		for v in pool:
			if v.tile == t:
				v.set_selected(true)
				pool.erase(v)
				break
	sfx.play("hint")
	_show_message("%s  +%d  (%d/%d)" % [h.name, h.total, (hint_index - 1) % list.size() + 1, list.size()], Style.MINT)
	_update_preview()


func _on_power() -> void:
	if not human_turn or busy or game.phase != TableGame.Phase.ACT:
		return
	var me := game.seats[view_seat]
	if me.powerups.is_empty():
		return
	_open_overlay("POWER-UPS")
	var y := 76.0
	for id: String in TableGame.POWER_IDS:
		var n := me.powerups.count(id)
		if n == 0:
			continue
		var info: Dictionary = TableGame.POWERUPS[id]
		_button("%s x%d" % [info.name, n], Rect2(70, y, 100, 18), _use_power.bind(id), overlay)
		_label(info.desc, 8, Style.TEXT, Vector2(178, y + 5), 300, HORIZONTAL_ALIGNMENT_LEFT, overlay)
		y += 22.0
	_button("CANCEL", Rect2(190, y + 8, 100, 18), _close_overlay, overlay)


func _use_power(id: String) -> void:
	_close_overlay()
	var sel := _selected_tiles()
	match id:
		"swap":
			if sel.size() != 1:
				_shake(2.0)
				_show_message("SELECT 1 TILE TO TRADE", MULT_RED)
				return
			_open_overlay("SWAP WITH WHO?")
			var y := 90.0
			for i in game.seats.size():
				if i == view_seat or game.seats[i].hand.is_empty():
					continue
				_button(game.seats[i].name, Rect2(190, y, 100, 18), _send_power.bind(id, sel, i), overlay)
				y += 24.0
			_button("CANCEL", Rect2(190, y + 8, 100, 18), _close_overlay, overlay)
		"dump3":
			var need := mini(3, game.seats[view_seat].hand.size())
			if sel.size() != need:
				_shake(2.0)
				_show_message("SELECT %d TILES TO DUMP" % need, MULT_RED)
				return
			_send_power(id, sel, -1)
		_:
			_send_power(id, [], -1)


func _send_power(id: String, tiles: Array, target: int) -> void:
	_close_overlay()
	_human_action({"type": "power", "id": id, "tiles": tiles, "target": target})


func _clear_score_display() -> void:
	meld_label.text = ""
	chips_label.text = "0"
	mult_label.text = "0"
	total_label.text = ""


func _update_preview() -> void:
	if animating:
		return
	if game == null or not human_turn or game.phase != TableGame.Phase.ACT:
		_clear_score_display()
		return
	var sel := _selected_tiles()
	total_label.text = ""
	if sel.size() < 2:
		meld_label.text = "SELECT TILES" if sel.is_empty() else "DISCARD?"
		meld_label.modulate = Color(1, 1, 1, 0.6)
		chips_label.text = "0"
		mult_label.text = "0"
		return
	var r := game.preview(view_seat, sel)
	if r.is_empty():
		meld_label.text = "NOT A MELD"
		meld_label.modulate = Color(1, 0.45, 0.45)
		chips_label.text = "0"
		mult_label.text = "0"
	else:
		meld_label.text = r.name
		meld_label.modulate = GOLD
		chips_label.text = str(r.chips)
		mult_label.text = str(r.mult)


# ---------------------------------------------------------------- Input

func _on_tile_clicked(v: TileView) -> void:
	if not human_turn or busy:
		return
	if not v.selected and _selected_tiles().size() >= MAX_SELECT:
		_shake(1.5)
		return
	v.set_selected(not v.selected)
	sfx.play("select" if v.selected else "deselect")
	_update_preview()


func _on_sort() -> void:
	sort_by_rank = not sort_by_rank
	sort_btn.text = "BY RANK" if sort_by_rank else "BY SUIT"
	_layout_hand()


func _on_meld() -> void:
	_human_action({"type": "meld", "tiles": _selected_tiles()})


func _on_discard() -> void:
	var sel := _selected_tiles()
	if sel.size() != 1:
		_shake(2.0)
		_show_message("SELECT 1 TILE TO DISCARD", MULT_RED)
		return
	_human_action({"type": "discard", "tile": sel[0]})


func _human_action(action: Dictionary) -> void:
	if not human_turn or busy:
		return
	busy = true
	hint_index = 0
	_update_buttons()
	if mode == "client":
		_rpc_action.rpc_id(1, action)
		return
	var ok := await _do_action(view_seat, action)
	busy = false
	_refresh()
	if ok:
		ui_acted.emit()


# ---------------------------------------------------------------- Actions + animation

## Applies an action to the game and plays its animation. Returns false if it was rejected.
func _do_action(si: int, action: Dictionary) -> bool:
	var res := game.apply(si, action)
	if not res.ok:
		last_err = str(res.err)
		if si == view_seat and human_turn:
			sfx.play("error")
			_shake(2.5)
			_show_message(last_err.to_upper(), MULT_RED)
		return false
	_broadcast_event(si, res)
	await _play(si, res)
	return true


## Plays the animation for an action that has already been applied to (or mirrored into) the game.
func _play(si: int, res: Dictionary) -> void:
	match res.type:
		"draw":
			sfx.play("draw")
			if si == view_seat:
				_reconcile_hand()
			elif res.from == "discard":
				_pop(discard_view)
			else:
				_pop(wall_view)
			for id: String in res.get("found", []):
				sfx.play("found")
				_float_text("POWER-UP: %s" % TableGame.POWERUPS[id].name, Vector2(240, 150), Style.MINT)
		"power":
			sfx.play("power")
			var info: Dictionary = TableGame.POWERUPS[res.id]
			_show_message("%s USES %s" % [game.seats[si].name, info.name], Style.MINT, 1.0)
			_flash(0.25)
			if si == view_seat or int(res.get("target", -1)) == view_seat:
				_reconcile_hand()
			if res.id == "dump3":
				_pop(discard_view)
			for id: String in res.get("found", []):
				_float_text("POWER-UP: %s" % TableGame.POWERUPS[id].name, Vector2(240, 150), Style.MINT)
		"meld":
			await _animate_meld(si, res)
			if si == view_seat and not res.get("refill", []).is_empty():
				_reconcile_hand()
			for id: String in res.get("found", []):
				_float_text("POWER-UP: %s" % TableGame.POWERUPS[id].name, Vector2(240, 150), Style.MINT)
		"discard":
			sfx.play("discard")
			_pop(discard_view)
			if si == view_seat:
				_reconcile_hand()
	_update_all()
	if res.get("out", false):
		await _go_out_fx(si)


func _animate_meld(si: int, res: Dictionary) -> void:
	animating = true
	var seat := game.seats[si]
	var col: Color = seat.character.color
	if si == view_seat:
		_reconcile_hand()
	_clear_center()
	var n: int = res.tiles.size()
	var start_x := (480.0 - (n * SLOT_W - 5)) / 2.0
	for i in n:
		var v := TileView.new()
		v.tile = res.tiles[i]
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.position = Vector2(start_x + i * SLOT_W, CENTER_Y)
		v.scale = Vector2.ZERO
		world.add_child(v)
		center_views.append(v)
		var tw := create_tween()
		tw.tween_interval(i * 0.04)
		tw.tween_property(v, "scale", Vector2.ONE, 0.15)

	var chips: int = res.base_chips
	for b: String in res.bonuses:
		_float_text(b, Vector2(240, 108), Style.AMBER)
	var mult: int = res.base_mult
	chips_label.text = str(chips)
	mult_label.text = str(mult)
	total_label.text = ""
	meld_label.text = "%s: %s" % [seat.name, res.name]
	meld_label.modulate = col.lightened(0.3)
	_pop(meld_label)
	sfx.play("meld")
	await get_tree().create_timer(0.35).timeout

	for i in n:
		var v := center_views[i]
		var step: int = res.steps[i]
		chips += step
		sfx.play("tick", 1.0 + i * 0.12)
		chips_label.text = str(chips)
		_pop(chips_label)
		_pop(v)
		var fl := create_tween()
		fl.tween_property(v, "flash", 1.0, 0.04)
		fl.tween_property(v, "flash", 0.0, 0.2)
		var centre := v.position + Vector2(TileView.W, TileView.H) / 2.0
		_float_text("+%d" % step, centre + Vector2(0, -34), CHIP_BLUE.lightened(0.4))
		_burst(centre, TileView.SUIT_COLORS[Meld.suit_of(res.tiles[i])], 10)
		await get_tree().create_timer(0.12).timeout

	if res.combo > 0:
		mult += res.combo
		sfx.play("surge")
		mult_label.text = str(mult)
		_pop(mult_label)
		_float_text("COMBO +%d SURGE" % res.combo, Vector2(240, 130), MULT_RED.lightened(0.3))
		await get_tree().create_timer(0.3).timeout

	if res.chain > 0:
		mult += res.chain
		sfx.play("surge", 1.25)
		mult_label.text = str(mult)
		_pop(mult_label)
		_float_text("CHAIN +%d SURGE" % res.chain, Vector2(240, 118), Style.AMBER)
		await get_tree().create_timer(0.3).timeout

	if res.surge > 0:
		mult += res.surge
		sfx.play("surge", 1.5)
		mult_label.text = str(mult)
		_pop(mult_label)
		_float_text("SURGE POWER-UP +%d" % res.surge, Vector2(240, 118), Style.MINT)
		await get_tree().create_timer(0.3).timeout

	var total: int = chips * mult
	total_label.text = "%d x %d = %d" % [chips, mult, total]
	_pop(total_label)
	var power := minf(total / 60.0, 9.0) * (1.0 if si == view_seat else 0.6)
	_shake(2.0 + power)
	_flash(0.2 + power * 0.03)
	_burst(Vector2(240, 100), col, 30)
	if res.stolen > 0:
		sfx.play("steal")
		_float_text("STOLE %d FROM %s" % [res.stolen, game.seats[res.victim].name], Vector2(240, 180), Color("d9a0ff"))
	await _sync_scores()
	await get_tree().create_timer(0.3).timeout
	_clear_center()
	_clear_score_display()
	animating = false
	_update_preview()


func _go_out_fx(si: int) -> void:
	sfx.play("out")
	_shake(7.0)
	_flash(0.5)
	_burst(Vector2(240, 130), GOLD, 60)
	_burst(Vector2(100, 130), MULT_RED, 30)
	_burst(Vector2(380, 130), CHIP_BLUE, 30)
	var pts := int(game.end_info.get("bonus", TableGame.OUT_BONUS))
	_show_message("%s GOES OUT!%s" % [game.seats[si].name, "  +%d" % pts if pts > 0 else ""], GOLD, 1.4)
	await _sync_scores()
	await get_tree().create_timer(1.0).timeout


func _clear_center() -> void:
	for v in center_views:
		var tw := create_tween()
		tw.tween_property(v, "scale", Vector2.ZERO, 0.12)
		tw.tween_callback(v.queue_free)
	center_views.clear()


func _sync_scores() -> void:
	var last: Tween
	for i in game.seats.size():
		var tw := create_tween()
		tw.tween_method(_set_shown.bind(i), shown_totals[i], float(game.seats[i].total), 0.5)
		last = tw
	await last.finished


func _set_shown(value: float, i: int) -> void:
	shown_totals[i] = value
	_update_all()


# ---------------------------------------------------------------- Overlay + juice

func _open_overlay(heading: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	overlay = Control.new()
	overlay.theme = theme
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(overlay)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.75)
	overlay.add_child(dim)
	if heading != "":
		_label(heading, 16, GOLD, Vector2(0, 50), 480, HORIZONTAL_ALIGNMENT_CENTER, overlay)


func _pop(ctrl: Control) -> void:
	ctrl.pivot_offset = ctrl.size / 2.0
	ctrl.scale = Vector2(1.35, 1.35)
	create_tween().tween_property(ctrl, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _shake(amount: float) -> void:
	var tw := create_tween()
	for i in 6:
		tw.tween_property(world, "position", Vector2(randf_range(-1, 1), randf_range(-1, 1)) * amount * (1.0 - i / 6.0), 0.03)
	tw.tween_property(world, "position", Vector2.ZERO, 0.03)


func _flash(amount: float) -> void:
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: (crt.material as ShaderMaterial).set_shader_parameter("flash", v), amount, 0.0, 0.3)
	var tw2 := create_tween()
	tw2.tween_method(func(v: float) -> void: (bg.material as ShaderMaterial).set_shader_parameter("pulse", v), amount, 0.0, 0.6)


func _burst(pos: Vector2, color: Color, amount: int) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.spread = 180.0
	p.direction = Vector2.UP
	p.initial_velocity_min = 50.0
	p.initial_velocity_max = 130.0
	p.gravity = Vector2(0, 240)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 3.0
	p.color = color
	var g := Gradient.new()
	g.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	g.offsets = PackedFloat32Array([0.4, 1.0])
	p.color_ramp = g
	world.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


func _float_text(text: String, pos: Vector2, color: Color) -> void:
	var l := _label(text, 8, color, pos - Vector2(110, 0), 220, HORIZONTAL_ALIGNMENT_CENTER)
	var tw := create_tween().set_parallel()
	tw.tween_property(l, "position:y", pos.y - 18, 0.7)
	tw.tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)


func _show_message(text: String, color: Color, hold := 0.7) -> void:
	message_label.text = text
	message_label.add_theme_color_override("font_color", color)
	message_label.modulate.a = 1.0
	_pop(message_label)
	var tw := create_tween()
	tw.tween_interval(hold)
	tw.tween_property(message_label, "modulate:a", 0.0, 0.3)
