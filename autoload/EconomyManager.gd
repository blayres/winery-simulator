## EconomyManager.gd
## Singleton — manages all financial state.
##
## Responsibility:
##   - Tracks player funds.
##   - Handles income, expenses, and transactions.
##   - Exposes market pricing logic (driven by JSON config).
##   - Broadcasts financial events for UI and other systems.
##
## Godot 4.6 notes:
##   - _ledger uses untyped Array — JSON deserialization produces untyped arrays.
##   - Dictionary.get() returns Variant; we assign to Variant first, then check type.
##   - warning_threshold is explicitly typed float.

extends Node

# ─── Signals ──────────────────────────────────────────────────────────────────
signal funds_changed(new_amount: float, delta: float)
signal transaction_recorded(transaction: Dictionary)
signal bankruptcy_warning()
signal bankruptcy_occurred()

# ─── State ────────────────────────────────────────────────────────────────────
var funds: float = 0.0

# Untyped Array — JSON deserialization produces untyped arrays.
var _ledger: Array = []

var _economy_config: Dictionary = {}

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	DataManager.data_loaded.connect(_on_data_loaded)
	GameManager.year_advanced.connect(_on_year_advanced)
	GameManager.game_started.connect(_on_game_started)


# ─── Public API ───────────────────────────────────────────────────────────────

## Add funds. [param source] labels the ledger entry.
func earn(amount: float, source: String = "unknown") -> void:
	_apply_transaction(amount, source)


## Deduct funds. Returns false if insufficient.
func spend(amount: float, reason: String = "unknown") -> bool:
	if funds < amount:
		push_warning("EconomyManager: insufficient funds for '%s' (need %.2f, have %.2f)" \
				% [reason, amount, funds])
		return false
	_apply_transaction(-amount, reason)
	return true


func can_afford(amount: float) -> bool:
	return funds >= amount


## Returns the base price for [param item_key] from JSON config.
func get_base_price(item_key: String) -> float:
	var raw_prices: Variant = _economy_config.get("base_prices", {})
	if not raw_prices is Dictionary:
		return 0.0
	var prices: Dictionary = raw_prices
	return float(prices.get(item_key, 0.0))


func get_ledger() -> Array:
	return _ledger.duplicate()


func get_starting_funds() -> float:
	return float(_economy_config.get("starting_funds", 5000.0))


# ─── Private ──────────────────────────────────────────────────────────────────

func _on_data_loaded(key: String) -> void:
	if key == "economy":
		_economy_config = DataManager.get_data("economy")


func _on_game_started() -> void:
	funds = get_starting_funds()
	_ledger.clear()
	funds_changed.emit(funds, 0.0)


func _on_year_advanced(_year: int) -> void:
	_ledger.clear()


func _apply_transaction(delta: float, label: String) -> void:
	funds += delta

	var entry: Dictionary = {
		"label":         label,
		"amount":        delta,
		"balance_after": funds,
		"year":          GameManager.current_year,
		"season":        GameManager.get_season_name(),
	}
	_ledger.append(entry)
	transaction_recorded.emit(entry)
	funds_changed.emit(funds, delta)

	var warning_threshold: float = get_starting_funds() * 0.2
	if funds <= 0.0:
		bankruptcy_occurred.emit()
	elif funds <= warning_threshold:
		bankruptcy_warning.emit()


# ─── Save / Load interface ────────────────────────────────────────────────────

func get_save_data() -> Dictionary:
	return {
		"funds":  funds,
		"ledger": _ledger,
	}


func load_save_data(data: Dictionary) -> void:
	funds = float(data.get("funds", get_starting_funds()))
	var raw_ledger: Variant = data.get("ledger", [])
	_ledger = raw_ledger if raw_ledger is Array else []
	funds_changed.emit(funds, 0.0)
