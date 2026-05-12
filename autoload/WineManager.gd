## WineManager.gd
## Singleton — manages wine creation, aging, and inventory.
##
## Responsibility:
##   - Stores the player's wine inventory (cellar).
##   - Handles wine crafting (grape → wine) using JSON-defined profiles.
##   - Manages aging progression per year.
##   - Generates wine descriptors (feel language, not raw stats).
##
## Godot 4.6 notes:
##   - cellar uses untyped Array — JSON deserialization produces untyped arrays.
##   - Dictionary.get() returns Variant; assign to Variant first, then type-check.
##   - quality_mult and age_bonus are explicitly typed float.
##   - _pick_descriptors returns untyped Array to match JSON pool type.

extends Node

# ─── Signals ──────────────────────────────────────────────────────────────────
signal wine_crafted(wine_entry: Dictionary)
signal wine_aged(wine_id: String, new_age: int)
signal wine_sold(wine_id: String, price: float)
signal inventory_changed()

# ─── State ────────────────────────────────────────────────────────────────────
# Untyped Array — JSON deserialization and save/load produce untyped arrays.
var cellar: Array = []

var _next_id:   int        = 1
var _wine_data: Dictionary = {}

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	DataManager.data_loaded.connect(_on_data_loaded)
	GameManager.year_advanced.connect(_on_year_advanced)


# ─── Public API ───────────────────────────────────────────────────────────────

## Craft a new wine entry.
## [param profile_id] maps to a wine profile in JSON.
## [param quality_score] is 0–100, computed by the harvest system.
## [param quantity] is the number of bottles produced.
func craft_wine(profile_id: String, quality_score: float, quantity: int) -> Dictionary:
	var profile: Dictionary = _get_profile(profile_id)
	if profile.is_empty():
		push_error("WineManager: unknown profile_id '%s'" % profile_id)
		return {}

	var entry: Dictionary = {
		"id":            "wine_%d" % _next_id,
		"profile_id":    profile_id,
		"name":          str(profile.get("name", profile_id)),
		"vintage_year":  GameManager.current_year,
		"age":           0,
		"quality_score": clampf(quality_score, 0.0, 100.0),
		"quantity":      quantity,
		"descriptors":   _pick_descriptors(profile, quality_score),
	}

	_next_id += 1
	cellar.append(entry)
	wine_crafted.emit(entry)
	inventory_changed.emit()
	return entry


## Sell [param quantity] bottles by wine id. Returns revenue, or 0.0 on failure.
func sell_wine(wine_id: String, quantity: int) -> float:
	var idx: int = _find_entry_index(wine_id)
	if idx == -1:
		push_warning("WineManager: wine_id '%s' not found." % wine_id)
		return 0.0

	if not cellar[idx] is Dictionary:
		return 0.0
	var entry: Dictionary = cellar[idx]
	var available: int    = int(entry.get("quantity", 0))

	if quantity > available:
		push_warning("WineManager: requested %d bottles but only %d available." \
				% [quantity, available])
		quantity = available

	var price: float = _calculate_sale_price(entry, quantity)
	entry["quantity"] = available - quantity

	if int(entry["quantity"]) <= 0:
		cellar.remove_at(idx)

	EconomyManager.earn(price, "wine_sale")
	wine_sold.emit(wine_id, price)
	inventory_changed.emit()
	return price


func get_cellar() -> Array:
	return cellar.duplicate()


# ─── Private ──────────────────────────────────────────────────────────────────

func _on_data_loaded(key: String) -> void:
	if key == "wines":
		_wine_data = DataManager.get_data("wines")


func _on_year_advanced(_year: int) -> void:
	for i: int in cellar.size():
		if not cellar[i] is Dictionary:
			continue
		var entry: Dictionary = cellar[i]
		var new_age: int = int(entry.get("age", 0)) + 1
		entry["age"] = new_age
		wine_aged.emit(str(entry.get("id", "")), new_age)


func _get_profile(profile_id: String) -> Dictionary:
	var raw_profiles: Variant = _wine_data.get("profiles", [])
	if not raw_profiles is Array:
		return {}
	var profiles: Array = raw_profiles
	for i: int in profiles.size():
		if not profiles[i] is Dictionary:
			continue
		var p: Dictionary = profiles[i]
		if str(p.get("id", "")) == profile_id:
			return p
	return {}


## Picks up to 3 flavor descriptors based on quality tier.
func _pick_descriptors(profile: Dictionary, quality: float) -> Array:
	var raw_tiers: Variant = profile.get("descriptor_tiers", {})
	if not raw_tiers is Dictionary:
		return []
	var tiers: Dictionary = raw_tiers

	var tier_key: String
	if quality >= 85.0:
		tier_key = "exceptional"
	elif quality >= 70.0:
		tier_key = "good"
	elif quality >= 50.0:
		tier_key = "average"
	else:
		tier_key = "poor"

	var raw_pool: Variant = tiers.get(tier_key, [])
	if not raw_pool is Array:
		return []
	var pool: Array = raw_pool
	if pool.is_empty():
		return []

	pool.shuffle()
	return pool.slice(0, mini(3, pool.size()))


## Price = base × quality_multiplier × age_bonus × quantity.
func _calculate_sale_price(entry: Dictionary, quantity: int) -> float:
	var base: float         = EconomyManager.get_base_price("wine_bottle")
	var quality_mult: float = 1.0 + (float(entry.get("quality_score", 50.0)) - 50.0) / 100.0
	var age_bonus: float    = float(entry.get("age", 0)) * 0.05
	return base * quality_mult * (1.0 + age_bonus) * float(quantity)


func _find_entry_index(wine_id: String) -> int:
	for i: int in cellar.size():
		if not cellar[i] is Dictionary:
			continue
		var entry: Dictionary = cellar[i]
		if str(entry.get("id", "")) == wine_id:
			return i
	return -1


# ─── Save / Load interface ────────────────────────────────────────────────────

func get_save_data() -> Dictionary:
	return {
		"cellar":  cellar,
		"next_id": _next_id,
	}


func load_save_data(data: Dictionary) -> void:
	var raw_cellar: Variant = data.get("cellar", [])
	cellar   = raw_cellar if raw_cellar is Array else []
	_next_id = int(data.get("next_id", 1))
	inventory_changed.emit()
