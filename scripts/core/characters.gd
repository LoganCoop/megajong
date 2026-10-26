class_name Characters
## Playable characters. Each has a passive that TableGame applies when scoring.

const ALL := [
	{"id": "dragon", "name": "DRAGON", "kana": "龍", "desc": "Sets get\n+2 SURGE", "tag": "SETS +2 SURGE", "set_mult": 2, "color": Color("ff3d5a")},
	{"id": "crane", "name": "CRANE", "kana": "鶴", "desc": "Runs get\n+2 SURGE", "tag": "RUNS +2 SURGE", "run_mult": 2, "color": Color("19f0ff")},
	{"id": "magpie", "name": "MAGPIE", "kana": "鵲", "desc": "+20 DATA\nper meld", "tag": "+20 DATA/MELD", "meld_chips": 20, "color": Color("ffb43a")},
	{"id": "fox", "name": "FOX", "kana": "狐", "desc": "Starts with\na WILD tile", "tag": "START WITH WILD", "start_wild": true, "color": Color("c77dff")},
]


static func get_by_id(id: String) -> Dictionary:
	for c: Dictionary in ALL:
		if c.id == id:
			return c
	return ALL[0]
