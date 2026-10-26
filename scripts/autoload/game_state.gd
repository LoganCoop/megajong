extends Node
## Global run state (score, round, money). Registered as the `GameState` autoload.

signal score_changed(new_score: int)

var round_number: int = 1
var money: int = 0
var score: int = 0:
	set(value):
		score = value
		score_changed.emit(score)


func new_run() -> void:
	round_number = 1
	money = 0
	score = 0
