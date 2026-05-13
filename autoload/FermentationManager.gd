## FermentationManager.gd
## Singleton — fermentation pipeline, wine batch inventory, and aging.
##
## Responsibility:
##   - Receives a GrapeLot and a fermentation method.
##   - Calculates wine profile from grape data + method modifiers.
##   - Creates a WineBatch Resource and stores it in memory.
##   - Removes the consumed GrapeLot from HarvestManager.
##   - Ages all WineBatch objects each year via WineAgingProcessor.
##   - Emits fermentation_completed and batches_changed for UI/economy systems.

extends Node

# ─── Signals ──────────────────────────────────────────────────────────────────
signal fermentation_completed(batch: WineBatch)
signal batches_changed(total_batches: int)
signal aging_tick_completed()

# ─── Constants ────────────────────────────────────────────────────────────────
const METHOD_STAINLESS: String = "stainless_steel"
const METHOD_OLD_OAK:   String = "old_oak"
const METHOD_NEW_OAK:   String = "new_oak"

# Method modifiers: each entry adjusts freshness, complexity, oak, quality_mult.
# All values are additive deltas applied on top of the base grape calculation.
const METHOD_MODIFIERS: Dictionary = {
	"stainless_steel": {
		"freshness_bonus":    0.15,
		"complexity_bonus":   0.00,
		"oak_influence":      0.00,
		"quality_multiplier": 1.00,
		"bottles_multiplier": 1.00,
	},
	"old_oak": {
		"freshness_bonus":    0.05,
		"complexity_bonus":   0.12,
		"oak_influence":      0.25,
		"quality_multiplier": 1.05,
		"bottles_multiplier": 0.95,
	},
	"new_oak": {
		"freshness_bonus":   -0.05,
		"complexity_bonus":   0.22,
		"oak_influence":      0.60,
		"quality_multiplier": 1.10,
		"bottles_multiplier": 0.90,
	},
}

# ─── State ────────────────────────────────────────────────────────────────────
var _batches:  Array[WineBatch] = []
var _next_id:  int              = 1

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	TimeManager.year_changed.connect(_on_year_changed)


# ─── Public API ───────────────────────────────────────────────────────────────

## Ferment the most recent available GrapeLot using [param method].
## Returns a result string. On success, creates a WineBatch.
func ferment(method: String = METHOD_STAINLESS) -> String:
	# Validate method.
	if not METHOD_MODIFIERS.has(method):
		return "Ferment: unknown method '%s'. Use stainless_steel, old_oak, or new_oak." % method

	# Get the most recent lot from HarvestManager.
	var lots: Array = HarvestManager.get_all_lots()
	if lots.is_empty():
		return "Ferment: no grape lots available — harvest first."

	# Use the last lot (most recently harvested).
	var lot: GrapeLot = lots[lots.size() - 1]

	# Create the wine batch.
	var batch: WineBatch = _create_batch(lot, method)
	_batches.append(batch)
	_next_id += 1

	# Remove the consumed lot from HarvestManager.
	# HarvestManager doesn't expose remove_lot() yet — we call clear and re-add
	# all except the consumed one. Simple for prototype scale.
	_consume_lot(lot)

	fermentation_completed.emit(batch)
	batches_changed.emit(_batches.size())

	var abv: float = 8.0 + batch.alcohol_potential * 8.0
	var result: String = (
		"Created WineBatch: %s Year %d  Method: %s  Quality: %.2f  " +
		"Alcohol: %.1f%%  Freshness: %.2f  Complexity: %.2f  Bottles: %d  [%d batches total]"
	) % [
		batch.wine_name, batch.vintage_year, batch.method_label(),
		batch.wine_quality, abv, batch.freshness, batch.complexity,
		batch.bottles_estimated, _batches.size()
	]
	print(result)
	return result


## Ferment a specific lot by lot_id.
func ferment_lot(lot_id: int, method: String = METHOD_STAINLESS) -> String:
	if not METHOD_MODIFIERS.has(method):
		return "Ferment: unknown method '%s'." % method

	var lots: Array = HarvestManager.get_all_lots()
	var target: GrapeLot = null
	for i: int in lots.size():
		if lots[i] is GrapeLot and (lots[i] as GrapeLot).lot_id == lot_id:
			target = lots[i]
			break

	if target == null:
		return "Ferment: lot #%d not found." % lot_id

	var batch: WineBatch = _create_batch(target, method)
	_batches.append(batch)
	_next_id += 1
	_consume_lot(target)

	fermentation_completed.emit(batch)
	batches_changed.emit(_batches.size())

	var abv: float = 8.0 + batch.alcohol_potential * 8.0
	var result: String = (
		"Created WineBatch: %s Year %d  Method: %s  Quality: %.2f  " +
		"Alcohol: %.1f%%  Freshness: %.2f  Complexity: %.2f  Bottles: %d  [%d batches total]"
	) % [
		batch.wine_name, batch.vintage_year, batch.method_label(),
		batch.wine_quality, abv, batch.freshness, batch.complexity,
		batch.bottles_estimated, _batches.size()
	]
	print(result)
	return result


func get_all_batches() -> Array:
	return _batches.duplicate()


func get_batch_count() -> int:
	return _batches.size()


## Remove a single batch by id. Used by WineMarket when a batch is sold.
func remove_batch(batch_id: int) -> void:
	for i: int in _batches.size():
		if _batches[i].batch_id == batch_id:
			_batches.remove_at(i)
			batches_changed.emit(_batches.size())
			return


# ─── Save / Load interface ────────────────────────────────────────────────────

func get_save_data() -> Dictionary:
	var serialized: Array = []
	for b: WineBatch in _batches:
		serialized.append({
			"batch_id":            b.batch_id,
			"wine_name":           b.wine_name,
			"grape_variety":       b.grape_variety,
			"vintage_year":        b.vintage_year,
			"fermentation_method": b.fermentation_method,
			"source_grape_quality": b.source_grape_quality,
			"source_sugar":        b.source_sugar,
			"source_acidity":      b.source_acidity,
			"source_lot_id":       b.source_lot_id,
			"alcohol_potential":   b.alcohol_potential,
			"freshness":           b.freshness,
			"body":                b.body,
			"complexity":          b.complexity,
			"oak_influence":       b.oak_influence,
			"wine_quality":        b.wine_quality,
			"bottles_estimated":   b.bottles_estimated,
			"age_years":           b.age_years,
			"aging_potential":     b.aging_potential,
			"maturity_stage":      b.maturity_stage,
		})
	return { "batches": serialized, "next_id": _next_id }


func load_save_data(data: Dictionary) -> void:
	_batches.clear()
	_next_id = int(data.get("next_id", 1))
	var raw: Variant = data.get("batches", [])
	if not raw is Array:
		return
	var arr: Array = raw
	for i: int in arr.size():
		if not arr[i] is Dictionary:
			continue
		var d: Dictionary = arr[i]
		var b: WineBatch  = WineBatch.new()
		b.batch_id            = int(d.get("batch_id", 0))
		b.wine_name           = str(d.get("wine_name", ""))
		b.grape_variety       = str(d.get("grape_variety", ""))
		b.vintage_year        = int(d.get("vintage_year", 1))
		b.fermentation_method = str(d.get("fermentation_method", "stainless_steel"))
		b.source_grape_quality = float(d.get("source_grape_quality", 0.0))
		b.source_sugar        = float(d.get("source_sugar", 0.0))
		b.source_acidity      = float(d.get("source_acidity", 0.0))
		b.source_lot_id       = int(d.get("source_lot_id", 0))
		b.alcohol_potential   = float(d.get("alcohol_potential", 0.0))
		b.freshness           = float(d.get("freshness", 0.0))
		b.body                = float(d.get("body", 0.0))
		b.complexity          = float(d.get("complexity", 0.0))
		b.oak_influence       = float(d.get("oak_influence", 0.0))
		b.wine_quality        = float(d.get("wine_quality", 0.0))
		b.bottles_estimated   = int(d.get("bottles_estimated", 0))
		b.age_years           = int(d.get("age_years",       0))
		b.aging_potential     = float(d.get("aging_potential", 0.0))
		b.maturity_stage      = str(d.get("maturity_stage",  "young"))
		_batches.append(b)
	batches_changed.emit(_batches.size())


# ─── Private ──────────────────────────────────────────────────────────────────

func _create_batch(lot: GrapeLot, method: String) -> WineBatch:
	var mods: Dictionary = METHOD_MODIFIERS.get(method, {}) as Dictionary
	var b: WineBatch     = WineBatch.new()

	b.batch_id            = _next_id
	b.grape_variety       = lot.grape_variety
	b.vintage_year        = lot.harvest_year
	b.fermentation_method = method
	b.source_grape_quality = lot.estimated_grape_quality
	b.source_sugar        = lot.sugar_level
	b.source_acidity      = lot.acidity_level
	b.source_lot_id       = lot.lot_id

	# Wine name: "Grape Variety Year" e.g. "Pinot Noir 2"
	var variety_display: String = lot.grape_variety.replace("_", " ").capitalize()
	b.wine_name = "%s %d" % [variety_display, lot.harvest_year]

	# ── Alcohol potential — from sugar ────────────────────────────────────
	# Sugar 0.20 (base) → ~0.0 alcohol; sugar 0.90 → ~1.0 alcohol potential.
	b.alcohol_potential = clampf((lot.sugar_level - 0.15) / 0.75, 0.0, 1.0)

	# ── Freshness — from acidity + method ─────────────────────────────────
	var freshness_bonus: float = float(mods.get("freshness_bonus", 0.0))
	b.freshness = clampf(lot.acidity_level * 0.8 + freshness_bonus, 0.0, 1.0)

	# ── Body — from ripeness, productivity, and grape quality ─────────────
	b.body = clampf(
		lot.ripeness * 0.5 + lot.productivity * 0.3 + lot.estimated_grape_quality * 0.2,
		0.0, 1.0
	)

	# ── Complexity — from grape quality + method ──────────────────────────
	var complexity_bonus: float = float(mods.get("complexity_bonus", 0.0))
	b.complexity = clampf(lot.estimated_grape_quality * 0.75 + complexity_bonus, 0.0, 1.0)

	# ── Oak influence — purely from method ────────────────────────────────
	b.oak_influence = clampf(float(mods.get("oak_influence", 0.0)), 0.0, 1.0)

	# ── Wine quality — weighted combination ──────────────────────────────
	var quality_mult: float = float(mods.get("quality_multiplier", 1.0))
	var raw_quality: float  = (
		lot.estimated_grape_quality * 0.40 +
		b.freshness                 * 0.20 +
		b.body                      * 0.15 +
		b.complexity                * 0.25
	)
	b.wine_quality = clampf(raw_quality * quality_mult, 0.0, 1.0)

	# ── Bottle estimate — productivity × method multiplier ────────────────
	var bottles_mult: float = float(mods.get("bottles_multiplier", 1.0))
	# Base: 400 bottles per tile at full productivity.
	b.bottles_estimated = int(400.0 * lot.productivity * bottles_mult)
	b.bottles_estimated = maxi(b.bottles_estimated, 12)   # minimum 12 bottles

	# ── Aging potential — computed last (needs all other fields set) ──────
	WineAgingProcessor.compute_aging_potential(b)

	return b


## Remove a consumed lot from HarvestManager's inventory.
func _consume_lot(lot: GrapeLot) -> void:
	HarvestManager.remove_lot(lot.lot_id)


# ─── Private — yearly aging ───────────────────────────────────────────────────

func _on_year_changed(_year: int) -> void:
	if _batches.is_empty():
		return

	var counts: Dictionary = {
		"young": 0, "developing": 0, "peak": 0, "declining": 0
	}

	for i: int in _batches.size():
		var b: WineBatch = _batches[i]
		WineAgingProcessor.tick_year(b)
		var stage: String = b.maturity_stage
		if counts.has(stage):
			counts[stage] = int(counts[stage]) + 1

	batches_changed.emit(_batches.size())
	aging_tick_completed.emit()

	print("Wine Aging: %d batch%s aged.  %d young, %d developing, %d peak, %d declining" % [
		_batches.size(),
		"es" if _batches.size() != 1 else "",
		int(counts["young"]), int(counts["developing"]),
		int(counts["peak"]),  int(counts["declining"])
	])
