class_name KingdomCombatWindow
extends AcceptDialog

signal action_requested(type: String, args: Array)
const BattleScript: Script = preload("res://src/battle_view.gd")
var battlefield: KingdomBattleView

func _ready() -> void:
	title = "战斗指挥 · 我军在左，敌军在右"
	ok_button_text = "返回城池（战斗保留）"
	wrap_controls = false
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	battlefield = BattleScript.new() as KingdomBattleView
	battlefield.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(battlefield)
	battlefield.action_requested.connect(func(type: String, args: Array) -> void: action_requested.emit(type, args))
	get_tree().root.size_changed.connect(_fit_window)
	_fit_window()

func update_battle(battle: Variant, units: Dictionary, enabled: bool) -> void:
	if is_instance_valid(battlefield):
		battlefield.set_battle(battle, units)
		battlefield.set_actions_enabled(enabled)

func open_battle() -> void:
	_fit_window()
	popup_centered(size)

func _fit_window() -> void:
	var viewport: Vector2 = get_tree().root.get_visible_rect().size
	min_size = Vector2i(280, 340)
	size = Vector2i(int(minf(1380, viewport.x - 28)), int(minf(1000, viewport.y - 52)))
	if visible:
		position = Vector2i((viewport - Vector2(size)) / 2)
