extends Node

signal typing_finished

@export var typing_speed: float = 0.03

@onready var info_screen_label: Label = null

var default_text: String = ""
var current_mode: String = "idle"
var is_typing: bool = false
var typing_tween: Tween = null

# Track used phrases to avoid repeats until all are shown
var used_phrases: Dictionary = {
	"round_end_player_close": [],
	"round_end_player_dominant": [],
	"round_end_opponent_close": [],
	"round_end_opponent_crushing": [],
	"game_end_player": [],
	"game_end_opponent": [],
	"general": [],
	"pass_hover": [],
	"opponent_bad_move": [],   # Opponent plays low/takes high
	"opponent_mid_move": [],    # Opponent plays mid/takes mid
	"opponent_good_move": [],   # Opponent plays high/takes low
	"opponent_pass": [],
	"game_loading": []          # Initial game setup messages
}

func _ready():
	await get_tree().process_frame
	_find_info_screen()
	if info_screen_label:
		info_screen_label.text = default_text
		# Show a random loading message when the game starts
		show_game_loading_message()

func _find_info_screen():
	var ui_panel = get_node_or_null("../../FrontLayerUI/UIPanel")
	if ui_panel:
		var info_screen = ui_panel.get_node_or_null("PanelBG/VBoxContainer/InformationScreen/Label")
		if info_screen:
			info_screen_label = info_screen

func set_text(new_text: String) -> void:
	if not info_screen_label:
		return
	
	if typing_tween and typing_tween.is_running():
		typing_tween.kill()
	
	if new_text == "":
		info_screen_label.text = ""
		is_typing = false
		emit_signal("typing_finished")
		return
	
	is_typing = true
	info_screen_label.text = ""
	
	typing_tween = create_tween()
	var char_count = new_text.length()
	
	for i in range(char_count):
		typing_tween.tween_callback(func(): 
			if info_screen_label:
				info_screen_label.text = new_text.substr(0, i + 1)
		)
		typing_tween.tween_interval(typing_speed)
	
	typing_tween.tween_callback(func(): 
		is_typing = false
		emit_signal("typing_finished")
	)

func get_text() -> String:
	if info_screen_label:
		return info_screen_label.text
	return ""

func clear() -> void:
	set_text("")
	current_mode = "idle"

func show_card_info(card_name: String) -> void:
	var turn_manager = get_node_or_null("/root/main/Managers/TurnManager")
	if not turn_manager or not turn_manager.get_is_player_turn():
		return
	if current_mode == "tutorial":
		return
	
	var card_data_loader = get_node_or_null("/root/CardDataLoader")
	if not card_data_loader:
		return
	
	var data = card_data_loader.get_card_data(card_name)
	if data.is_empty():
		return
	
	var info_text = data.get("description", "")
	set_text(info_text)
	current_mode = "card_info"

func show_game_commentary(params: Dictionary) -> void:
	if current_mode == "tutorial":
		return
	
	var commentary = _get_random_commentary(params)
	set_text(commentary)
	current_mode = "commentary"

func show_round_end_commentary(winner: String, player_score: int, opponent_score: int) -> void:
	if current_mode == "tutorial":
		return
	
	var params = {
		"type": "round_end",
		"winner": winner,
		"player_score": player_score,
		"opponent_score": opponent_score,
		"close_game": abs(player_score - opponent_score) <= 5
	}
	var commentary = _get_random_commentary(params)
	set_text(commentary)
	current_mode = "round_end"

func show_game_end_commentary(winner: String, player_total: int, opponent_total: int) -> void:
	var params = {
		"type": "game_end",
		"winner": winner,
		"player_total": player_total,
		"opponent_total": opponent_total
	}
	var commentary = _get_random_commentary(params)
	set_text(commentary)
	current_mode = "game_end"

func display_round_winner(winner: int, score: int) -> void:
	"""
	Called by GameManager when a single player wins the round.
	winner: integer (GameManager.Player enum value where 0 is player one / the human)
	score: the points awarded to the winner (lower total in this game's rules)
	"""
	if current_mode == "tutorial":
		return

	# Best-effort mapping: Player one (0) is the human player; anything else is opponent.
	var winner_text = "You" if winner == 0 else "Opponent"
	var message = "%s won the round with %d points!" % [winner_text, score]
	set_text(message)
	current_mode = "round_end"

func display_round_tie(score: int) -> void:
	"""
	Called by GameManager when the round ends in a tie. Both players receive their points.
	"""
	if current_mode == "tutorial":
		return

	# On a tie, no points are awarded (score param may be 0 to indicate this)
	var message: String = ""
	if score <= 0:
		message = "It's a tie. No points awarded."
	else:
		message = "It's a tie! Both players receive %d points." % score
	set_text(message)
	current_mode = "round_end"

func show_tutorial_message(message: String) -> void:
	set_text(message)
	current_mode = "tutorial"

func exit_tutorial_mode() -> void:
	if current_mode == "tutorial":
		clear()

func test_typing(message: String = "Hello! This is a test message!") -> void:
	set_text(message)

func show_pass_button_hover(actions_left: int = 0) -> void:
	# Robust GameManager lookup: support autoload, scene Managers container, parent, and current scene find
	var gm: Node = null
	gm = get_node_or_null("/root/GameManager")
	if not gm:
		gm = get_node_or_null("/root/main/Managers/GameManager")
	if not gm:
		var manager_container = get_parent()
		if manager_container:
			gm = manager_container.get_node_or_null("GameManager")
	if not gm:
		var current_scene = get_tree().get_current_scene()
		if current_scene and current_scene.has_method("find_node"):
			gm = current_scene.find_node("GameManager", true, false)

	if not gm:
		# Not critical: InfoScreen should tolerate missing GameManager during early setup
		return
	if gm.current_game_state != gm.GameState.IN_ROUND:
		return

	var turn_manager = get_node_or_null("/root/main/Managers/TurnManager")
	if not turn_manager or not turn_manager.get_is_player_turn():
		return
	if current_mode == "tutorial":
		return
	
	# Build the actions phrase with proper singular/plural (max 2 actions in game)
	var actions_phrase = ""
	if actions_left == 1:
		actions_phrase = "You DO know you have 1 action left, right?"
	else:
		actions_phrase = "You DO know you have 2 actions left, right?"
	
	var phrases = [
		"Done already? (ಠ_ಠ)",
		"Are you sure you're finished?",
		"Well? We're waiting....",
		"Really? With that hand?  (⚆ᗝ⚆)",
		actions_phrase,
		"Just so we're clear, you're choosing to do nothing else.",
		"That's an... interesting strategy. (゜-゜)",
		"Those are cards in a hand, yes (ꆤ⍸ꆤ)",
		"That's one way to play, I guess."
	]
	
	var random_phrase = _get_non_repeating_phrase(phrases, "pass_hover")
	set_text(random_phrase)
	current_mode = "pass_hover"

func show_opponent_move_commentary(move_quality: String) -> void:
	"""
	Show commentary based on how good/bad the opponent's move was for the player.
	move_quality can be: "bad" (opponent helps player), "mid" (neutral), or "good" (opponent hurts player)
	"""
	if current_mode == "tutorial":
		return
	
	var phrases = []
	var category_key = ""
	
	match move_quality:
		"bad":  # Opponent made a mistake that helps the player (gives us low card, takes our high card, peeks our high card)
			category_key = "opponent_bad_move"
			phrases = [
				"That's what I'm talking about!",
				"Amateur. It almost feels bad to beat them. Almost.",
				"Ladies and gentlemen...we got 'em (⌐▨_▨)",
				"A gift! And we shall accept it.",
				"Was that a mistake? Or just a really bad move?",
				"And that's what we call a 'tactical error'.",
				"Oh, you got this in the bag now.",
				"Can't believe they just did that! (ﾉ◕ヮ◕)ﾉ*:･ﾟ✧",
				"(/・0・) let's f◾️◾️◾️ing goooo!",
				"┗(＾ 0 ＾)┓"
			]
		
		"mid":  # Opponent made an okay move (mid value swaps/peeks)
			category_key = "opponent_mid_move"
			phrases = [
				"Oof.",
				"Alright, alright. Deep breaths.",
				"Annoying, but manageable.",
				"Nothing we can't handle.",
				"We can recover from that.",
				"Damn, well okay then.",
				"♪～(￣、￣ ) don't sweat it.",
				"(︶︹︺) Not ideal, but not a disaster."
			]
		
		"good":  # Opponent made a great move that hurts the player (gives us high card, takes our low card, peeks our low card)
			category_key = "opponent_good_move"
			phrases = [
				"DAAAAAMMMMNNN!!",
				"That has got to sting...",
				"Okay, that was just rude.",
				"Did they really just do that to us?",
				"Houston, we have a problem.",
				"I don't think we're making it out of this one...",
				"Who needs to win things, anyways? ଵ ˛̼ ଵ",
				"(;° ロ°)",
				"˚‧º·(˃̣̣̥⌓˂̣̣̥)‧º·˚"
			]
	
	if phrases.is_empty():
		return
	
	var random_phrase = _get_non_repeating_phrase(phrases, category_key)
	set_text(random_phrase)
	current_mode = "opponent_move"

func show_opponent_pass_commentary() -> void:
	var phrases = [
		"Oh. They're confident.",
		"Talk about PASSive aggressive. Bold.",
		"They think they've already won. You should do something about that.",
		"Happy with that hand, are they? We'll see about that.",
		"Poker face. It's a bluff... wait, does that work in this game?",
		"I smell fear. Or my circuits are overheating again.",
		"That looked like a 'I have no good cards' pass if I've ever seen one.",
		"Nothing to play? Or just pretending they have nothing to play?",
		"hmmm...",
		"That...can be a good thing...sometimes",
		"What are they planning...?",
		"My probability analysis is inconclusive. You're on your own, kid.",
		"An interesting tactical decision.",
		"I have a bad feeling about this."
	]

	var random_phrase = _get_non_repeating_phrase(phrases, "opponent_pass")
	set_text(random_phrase)
	current_mode = "opponent_pass"

func show_game_loading_message() -> void:
	"""
	Show a random loading/setup message at the start of the game.
	"""
	var phrases = [
		"Hi there, let me get things set up.",
		"No that's okay, don't help - I'll set it up (¬_¬).",
		"Shuffling......................and done! Oop, actually 1 sec...",
		"mmmm, give me a moment.",
		"Waking up my circuits... one moment please.",
		"Alright, cards are here, table is... clean enough. Let's do this.",
		"Polishing the pixels... dusting off the deck...",
		"Let's see what you got!",
		"Well, well, well... look who it is.",
		"Pay no attention to the computer at the bottom of the screen...",
		"Remember: it's not whether you win or lose, it's... no, it's definitely whether you win."
	]
	
	var random_phrase = _get_non_repeating_phrase(phrases, "game_loading")
	set_text(random_phrase)
	current_mode = "loading"

func _get_random_commentary(params: Dictionary) -> String:
	var type = params.get("type", "general")
	var phrases = []
	
	match type:
		"round_end":
			if params.get("winner") == "player":
				if params.get("close_game", false):
					phrases = [
						"Whew! Won by the skin\nof your teeth!",
						"That was WAY too close.\nDon't do that to me again.",
						"You were lucky. Don't\nlet it get to your head."
					]
				else:
					phrases = [
						"Okay, showoff.\nWe get it, you're good.",
						"You didn't just win,\nyou embarrassed them.",
						"An absolute masterclass!\nWere you even trying?"
					]
			else:
				if params.get("close_game", false):
					phrases = [
						"Oof. So close.\nThat's gotta sting a little.",
						"You almost had it! 'Almost'\nbeing the key word.",
						"Should've played that\nother card, huh?"
					]
				else:
					phrases = [
						"Well, that was a disaster.\nLet's not do that again.",
						"Okay, let's just forget\nthat round ever happened.",
						"Did you... have a plan?\nJust checking."
					]
		
		"game_end":
			if params.get("winner") == "player":
				phrases = [
					"You actually did it!\nI'm impressed, honestly.",
					"VICTORY!\nNow go brag to your friends.",
					"Game, Set, Match.\nThey never stood a chance."
				]
			else:
				phrases = [
					"And that's the game.\nWant to try NOT losing?",
					"Defeated! But hey,\nlosing builds character... right?",
					"Go get a snack.\nThen come back for revenge."
				]
		
		"general":
			phrases = [
				"An interesting choice...\nNot the one I would've made.",
				"I see what you're doing there.\nI think.",
				"Now this is where\nit gets spicy!"
			]
	
	if phrases.is_empty():
		return "..."
	
	# Get category key for tracking
	var category_key = type
	if type == "round_end":
		if params.get("winner") == "player":
			category_key = "round_end_player_close" if params.get("close_game", false) else "round_end_player_dominant"
		else:
			category_key = "round_end_opponent_close" if params.get("close_game", false) else "round_end_opponent_crushing"
	elif type == "game_end":
		category_key = "game_end_player" if params.get("winner") == "player" else "game_end_opponent"
	
	return _get_non_repeating_phrase(phrases, category_key)

func _get_non_repeating_phrase(phrases: Array, category_key: String) -> String:
	# Ensure a tracking list exists for this category
	if not used_phrases.has(category_key):
		used_phrases[category_key] = []

	# If we've used all phrases, reset the tracking for this category
	if used_phrases[category_key].size() >= phrases.size():
		used_phrases[category_key].clear()

	# Find available phrases (ones we haven't used yet)
	var available_phrases = []
	for phrase in phrases:
		if phrase not in used_phrases[category_key]:
			available_phrases.append(phrase)

	# If something went wrong and available is empty, fallback to full list
	if available_phrases.size() == 0:
		available_phrases = phrases.duplicate()

	# Pick a random one from available phrases
	var selected_phrase = available_phrases[randi() % available_phrases.size()]

	# Mark it as used
	used_phrases[category_key].append(selected_phrase)

	return selected_phrase
