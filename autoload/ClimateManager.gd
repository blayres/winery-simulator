## ClimateManager.gd
## Singleton — manages all climate and weather state.
##
## Responsibility:
##   - Holds the active climate profile for the current year.
##   - Generates seasonal weather events from JSON-defined presets.
##   - Exposes current conditions to other systems (WineManager, EventManager).
##
## Architecture note:
##   Climate data lives in data/climate/climate_presets.json — never hardcoded.
##   This manager only processes and exposes that data.
##
## Godot 4.6 notes:
##   - Dictionary.get() returns Variant. We assign to Variant locals first,
##     then check type before using as a typed value. This avoids invalid cast errors.
##   - season_key is explicitly typed String.
##   - Autoload names (DataManager, GameManager) resolve as global singletons.

extends Node

# ─── Signals ──────────────────────────────────────────────────────────────────
signal climate_profile_changed(profile_id: String)
signal weather_event_triggered(event_data: Dictionary)
signal season_conditions_updated(conditions: Dictionary)

# ─── State ────────────────────────────────────────────────────────────────────
var active_profile_id:  String     = ""
var current_conditions: Dictionary = {}

var _climate_data: Dictionary = {}

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	DataManager.data_loaded.connect(_on_data_loaded)
	GameManager.season_changed.connect(_on_season_changed)
	GameManager.year_advanced.connect(_on_year_advanced)


# ─── Public API ───────────────────────────────────────────────────────────────

func get_current_conditions() -> Dictionary:
	return current_conditions.duplicate()


## Returns the active climate profile Dictionary, or {} if not set.
func get_active_profile() -> Dictionary:
	if _climate_data.is_empty() or active_profile_id.is_empty():
		return {}
	var raw_profiles: Variant = _climate_data.get("profiles", [])
	if not raw_profiles is Array:
		return {}
	var profiles: Array = raw_profiles
	for i: int in profiles.size():
		if not profiles[i] is Dictionary:
			continue
		var profile: Dictionary = profiles[i]
		if str(profile.get("id", "")) == active_profile_id:
			return profile
	return {}


## Manually override the climate profile (used by EventManager effects).
func set_profile(profile_id: String) -> void:
	active_profile_id = profile_id
	climate_profile_changed.emit(profile_id)


# ─── Private ──────────────────────────────────────────────────────────────────

func _on_data_loaded(key: String) -> void:
	if key == "climate":
		_climate_data = DataManager.get_data("climate")
		_pick_yearly_profile()


func _on_year_advanced(_year: int) -> void:
	_pick_yearly_profile()


func _on_season_changed(season: GameManager.Season) -> void:
	_resolve_season_conditions(season)


## Weighted-random selection of a climate profile for the new year.
func _pick_yearly_profile() -> void:
	if _climate_data.is_empty():
		return
	var raw_profiles: Variant = _climate_data.get("profiles", [])
	if not raw_profiles is Array:
		return
	var profiles: Array = raw_profiles
	if profiles.is_empty():
		return

	var total_weight: float = 0.0
	for i: int in profiles.size():
		if not profiles[i] is Dictionary:
			continue
		var p: Dictionary = profiles[i]
		total_weight += float(p.get("weight", 1.0))

	var roll: float      = randf() * total_weight
	var cumulative: float = 0.0
	for i: int in profiles.size():
		if not profiles[i] is Dictionary:
			continue
		var p: Dictionary = profiles[i]
		cumulative += float(p.get("weight", 1.0))
		if roll <= cumulative:
			set_profile(str(p.get("id", "")))
			return

	# Fallback: first valid profile.
	if profiles[0] is Dictionary:
		var first: Dictionary = profiles[0]
		set_profile(str(first.get("id", "")))


## Resolves numeric conditions for the given season from the active profile.
func _resolve_season_conditions(season: GameManager.Season) -> void:
	var profile: Dictionary = get_active_profile()
	if profile.is_empty():
		return

	# Explicit String — GameManager.get_season_name_for() returns String.
	var season_key: String = GameManager.get_season_name_for(season).to_lower()

	var raw_seasons: Variant = profile.get("seasons", {})
	var seasons_data: Dictionary = raw_seasons if raw_seasons is Dictionary else {}

	var raw_base: Variant = seasons_data.get(season_key, {})
	var base: Dictionary = raw_base if raw_base is Dictionary else {}

	current_conditions = {
		"temperature": _vary(float(base.get("temperature", 15.0)), 2.0),
		"rainfall":    _vary(float(base.get("rainfall",    50.0)), 10.0),
		"humidity":    _vary(float(base.get("humidity",     0.5)), 0.05),
		"frost_risk":  float(base.get("frost_risk", 0.0)),
	}

	season_conditions_updated.emit(current_conditions)


func _vary(base: float, range_val: float) -> float:
	return base + randf_range(-range_val, range_val)


# ─── Save / Load interface ────────────────────────────────────────────────────

func get_save_data() -> Dictionary:
	return {
		"active_profile_id":  active_profile_id,
		"current_conditions": current_conditions,
	}


func load_save_data(data: Dictionary) -> void:
	active_profile_id = str(data.get("active_profile_id", ""))
	var raw_cond: Variant = data.get("current_conditions", {})
	current_conditions = raw_cond if raw_cond is Dictionary else {}
