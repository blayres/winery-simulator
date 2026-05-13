## HarvestManager.gd
## Singleton — owns the grape lot inventory and harvest logic.
##
## Responsibility:
##   - Validates harvest conditions on a tile.
##   - Creates GrapeLot Resources from harvested TileSimData.
##   - Stores all grape lots in memory (no save yet).
##   - Emits harvest_completed so UI and future systems can react.
##   - Resets tile harvest state after a successful harvest.
##
## Architecture:
##   HarvestManager is the ONLY creator of GrapeLot instances.
##   VineyardActionSystem calls harvest() — it never creates lots directly.
##   WineManager (future) will consume lots from get_all_lots().
##
## Grape quality formula:
##   base = ripeness × sugar_balance × acidity_balance
##   modifiers = vine_health × productivity × (1 - disease_risk)
##   quality_potential caps the ceiling
##   Result clamped 0.0–1.0

extends Node

# ─── Signals ──────────────────────────────────────────────────────────────────
signal harvest_completed(lot: GrapeLot)
signal lots_changed(total_lots: int)

# ─── State ────────────────────────────────────────────────────────────────────
var _lots:    Array[GrapeLot] = []
var _next_id: int             = 1

# ─── Public API ───────────────────────────────────────────────────────────────

## Attempt to harvest the tile at (col, row).
## Returns a result string. On success, creates and stores a GrapeLot.
func harvest(col: int, row: int) -> String:
	var data: TileSimData = VineyardSimulation.get_tile_data(col, row)
	if data == null:
		return "Harvest (%d,%d): no tile found." % [col, row]

	# ── Validation ────────────────────────────────────────────────────────
	if not data.is_planted:
		return "Harvest (%d,%d): no vine planted." % [col, row]
	if not data.harvest_ready:
		return "Harvest (%d,%d): not ready — ripeness %.0f%% (need 75%%)." % [
			col, row, data.ripeness * 100.0
		]
	if data.vine_health <= 0.0:
		return "Harvest (%d,%d): vine health is zero — cannot harvest." % [col, row]
	if data.productivity <= 0.0:
		return "Harvest (%d,%d): productivity is zero — cannot harvest." % [col, row]
	if data.harvested_this_year:
		return "Harvest (%d,%d): already harvested this year." % [col, row]

	# ── Create grape lot ──────────────────────────────────────────────────
	var lot: GrapeLot = _create_lot(data)
	_lots.append(lot)
	_next_id += 1

	# ── Update tile state ─────────────────────────────────────────────────
	data.harvest_ready       = false
	data.harvested_this_year = true
	# Ripeness holds at current value — stops increasing until spring reset.
	VineyardSimulation.tile_data_changed.emit(data)

	# ── Signals and logging ───────────────────────────────────────────────
	harvest_completed.emit(lot)
	lots_changed.emit(_lots.size())

	var result: String = "Harvested %s at (%d,%d): quality=%.2f sugar=%.2f acidity=%.2f  [%d lots total]" % [
		lot.grape_variety, col, row,
		lot.estimated_grape_quality, lot.sugar_level, lot.acidity_level,
		_lots.size()
	]
	print(result)
	return result


## Returns all grape lots (read-only array copy).
func get_all_lots() -> Array:
	return _lots.duplicate()


## Returns the total number of lots in inventory.
func get_lot_count() -> int:
	return _lots.size()


## Clears all lots (used for new game / testing).
func clear_lots() -> void:
	_lots.clear()
	lots_changed.emit(0)


## Removes a single lot by id. Used by FermentationManager when consuming a lot.
func remove_lot(lot_id: int) -> void:
	for i: int in _lots.size():
		if _lots[i].lot_id == lot_id:
			_lots.remove_at(i)
			lots_changed.emit(_lots.size())
			return


# ─── Save / Load interface ────────────────────────────────────────────────────

func get_save_data() -> Dictionary:
	var serialized: Array = []
	for lot: GrapeLot in _lots:
		serialized.append({
			"lot_id":                 lot.lot_id,
			"harvest_year":           lot.harvest_year,
			"source_col":             lot.source_col,
			"source_row":             lot.source_row,
			"soil_type":              lot.soil_type,
			"grape_variety":          lot.grape_variety,
			"ripeness":               lot.ripeness,
			"sugar_level":            lot.sugar_level,
			"acidity_level":          lot.acidity_level,
			"vine_health":            lot.vine_health,
			"productivity":           lot.productivity,
			"quality_potential":      lot.quality_potential,
			"disease_risk":           lot.disease_risk,
			"estimated_grape_quality": lot.estimated_grape_quality,
		})
	return { "lots": serialized, "next_id": _next_id }


func load_save_data(data: Dictionary) -> void:
	_lots.clear()
	_next_id = int(data.get("next_id", 1))
	var raw: Variant = data.get("lots", [])
	if not raw is Array:
		return
	var arr: Array = raw
	for i: int in arr.size():
		if not arr[i] is Dictionary:
			continue
		var d: Dictionary = arr[i]
		var lot: GrapeLot = GrapeLot.new()
		lot.lot_id                 = int(d.get("lot_id", 0))
		lot.harvest_year           = int(d.get("harvest_year", 1))
		lot.source_col             = int(d.get("source_col", 0))
		lot.source_row             = int(d.get("source_row", 0))
		lot.soil_type              = str(d.get("soil_type", ""))
		lot.grape_variety          = str(d.get("grape_variety", ""))
		lot.ripeness               = float(d.get("ripeness", 0.0))
		lot.sugar_level            = float(d.get("sugar_level", 0.0))
		lot.acidity_level          = float(d.get("acidity_level", 0.0))
		lot.vine_health            = float(d.get("vine_health", 0.0))
		lot.productivity           = float(d.get("productivity", 0.0))
		lot.quality_potential      = float(d.get("quality_potential", 0.0))
		lot.disease_risk           = float(d.get("disease_risk", 0.0))
		lot.estimated_grape_quality = float(d.get("estimated_grape_quality", 0.0))
		_lots.append(lot)
	lots_changed.emit(_lots.size())


# ─── Private ──────────────────────────────────────────────────────────────────

func _create_lot(data: TileSimData) -> GrapeLot:
	var lot: GrapeLot = GrapeLot.new()
	lot.lot_id         = _next_id
	lot.harvest_year   = TimeManager.current_year
	lot.source_col     = data.grid_col
	lot.source_row     = data.grid_row
	lot.soil_type      = data.soil_type
	lot.grape_variety  = data.grape_variety
	lot.ripeness       = data.ripeness
	lot.sugar_level    = data.sugar_level
	lot.acidity_level  = data.acidity_level
	lot.vine_health    = data.vine_health
	lot.productivity   = data.productivity
	lot.quality_potential = data.quality_potential
	lot.disease_risk   = data.disease_risk
	lot.estimated_grape_quality = _compute_quality(data)
	return lot


## Grape quality formula — additive condition score with soft floors on modifiers.
##
## The old formula multiplied 5+ factors together, compressing the range to 0.05–0.35.
## This formula uses an additive condition score so good ripeness/sugar/acidity
## can produce meaningful quality even with imperfect vine health.
## quality_potential still acts as a hard ceiling.
func _compute_quality(data: TileSimData) -> float:
	# Ripeness timing: peak at 0.75–0.95, penalty outside that window.
	var ripe_score: float
	if data.ripeness < 0.75:
		ripe_score = data.ripeness / 0.75        # underripe penalty
	elif data.ripeness > 0.95:
		ripe_score = 1.0 - (data.ripeness - 0.95) * 3.0  # overripe penalty
	else:
		ripe_score = 1.0                          # ideal window

	# Additive condition score from ripeness, sugar, and acidity.
	# Each contributes independently — a great sugar year can compensate
	# for slightly low acidity.
	var condition: float = ripe_score * 0.35 + data.sugar_level * 0.35 \
			+ data.acidity_level * 0.30

	# Vine health: floor at 0.50 so even stressed vines produce something.
	var health_factor: float = 0.50 + data.vine_health * 0.50

	# Disease: floor at 0.85 — disease hurts but doesn't zero out quality.
	var disease_factor: float = 0.85 + (1.0 - data.disease_risk) * 0.15

	# Productivity: floor at 0.60 — low-yield vines still make decent wine.
	var prod_factor: float = 0.60 + data.productivity * 0.40

	var raw: float = condition * health_factor * disease_factor * prod_factor
	# quality_potential is the hard ceiling (soil + terroir).
	return clampf(raw * data.quality_potential, 0.0, 1.0)
