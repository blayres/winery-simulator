## VineyardActionSystem.gd
## Singleton — all player-initiated vineyard actions.
##
## Responsibility:
##   Validates and applies player actions to TileSimData via VineyardSimulation.
##   Returns a human-readable result string for console logging and future UI.
##   Emits action_performed so any system can react (future: economy, UI, events).
##
## Architecture:
##   This is the ONLY entry point for player-driven tile mutations.
##   Input handlers (World.gd) call these methods — they never mutate sim data
##   directly. This makes actions easy to trigger from UI buttons, events, or
##   scripted sequences later without changing the action logic.
##
##   All numeric values come from vineyard_sim_config.json "player_actions".
##   No magic numbers in this file.

extends Node

# ─── Signals ──────────────────────────────────────────────────────────────────
## Emitted after any action succeeds.
## [param action]  — action id string (e.g. "irrigate")
## [param col/row] — tile address
## [param result]  — human-readable outcome string
signal action_performed(action: String, col: int, row: int, result: String)

# ─── Action IDs ───────────────────────────────────────────────────────────────
const ACTION_IRRIGATE: String = "irrigate"
const ACTION_DRAIN:    String = "drain"
const ACTION_TREAT:    String = "treat_disease"
const ACTION_PRUNE:    String = "prune"
const ACTION_REPLANT:  String = "replant"

# ─── Public API ───────────────────────────────────────────────────────────────

## Irrigate: raises tile humidity.
## Works on any tile (planted or empty).
func irrigate(col: int, row: int) -> String:
	var data: TileSimData = VineyardSimulation.get_tile_data(col, row)
	if data == null:
		return "No tile at (%d,%d)." % [col, row]

	var cfg: Dictionary  = _action_cfg()
	var gain: float      = float(cfg.get("irrigate_humidity_gain", 0.18))
	var before: float    = data.humidity
	data.humidity        = clampf(data.humidity + gain, 0.0, 1.0)
	var result: String   = "Irrigate (%d,%d): humidity %.2f → %.2f" % [col, row, before, data.humidity]

	_commit(data, ACTION_IRRIGATE, result)
	return result


## Drain: lowers tile humidity.
## Works on any tile.
func drain(col: int, row: int) -> String:
	var data: TileSimData = VineyardSimulation.get_tile_data(col, row)
	if data == null:
		return "No tile at (%d,%d)." % [col, row]

	var cfg: Dictionary  = _action_cfg()
	var loss: float      = float(cfg.get("drain_humidity_loss", 0.20))
	var before: float    = data.humidity
	data.humidity        = clampf(data.humidity - loss, 0.0, 1.0)
	var result: String   = "Drain (%d,%d): humidity %.2f → %.2f" % [col, row, before, data.humidity]

	_commit(data, ACTION_DRAIN, result)
	return result


## Treat Disease: reduces disease risk.
## Requires a planted vine.
func treat_disease(col: int, row: int) -> String:
	var data: TileSimData = VineyardSimulation.get_tile_data(col, row)
	if data == null:
		return "No tile at (%d,%d)." % [col, row]
	if not data.is_planted:
		return "Treat (%d,%d): no vine planted — nothing to treat." % [col, row]

	var cfg: Dictionary  = _action_cfg()
	var reduction: float = float(cfg.get("treat_disease_reduction", 0.25))
	var before: float    = data.disease_risk
	data.disease_risk    = clampf(data.disease_risk - reduction, 0.0, 1.0)
	var result: String   = "Treat (%d,%d): disease %.2f → %.2f" % [col, row, before, data.disease_risk]

	_commit(data, ACTION_TREAT, result)
	return result


## Prune: improves vine health and productivity slightly.
## Requires a planted vine.
func prune(col: int, row: int) -> String:
	var data: TileSimData = VineyardSimulation.get_tile_data(col, row)
	if data == null:
		return "No tile at (%d,%d)." % [col, row]
	if not data.is_planted:
		return "Prune (%d,%d): no vine planted — nothing to prune." % [col, row]

	var cfg: Dictionary    = _action_cfg()
	var health_gain: float = float(cfg.get("prune_health_gain", 0.08))
	var prod_gain: float   = float(cfg.get("prune_productivity_gain", 0.06))

	var before_h: float  = data.vine_health
	var before_p: float  = data.productivity
	data.vine_health     = clampf(data.vine_health  + health_gain, 0.0, 1.0)
	data.productivity    = clampf(data.productivity + prod_gain,   0.0, 1.0)

	VineyardSimulation.recompute_quality_public(data)

	var result: String = "Prune (%d,%d): health %.2f→%.2f  productivity %.2f→%.2f" % [
		col, row, before_h, data.vine_health, before_p, data.productivity
	]

	_commit(data, ACTION_PRUNE, result)
	return result


## Replant: removes existing vine (if any) and plants a fresh young vine.
## Works on planted or empty tiles.
func replant(col: int, row: int, grape_id: String = "") -> String:
	var data: TileSimData = VineyardSimulation.get_tile_data(col, row)
	if data == null:
		return "No tile at (%d,%d)." % [col, row]

	var cfg: Dictionary    = _action_cfg()
	var start_health: float = float(cfg.get("replant_starting_health", 0.85))
	var default_grape: String = str(cfg.get("replant_default_grape", "pinot_noir"))
	var chosen_grape: String  = grape_id if grape_id != "" else default_grape

	var was_planted: bool = data.is_planted
	data.is_planted    = true
	data.grape_variety = chosen_grape
	data.vine_age      = 0
	data.vine_health   = start_health
	data.disease_risk  = clampf(data.disease_risk * 0.5, 0.0, 1.0)  # partial reset
	data.lifecycle_stage = VineLifecycle.STAGE_YOUNG
	data.productivity    = 0.0

	VineyardSimulation.recompute_quality_public(data)

	var action_desc: String = "Replant" if was_planted else "Plant"
	var result: String = "%s (%d,%d): %s  health=%.2f" % [
		action_desc, col, row, chosen_grape, data.vine_health
	]

	_commit(data, ACTION_REPLANT, result)
	return result


# ─── Private ──────────────────────────────────────────────────────────────────

## Emit tile_data_changed and the action signal, then log to console.
func _commit(data: TileSimData, action: String, result: String) -> void:
	VineyardSimulation.tile_data_changed.emit(data)
	action_performed.emit(action, data.grid_col, data.grid_row, result)
	print("Action: %s" % result)


func _action_cfg() -> Dictionary:
	var cfg: Dictionary = DataManager.get_data("vineyard_sim")
	var raw: Variant    = cfg.get("player_actions", {})
	return raw if raw is Dictionary else {}
