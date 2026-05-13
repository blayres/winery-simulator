## WineMarket.gd
## Singleton — player economy and wine selling.
##
## Responsibility:
##   - Tracks player_money.
##   - Calculates sale price for a WineBatch.
##   - Executes sales: removes batch from FermentationManager, adds money.
##   - Emits signals for UI and future systems (reputation, critics, etc.).
##
## Price formula:
##   base_per_bottle = 8 + wine_quality × 22        (€8–€30 per bottle)
##   maturity_mult   = stage bonus (peak +20%, declining -10%)
##   aging_mult      = 1 + age_years × 0.04          (+4% per year aged)
##   prestige_mult   = grape variety prestige factor
##   total = base_per_bottle × maturity_mult × aging_mult × prestige_mult × bottles
##
## Architecture:
##   WineMarket is the ONLY place that modifies player_money.
##   UI reads money via get_money() — never writes directly.
##   Future systems (reputation, market events) will add multipliers here.

extends Node

# ─── Signals ──────────────────────────────────────────────────────────────────
signal money_changed(new_amount: float, delta: float)
signal batch_sold(batch_name: String, price: float, new_money: float)

# ─── Constants ────────────────────────────────────────────────────────────────
const STARTING_MONEY: float = 5000.0

# Base price per bottle at quality 0 = €8, quality 1.0 = €30.
const BASE_PRICE_MIN:  float = 8.0
const BASE_PRICE_RANGE: float = 22.0

# Maturity stage price multipliers.
const MATURITY_MULT: Dictionary = {
	"young":      1.00,
	"developing": 1.10,
	"peak":       1.20,
	"declining":  0.90,
}

# Aging bonus per year (4% per year).
const AGING_BONUS_PER_YEAR: float = 0.04

# Grape variety prestige multipliers.
# Higher = more prestigious variety = higher price.
const GRAPE_PRESTIGE: Dictionary = {
	"pinot_noir":  1.20,
	"chardonnay":  1.10,
}
const DEFAULT_PRESTIGE: float = 1.00

# ─── State ────────────────────────────────────────────────────────────────────
var player_money: float = STARTING_MONEY

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	player_money = STARTING_MONEY


# ─── Public API ───────────────────────────────────────────────────────────────

## Returns current player money.
func get_money() -> float:
	return player_money


## Calculate the sale price for a WineBatch without selling it.
func calculate_price(batch: WineBatch) -> float:
	# Base price per bottle from quality.
	var base_per_bottle: float = BASE_PRICE_MIN + batch.wine_quality * BASE_PRICE_RANGE

	# Maturity stage multiplier.
	var maturity_mult: float = float(MATURITY_MULT.get(batch.maturity_stage, 1.0))

	# Aging bonus — older wines command a premium.
	var aging_mult: float = 1.0 + float(batch.age_years) * AGING_BONUS_PER_YEAR

	# Grape variety prestige.
	var prestige: float = float(GRAPE_PRESTIGE.get(batch.grape_variety, DEFAULT_PRESTIGE))

	var total: float = base_per_bottle * maturity_mult * aging_mult * prestige \
			* float(batch.bottles_estimated)
	return maxf(total, 1.0)


## Sell the most recent WineBatch. Returns a result string.
func sell_latest() -> String:
	var batches: Array = FermentationManager.get_all_batches()
	if batches.is_empty():
		return "Sell: no wine batches in cellar."
	var batch: WineBatch = batches[batches.size() - 1]
	return sell_batch(batch.batch_id)


## Sell a specific WineBatch by batch_id. Returns a result string.
func sell_batch(batch_id: int) -> String:
	var batches: Array = FermentationManager.get_all_batches()
	var target: WineBatch = null
	for i: int in batches.size():
		if batches[i] is WineBatch and (batches[i] as WineBatch).batch_id == batch_id:
			target = batches[i]
			break

	if target == null:
		return "Sell: batch #%d not found." % batch_id

	var price: float    = calculate_price(target)
	var old_money: float = player_money
	player_money        += price

	# Remove the sold batch from FermentationManager.
	_remove_batch(target.batch_id)

	money_changed.emit(player_money, price)
	batch_sold.emit(target.wine_name, price, player_money)

	var result: String = "Sold %s Year %d for €%.0f  Money: €%.0f" % [
		target.wine_name, target.vintage_year, price, player_money
	]
	print(result)
	return result


# ─── Save / Load interface ────────────────────────────────────────────────────

func get_save_data() -> Dictionary:
	return { "player_money": player_money }


func load_save_data(data: Dictionary) -> void:
	player_money = float(data.get("player_money", STARTING_MONEY))
	money_changed.emit(player_money, 0.0)


# ─── Private ──────────────────────────────────────────────────────────────────

## Remove a sold batch from FermentationManager's inventory.
func _remove_batch(batch_id: int) -> void:
	FermentationManager.remove_batch(batch_id)
