## WineCellarPanel.gd
## Attached to: scenes/ui/WineCellarPanel.tscn
##
## TEMPORARY DEVELOPER UI — not the final production cellar screen.
## Shows all WineBatch objects currently in FermentationManager inventory.
## Replace with the proper cellar UI when the game HUD is built.
##
## Usage:
##   C  → toggle panel visibility
##   Panel auto-refreshes whenever a new WineBatch is created.
##
## Layout rule:
##   RootPanel is a direct child of a CanvasLayer — use position/size, not anchors.

class_name WineCellarPanel
extends CanvasLayer

# ─── Panel geometry ───────────────────────────────────────────────────────────
const PANEL_W: float = 280.0
const PANEL_H: float = 500.0
const MARGIN:  float = 10.0

# ─── Child nodes ──────────────────────────────────────────────────────────────
@onready var _root_panel: PanelContainer = $RootPanel
@onready var _lbl_header: Label          = $RootPanel/Margin/VBox/Header
@onready var _lbl_count:  Label          = $RootPanel/Margin/VBox/CountLabel
@onready var _scroll:     ScrollContainer = $RootPanel/Margin/VBox/Scroll
@onready var _list:       RichTextLabel  = $RootPanel/Margin/VBox/Scroll/BatchList
@onready var _lbl_hint:   Label          = $RootPanel/Margin/VBox/HintLabel

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	get_viewport().size_changed.connect(_place_panel)
	_place_panel.call_deferred()

	# Listen for new batches and aging ticks — refresh automatically.
	FermentationManager.batches_changed.connect(_on_batches_changed)
	FermentationManager.fermentation_completed.connect(_on_fermentation_completed)
	FermentationManager.aging_tick_completed.connect(_on_aging_tick)

	_root_panel.visible = false
	_refresh()


func _place_panel() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp.x < 100.0:
		vp = Vector2(1280.0, 720.0)
	# Left side, just right of the actions panel (actions panel is 160px wide).
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


# ─── Private — display ────────────────────────────────────────────────────────

func _refresh() -> void:
	var batches: Array = FermentationManager.get_all_batches()
	var count: int     = batches.size()

	_lbl_header.text = "Wine Cellar"
	_lbl_count.text  = "%d batch%s in cellar" % [count, "es" if count != 1 else ""]

	if count == 0:
		_list.text = "[color=#888888]No wine batches yet.\nHarvest grapes and ferment to create wine.[/color]"
		_lbl_hint.text = "C  close  |  F  ferment"
		return

	# Build the batch list as BBCode for colour-coded display.
	var lines: PackedStringArray = PackedStringArray()
	for i: int in batches.size():
		if not batches[i] is WineBatch:
			continue
		var b: WineBatch = batches[i]
		var abv: float   = 8.0 + b.alcohol_potential * 8.0
		var tier_color: String = _quality_color(b.wine_quality)

		lines.append("[color=#c8a840]── Batch #%d ──[/color]" % b.batch_id)
		lines.append("[color=%s]%s  (%s)[/color]" % [tier_color, b.wine_name, b.quality_label()])
		lines.append("  Year %d  ·  %s" % [b.vintage_year, b.method_label()])
		lines.append("  Age       %dy  ·  [color=%s]%s[/color]  (pot. %.0f%%)" % [
			b.age_years,
			_stage_color(b.maturity_stage),
			b.maturity_label(),
			b.aging_potential * 100.0
		])
		lines.append("  Quality   [color=%s]%.0f%%[/color]" % [tier_color, b.wine_quality * 100.0])
		lines.append("  Alcohol   %.1f%% ABV" % abv)
		lines.append("  Freshness %.0f%%  Body %.0f%%" % [b.freshness * 100.0, b.body * 100.0])
		lines.append("  Complexity %.0f%%  Oak %.0f%%" % [b.complexity * 100.0, b.oak_influence * 100.0])
		lines.append("  Bottles   %d est." % b.bottles_estimated)
		if i < batches.size() - 1:
			lines.append("")   # blank line between batches

	_list.text = "\n".join(lines)
	_lbl_hint.text = "C  close  |  F  ferment"


func _quality_color(quality: float) -> String:
	if quality >= 0.85:
		return "#f0d060"   # gold — exceptional
	elif quality >= 0.70:
		return "#80d080"   # green — good
	elif quality >= 0.50:
		return "#c0c0c0"   # silver — average
	else:
		return "#c06060"   # red — poor


func _stage_color(stage: String) -> String:
	match stage:
		"young":      return "#88aaff"   # blue — fresh
		"developing": return "#88ddaa"   # teal — growing
		"peak":       return "#f0d060"   # gold — best
		"declining":  return "#cc8866"   # amber — fading
	return "#aaaaaa"


# ─── Input ────────────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and k.keycode == KEY_C:
			toggle()
			get_viewport().set_input_as_handled()
