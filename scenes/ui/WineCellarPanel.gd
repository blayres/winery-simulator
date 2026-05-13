## WineCellarPanel.gd
## Attached to: scenes/ui/WineCellarPanel.tscn
##
## TEMPORARY DEVELOPER UI — not the final production cellar screen.
## Shows all WineBatch objects, current money, a method selector, and a Sell button.
## Replace with the proper cellar UI when the game HUD is built.
##
## Usage:
##   C  → toggle panel visibility
##   S  → sell latest batch (also works without opening panel)
##   Panel auto-refreshes on fermentation, aging, and sales.
##
## Method selector:
##   Three toggle buttons (Stainless / Old Oak / New Oak).
##   Selected method is stored in FermentationManager.selected_method.
##   Ferment button and F-key both use the selected method.

class_name WineCellarPanel
extends CanvasLayer

const PANEL_W: float = 300.0
const PANEL_H: float = 580.0
const MARGIN:  float = 10.0

# ─── Method display data ──────────────────────────────────────────────────────
const METHOD_INFO: Dictionary = {
	"stainless_steel": {
		"label":       "Stainless",
		"description": "Fresh & clean. Preserves fruit character.",
		"color":       Color(0.55, 0.85, 0.95, 1.0),
	},
	"old_oak": {
		"label":       "Old Oak",
		"description": "Balanced. Adds gentle complexity.",
		"color":       Color(0.85, 0.72, 0.45, 1.0),
	},
	"new_oak": {
		"label":       "New Oak",
		"description": "Bold & oaky. Strong style, higher cost.",
		"color":       Color(0.90, 0.55, 0.30, 1.0),
	},
}

# ─── Child nodes ──────────────────────────────────────────────────────────────
@onready var _root_panel:    PanelContainer  = $RootPanel
@onready var _lbl_header:    Label           = $RootPanel/Margin/VBox/Header
@onready var _lbl_money:     Label           = $RootPanel/Margin/VBox/MoneyLabel
@onready var _lbl_count:     Label           = $RootPanel/Margin/VBox/CountLabel
@onready var _lbl_method_hdr: Label          = $RootPanel/Margin/VBox/MethodHeader
@onready var _method_row:    HBoxContainer   = $RootPanel/Margin/VBox/MethodRow
@onready var _btn_stainless: Button          = $RootPanel/Margin/VBox/MethodRow/BtnStainless
@onready var _btn_old_oak:   Button          = $RootPanel/Margin/VBox/MethodRow/BtnOldOak
@onready var _btn_new_oak:   Button          = $RootPanel/Margin/VBox/MethodRow/BtnNewOak
@onready var _lbl_method_desc: Label         = $RootPanel/Margin/VBox/MethodDesc
@onready var _lbl_method_cost: Label         = $RootPanel/Margin/VBox/MethodCost
@onready var _btn_ferment:   Button          = $RootPanel/Margin/VBox/BtnFerment
@onready var _btn_sell:      Button          = $RootPanel/Margin/VBox/BtnSell
@onready var _scroll:        ScrollContainer = $RootPanel/Margin/VBox/Scroll
@onready var _list:          RichTextLabel   = $RootPanel/Margin/VBox/Scroll/BatchList
@onready var _lbl_hint:      Label           = $RootPanel/Margin/VBox/HintLabel

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	get_viewport().size_changed.connect(_place_panel)
	_place_panel.call_deferred()

	FermentationManager.batches_changed.connect(_on_batches_changed)
	FermentationManager.fermentation_completed.connect(_on_fermentation_completed)
	FermentationManager.aging_tick_completed.connect(_on_aging_tick)
	FermentationManager.method_changed.connect(_on_method_changed)
	WineMarket.money_changed.connect(_on_money_changed)
	WineMarket.batch_sold.connect(_on_batch_sold)

	_btn_stainless.pressed.connect(_on_stainless_pressed)
	_btn_old_oak.pressed.connect(_on_old_oak_pressed)
	_btn_new_oak.pressed.connect(_on_new_oak_pressed)
	_btn_ferment.pressed.connect(_on_ferment_pressed)
	_btn_sell.pressed.connect(_on_sell_pressed)

	_root_panel.visible = false
	_refresh()


func _place_panel() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp.x < 100.0:
		vp = Vector2(1280.0, 720.0)
	_root_panel.position = Vector2(180.0, MARGIN)
	_root_panel.size     = Vector2(PANEL_W, minf(PANEL_H, vp.y - MARGIN * 2.0))


# ─── Public API ───────────────────────────────────────────────────────────────

func toggle() -> void:
	_root_panel.visible = not _root_panel.visible
	if _root_panel.visible:
		_refresh()


func show_panel() -> void:
	_root_panel.visible = true
	_refresh()


func hide_panel() -> void:
	_root_panel.visible = false


# ─── Private — signal handlers ────────────────────────────────────────────────

func _on_batches_changed(_total: int) -> void:
	if _root_panel.visible:
		_refresh()


func _on_fermentation_completed(_batch: WineBatch) -> void:
	if _root_panel.visible:
		_refresh()


func _on_aging_tick() -> void:
	if _root_panel.visible:
		_refresh()


func _on_money_changed(_new_amount: float, _delta: float) -> void:
	if _root_panel.visible:
		_refresh_method_ui()
		_lbl_money.text = "Money   €%.0f" % WineMarket.get_money()


func _on_batch_sold(_name: String, _price: float, _money: float) -> void:
	if _root_panel.visible:
		_refresh()


func _on_method_changed(_method: String) -> void:
	if _root_panel.visible:
		_refresh_method_ui()


# ─── Private — method selector ────────────────────────────────────────────────

func _on_stainless_pressed() -> void:
	FermentationManager.set_selected_method(FermentationManager.METHOD_STAINLESS)


func _on_old_oak_pressed() -> void:
	FermentationManager.set_selected_method(FermentationManager.METHOD_OLD_OAK)


func _on_new_oak_pressed() -> void:
	FermentationManager.set_selected_method(FermentationManager.METHOD_NEW_OAK)


func _on_ferment_pressed() -> void:
	VineyardActionSystem.ferment()


func _on_sell_pressed() -> void:
	WineMarket.sell_latest()


## Refresh only the method selector row — called on money/method changes.
func _refresh_method_ui() -> void:
	var method: String = FermentationManager.get_selected_method()
	var money: float   = WineMarket.get_money()
	var cost: float    = FermentationManager.get_method_cost(method)
	var has_lots: bool = HarvestManager.get_lot_count() > 0

	# Highlight the active method button.
	var info_s: Dictionary = METHOD_INFO["stainless_steel"]
	var info_o: Dictionary = METHOD_INFO["old_oak"]
	var info_n: Dictionary = METHOD_INFO["new_oak"]

	_btn_stainless.modulate = info_s["color"] if method == "stainless_steel" else Color(0.6, 0.6, 0.6, 1.0)
	_btn_old_oak.modulate   = info_o["color"] if method == "old_oak"         else Color(0.6, 0.6, 0.6, 1.0)
	_btn_new_oak.modulate   = info_n["color"] if method == "new_oak"         else Color(0.6, 0.6, 0.6, 1.0)

	# Description and cost.
	var active_info: Dictionary = METHOD_INFO.get(method, METHOD_INFO["stainless_steel"])
	_lbl_method_desc.text = str(active_info.get("description", ""))
	_lbl_method_cost.text = "Cost: €%.0f" % cost

	# Ferment button state.
	_btn_ferment.disabled = not has_lots or money < cost
	if not has_lots:
		_btn_ferment.text = "Ferment  [F]  (no lots)"
	elif money < cost:
		_btn_ferment.text = "Ferment  [F]  (need €%.0f)" % cost
	else:
		_btn_ferment.text = "Ferment  [F]  €%.0f" % cost


# ─── Private — display ────────────────────────────────────────────────────────

func _refresh() -> void:
	var batches: Array = FermentationManager.get_all_batches()
	var count: int     = batches.size()

	_lbl_header.text = "Wine Cellar"
	_lbl_money.text  = "Money   €%.0f" % WineMarket.get_money()
	_lbl_count.text  = "%d batch%s in cellar" % [count, "es" if count != 1 else ""]
	_btn_sell.disabled = count == 0

	_refresh_method_ui()

	if count == 0:
		_list.text = "[color=#888888]No wine batches yet.\nHarvest grapes and ferment to create wine.[/color]"
		_lbl_hint.text = "C  close  |  F  ferment  |  S  sell"
		return

	var lines: PackedStringArray = PackedStringArray()
	for i: int in batches.size():
		if not batches[i] is WineBatch:
			continue
		var b: WineBatch       = batches[i]
		var abv: float         = 8.0 + b.alcohol_potential * 8.0
		var tier_color: String = _quality_color(b.wine_quality)
		var method_color: String = _method_color(b.fermentation_method)
		var price: float       = WineMarket.calculate_price(b)

		lines.append("[color=#c8a840]── Batch #%d ──[/color]" % b.batch_id)
		lines.append("[color=%s]%s[/color]  [color=#aaaaaa](%s)[/color]" % [
			tier_color, b.wine_name, b.quality_label()
		])
		# Method and style on one line — the key new info
		lines.append("  [color=%s]%s[/color]  ·  [color=#dddddd]%s[/color]" % [
			method_color, b.method_label(), b.style_label()
		])
		lines.append("  Year %d  ·  Age %dy  ·  [color=%s]%s[/color]" % [
			b.vintage_year, b.age_years,
			_stage_color(b.maturity_stage), b.maturity_label()
		])
		lines.append("  Quality   [color=%s]%.0f%%[/color]  ·  Aging pot. %.0f%%" % [
			tier_color, b.wine_quality * 100.0, b.aging_potential * 100.0
		])
		lines.append("  Freshness %.0f%%  ·  Complexity %.0f%%  ·  Oak %.0f%%" % [
			b.freshness * 100.0, b.complexity * 100.0, b.oak_influence * 100.0
		])
		lines.append("  Alcohol   %.1f%% ABV  ·  Bottles %d" % [abv, b.bottles_estimated])
		lines.append("  [color=#88dd88]Sale price  €%.0f[/color]" % price)
		if i < batches.size() - 1:
			lines.append("")

	_list.text = "\n".join(lines)
	_lbl_hint.text = "C  close  |  F  ferment  |  S  sell latest"


func _quality_color(quality: float) -> String:
	if quality >= 0.60: return "#f0d060"
	elif quality >= 0.45: return "#80d080"
	elif quality >= 0.30: return "#c0c0c0"
	else: return "#c06060"


func _method_color(method: String) -> String:
	match method:
		"stainless_steel": return "#88ccee"
		"old_oak":         return "#ddaa66"
		"new_oak":         return "#ee8844"
	return "#aaaaaa"


func _stage_color(stage: String) -> String:
	match stage:
		"young":      return "#88aaff"
		"developing": return "#88ddaa"
		"peak":       return "#f0d060"
		"declining":  return "#cc8866"
	return "#aaaaaa"


# ─── Input ────────────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and k.keycode == KEY_C:
			toggle()
			get_viewport().set_input_as_handled()
