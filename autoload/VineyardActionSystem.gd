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
const ACTION_HARVEST:  String = "harvest"
const ACTION_FERMENT:  String = "ferment"
const ACTION_BUY_LAND: String = "buy_land"

# ─── Public API ───────────────────────────────────────────────────────────────

## Irrigate: raises tile humidity.
## Works on any tile (planted or empty).
func irrigate(col: int, row: int) -> String:
	var data: TileSimData = VineyardSimulation.get_tile_data(col, row)
	if data == null:
		return "No tile at (%d,%d)." % [col, row]
	if not data.is_owned:
		return "Irrigate (%d,%d): tile is locked — buy land first." % [col, row]

	var cost: float = _action_cost("irrigate")
	if not WineMarket.spend(cost, "irrigate"):
		return "Irrigate (%d,%d): not enough money — need €%.0f." % [col, row, cost]

	var cfg: Dictionary  = _action_cfg()
	var gain: float      = float(cfg.get("irrigate_humidity_gain", 0.18))
	var before: float    = data.humidity
	data.humidity        = clampf(data.humidity + gain, 0.0, 1.0)
	var result: String   = "Irrigate (%d,%d): humidity %.2f → %.2f  (€%.0f)" % [col, row, before, data.humidity, cost]

	_commit(data, ACTION_IRRIGATE, result)
	return result


## Drain: lowers tile humidity.
## Works on any tile.
func drain(col: int, row: int) -> String:
	var data: TileSimData = VineyardSimulation.get_tile_data(col, row)
	if data == null:
		return "No tile at (%d,%d)." % [col, row]
	if not data.is_owned:
		return "Drain (%d,%d): tile is locked — buy land first." % [col, row]

	var cost: float = _action_cost("drain")
	if not WineMarket.spend(cost, "drain"):
		return "Drain (%d,%d): not enough money — need €%.0f." % [col, row, cost]

	var cfg: Dictionary  = _action_cfg()
	var loss: float      = float(cfg.get("drain_humidity_loss", 0.20))
	var before: float    = data.humidity
	data.humidity        = clampf(data.humidity - loss, 0.0, 1.0)
	var result: String   = "Drain (%d,%d): humidity %.2f → %.2f  (€%.0f)" % [col, row, before, data.humidity, cost]

	_commit(data, ACTION_DRAIN, result)
	return result


## Treat Disease: reduces disease risk.
## Requires a planted vine.
func treat_disease(col: int, row: int) -> String:
	var data: TileSimData = VineyardSimulation.get_tile_data(col, row)
	if data == null:
		return "No tile at (%d,%d)." % [col, row]
	if not data.is_owned:
		return "Treat (%d,%d): tile is locked — buy land first." % [col, row]
	if not data.is_planted:
		return "Treat (%d,%d): no vine planted — nothing to treat." % [col, row]

	var cost: float = _action_cost("treat")
	if not WineMarket.spend(cost, "treat disease"):
		return "Treat (%d,%d): not enough money — need €%.0f." % [col, row, cost]

	var cfg: Dictionary  = _action_cfg()
	var reduction: float = float(cfg.get("treat_disease_reduction", 0.25))
	var before: float    = data.disease_risk
	data.disease_risk    = clampf(data.disease_risk - reduction, 0.0, 1.0)
	var result: String   = "Treat (%d,%d): disease %.2f → %.2f  (€%.0f)" % [col, row, before, data.disease_risk, cost]

	_commit(data, ACTION_TREAT, result)
	return result


## Prune: improves vine health and productivity slightly.
## Requires a planted vine.
func prune(col: int, row: int) -> String:
	var data: TileSimData = VineyardSimulation.get_tile_data(col, row)
	if data == null:
		return "No tile at (%d,%d)." % [col, row]
	if not data.is_owned:
		return "Prune (%d,%d): tile is locked — buy land first." % [col, row]
	if not data.is_planted:
		return "Prune (%d,%d): no vine planted — nothing to prune." % [col, row]

	var cost: float = _action_cost("prune")
	if not WineMarket.spend(cost, "prune"):
		return "Prune (%d,%d): not enough money — need €%.0f." % [col, row, cost]

	var cfg: Dictionary    = _action_cfg()
	var health_gain: float = float(cfg.get("prune_health_gain", 0.08))
	var prod_gain: float   = float(cfg.get("prune_productivity_gain", 0.06))

	var before_h: float  = data.vine_health
	var before_p: float  = data.productivity
	data.vine_health     = clampf(data.vine_health  + health_gain, 0.0, 1.0)
	data.productivity    = clampf(data.productivity + prod_gain,   0.0, 1.0)

	VineyardSimulation.recompute_quality_public(data)

	var result: String = "Prune (%d,%d): health %.2f→%.2f  prod %.2f→%.2f  (€%.0f)" % [
		col, row, before_h, data.vine_health, before_p, data.productivity, cost
	]

	_commit(data, ACTION_PRUNE, result)
	return result


## Replant: removes existing vine (if any) and plants a fresh young vine.
## Works on planted or empty tiles.
func replant(col: int, row: int, grape_id: String = "") -> String:
	var data: TileSimData = VineyardSimulation.get_tile_data(col, row)
	if data == null:
		return "No tile at (%d,%d)." % [col, row]
	if not data.is_owned:
		return "Replant (%d,%d): tile is locked — buy land first." % [col, row]

	var cost: float = _action_cost("replant")
	if not WineMarket.spend(cost, "replant"):
		return "Replant (%d,%d): not enough money — need €%.0f." % [col, row, cost]

	var cfg: Dictionary    = _action_cfg()
	var start_health: float = float(cfg.get("replant_starting_health", 0.85))
	var default_grape: String = str(cfg.get("replant_default_grape", "pinot_noir"))
	var chosen_grape: String  = grape_id if grape_id != "" else default_grape

	var was_planted: bool = data.is_planted
	data.is_planted    = true
	data.grape_variety = chosen_grape
	data.vine_age      = 0
	data.vine_health   = start_health
	data.disease_risk  = clampf(data.disease_risk * 0.5, 0.0, 1.0)
	data.lifecycle_stage = VineLifecycle.STAGE_YOUNG
	data.productivity    = 0.0

	VineyardSimulation.recompute_quality_public(data)

	var action_desc: String = "Replant" if was_planted else "Plant"
	var result: String = "%s (%d,%d): %s  health=%.2f  (€%.0f)" % [
		action_desc, col, row, chosen_grape, data.vine_health, cost
	]

	_commit(data, ACTION_REPLANT, result)
	return result


## Harvest: collects ripe grapes from a tile and creates a GrapeLot.
## Requires: owned, planted, harvest_ready, health > 0, productivity > 0, not already harvested.
func harvest(col: int, row: int) -> String:
	var data: TileSimData = VineyardSimulation.get_tile_data(col, row)
	if data != null and not data.is_owned:
		return "Harvest (%d,%d): tile is locked — buy land first." % [col, row]
	var cost: float = _action_cost("harvest")
	if not WineMarket.spend(cost, "harvest"):
		return "Harvest (%d,%d): not enough money — need €%.0f." % [col, row, cost]
	var result: String = HarvestManager.harvest(col, row)
	action_performed.emit(ACTION_HARVEST, col, row, result)
	return result


## Ferment: converts the most recent GrapeLot into a WineBatch.
## Uses FermentationManager.selected_method unless [param method] is explicitly provided.
## Cost is per-method: stainless €200, old oak €350, new oak €600.
func ferment(method: String = "") -> String:
	# Use the player's selected method if none is explicitly passed.
	var chosen: String = method if method != "" else FermentationManager.get_selected_method()
	var cost: float    = FermentationManager.get_method_cost(chosen)
	if not WineMarket.spend(cost, "ferment (%s)" % chosen):
		return "Ferment: not enough money — need €%.0f for %s." % [cost, chosen]
	var result: String = FermentationManager.ferment(chosen)
	action_performed.emit(ACTION_FERMENT, -1, -1, result)
	return result


## Buy Land: purchase a locked tile.
## Cost is based on the tile's quality_potential (€500–€1500).
func buy_land(col: int, row: int) -> String:
	var data: TileSimData = VineyardSimulation.get_tile_data(col, row)
	if data == null:
		return "Buy Land (%d,%d): no tile found." % [col, row]
	if data.is_owned:
		return "Buy Land (%d,%d): tile already owned." % [col, row]

	var cost: float = VineyardSimulation.calculate_land_cost(col, row)
	if not WineMarket.spend(cost, "buy land"):
		return "Buy Land (%d,%d): not enough money — need €%.0f, have €%.0f." % [
			col, row, cost, WineMarket.get_money()
		]

	VineyardSimulation.buy_land(col, row)

	var result: String = "Bought tile (%d,%d) for €%.0f.  Money: €%.0f" % [
		col, row, cost, WineMarket.get_money()
	]
	print(result)
	action_performed.emit(ACTION_BUY_LAND, col, row, result)
	return result


## DEV ONLY — Force a planted tile into harvest-ready state for testing.
## Sets ripeness=0.90, sugar=0.75, acidity=0.45, harvest_ready=true.
## Remove or gate behind a debug flag before shipping.
func debug_force_harvest_ready(col: int, row: int) -> String:
	var data: TileSimData = VineyardSimulation.get_tile_data(col, row)
	if data == null:
		return "No tile at (%d,%d)." % [col, row]
	if not data.is_planted:
		return "Force-ready (%d,%d): no vine planted — replant first." % [col, row]

	data.ripeness            = 0.90
	data.sugar_level         = 0.75
	data.acidity_level       = 0.45
	data.harvest_ready       = true
	data.harvested_this_year = false
	# Ensure lifecycle is mature so harvest validation passes.
	if data.lifecycle_stage == "young" or data.lifecycle_stage == "empty":
		data.lifecycle_stage = "mature"
	# Ensure health and productivity are non-zero.
	if data.vine_health <= 0.0:
		data.vine_health = 0.80
	if data.productivity <= 0.0:
		data.productivity = 0.70

	VineyardSimulation.tile_data_changed.emit(data)
	action_performed.emit("debug_force_harvest_ready", col, row, "")

	var result: String = "Forced harvest-ready state at (%d,%d)  ripeness=0.90  sugar=0.75  acidity=0.45" % [col, row]
	print(result)
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


## Returns the cost for a named action from JSON config.
func _action_cost(action_key: String) -> float:
	var cfg: Dictionary   = _action_cfg()
	var raw_costs: Variant = cfg.get("costs", {})
	if not raw_costs is Dictionary:
		return 0.0
	return float((raw_costs as Dictionary).get(action_key, 0.0))
