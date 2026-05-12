## ClimateManager.gd
## Singleton — weekly climate simulation.
##
## Subscribes to TimeManager.week_changed to generate new weather values
## each week. Picks a yearly profile at year start (weighted random).
## Derives a readable condition label and a 0–1 weekly_climate_score.
## Emits climate_updated every week for downstream systems.
##
## Data: climate_presets.json (seasonal base values)
##       climate_conditions.json (condition thresholds, score weights)

extends Node

# ─── Signals ──────────────────────────────────────────────────────────────────
## Emitted every week after new climate values are generated.
signal climate_updated(state: Dictionary)
## Emitted when the yearly profile changes (new year or event override).
signal profile_changed(profile_id: String)

# ─── Public state — read by UI and future systems ─────────────────────────────
var temperature:          float  = 15.0   # °C
var rainfall:             float  = 40.0   # mm
var humidity:             float  = 0.50   # 0–1
var wind:                 float  = 10.0   # km/h
var frost_risk:           float  = 0.0    # 0–1
var condition:            String = "Clear"
var weekly_climate_score: float  = 1.0    # 0–1, 1 = ideal
var active_profile_id:    String = ""

# ─── Private ──────────────────────────────────────────────────────────────────
var _profiles:    Array      = []   # parsed from climate_presets.json
var _conditions:  Array      = []   # parsed from climate_conditions.json
var _score_cfg:   Dictionary = {}   # weekly_score section
var _data_ready:  bool       = false

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	DataManager.data_loaded.connect(_on_data_loaded)
	TimeManager.week_changed.connect(_on_week_changed)
	TimeManager.year_changed.connect(_on_year_changed)

	# Data may already be loaded if DataManager ran before us.
	if DataManager.is_loaded("climate") and DataManager.is_loaded("climate_conditions"):
		_load_data()


# ─── Public API ───────────────────────────────────────────────────────────────

## Returns all current climate values as a Dictionary.
## Shape matches the climate_updated signal payload.
func get_current_state() -> Dictionary:
	return {
		"temperature":          temperature,
		"rainfall":             rainfall,
		"humidity":             humidity,
		"wind":                 wind,
		"frost_risk":           frost_risk,
		"condition":            condition,
		"weekly_climate_score": weekly_climate_score,
		"profile_id":           active_profile_id,
	}


## Force-set a profile (used by EventManager for climate event overrides).
func set_profile(profile_id: String) -> void:
	active_profile_id = profile_id
	profile_changed.emit(profile_id)


# ─── Save / Load interface ────────────────────────────────────────────────────

func get_save_data() -> Dictionary:
	return {
		"active_profile_id": active_profile_id,
		"temperature":       temperature,
		"rainfall":          rainfall,
		"humidity":          humidity,
		"wind":              wind,
		"frost_risk":        frost_risk,
		"condition":         condition,
	}


func load_save_data(data: Dictionary) -> void:
	active_profile_id = str(data.get("active_profile_id", ""))
	temperature       = float(data.get("temperature", 15.0))
	rainfall          = float(data.get("rainfall",    40.0))
	humidity          = float(data.get("humidity",     0.5))
	wind              = float(data.get("wind",         10.0))
	frost_risk        = float(data.get("frost_risk",   0.0))
	condition         = str(data.get("condition",      "Clear"))
	weekly_climate_score = _compute_score()
	climate_updated.emit(get_current_state())


# ─── Private — data loading ───────────────────────────────────────────────────

func _on_data_loaded(key: String) -> void:
	if key == "climate" or key == "climate_conditions":
		if DataManager.is_loaded("climate") and DataManager.is_loaded("climate_conditions"):
			_load_data()


func _load_data() -> void:
	var raw_presets: Dictionary    = DataManager.get_data("climate")
	var raw_conditions: Dictionary = DataManager.get_data("climate_conditions")

	var raw_p: Variant = raw_presets.get("profiles", [])
	_profiles = raw_p if raw_p is Array else []

	var raw_c: Variant = raw_conditions.get("conditions", [])
	_conditions = raw_c if raw_c is Array else []

	var raw_s: Variant = raw_conditions.get("weekly_score", {})
	_score_cfg = raw_s if raw_s is Dictionary else {}

	_data_ready = true

	# Pick initial profile for year 1.
	_pick_yearly_profile()
	# Generate initial week values.
	_generate_weekly_values(TimeManager.current_season)


# ─── Private — time signal handlers ──────────────────────────────────────────

func _on_week_changed(_year: int, season: int, _week: int) -> void:
	if not _data_ready:
		return
	_generate_weekly_values(season)


func _on_year_changed(_year: int) -> void:
	if not _data_ready:
		return
	_pick_yearly_profile()


# ─── Private — profile selection ─────────────────────────────────────────────

func _pick_yearly_profile() -> void:
	if _profiles.is_empty():
		return

	var total: float = 0.0
	for i: int in _profiles.size():
		if not _profiles[i] is Dictionary:
			continue
		total += float((_profiles[i] as Dictionary).get("weight", 1.0))

	var roll: float = randf() * total
	var cum:  float = 0.0
	for i: int in _profiles.size():
		if not _profiles[i] is Dictionary:
			continue
		var p: Dictionary = _profiles[i]
		cum += float(p.get("weight", 1.0))
		if roll <= cum:
			set_profile(str(p.get("id", "")))
			return

	if _profiles[0] is Dictionary:
		set_profile(str((_profiles[0] as Dictionary).get("id", "")))


# ─── Private — weekly generation ─────────────────────────────────────────────

func _generate_weekly_values(season_idx: int) -> void:
	var base: Dictionary = _get_season_base(season_idx)
	if base.is_empty():
		return

	# Apply per-week variance around the seasonal base.
	temperature = _vary(float(base.get("temperature", 15.0)),
						float(base.get("temp_variance",  3.0)))
	rainfall    = maxf(0.0, _vary(float(base.get("rainfall",  40.0)),
						float(base.get("rainfall_variance", 15.0))))
	humidity    = clampf(_vary(float(base.get("humidity",  0.50)),
						float(base.get("humidity_variance", 0.08))), 0.0, 1.0)
	wind        = maxf(0.0, _vary(float(base.get("wind",  10.0)),
						float(base.get("wind_variance",  5.0))))
	frost_risk  = float(base.get("frost_risk", 0.0))

	condition            = _derive_condition()
	weekly_climate_score = _compute_score()

	var state: Dictionary = get_current_state()
	climate_updated.emit(state)

	# Clean console summary every week.
	print("Climate: %s W%d — %.0f°C, rain %.0fmm, hum %d%%, wind %.0fkm/h — %s  (score %.2f)" % [
		TimeManager.get_season_name(),
		TimeManager.current_week,
		temperature, rainfall,
		int(humidity * 100.0), wind,
		condition, weekly_climate_score
	])


func _get_season_base(season_idx: int) -> Dictionary:
	if active_profile_id.is_empty() or _profiles.is_empty():
		return {}

	var season_key: String = _season_key(season_idx)

	for i: int in _profiles.size():
		if not _profiles[i] is Dictionary:
			continue
		var p: Dictionary = _profiles[i]
		if str(p.get("id", "")) != active_profile_id:
			continue
		var raw_seasons: Variant = p.get("seasons", {})
		if not raw_seasons is Dictionary:
			return {}
		var seasons: Dictionary = raw_seasons
		var raw_base: Variant   = seasons.get(season_key, {})
		return raw_base if raw_base is Dictionary else {}

	return {}


# ─── Private — condition derivation ──────────────────────────────────────────

## Evaluates condition rules in order — first match wins.
func _derive_condition() -> String:
	for i: int in _conditions.size():
		if not _conditions[i] is Dictionary:
			continue
		var c: Dictionary = _conditions[i]
		var rule: String  = str(c.get("rule", ""))
		var thresh: float = float(c.get("threshold", 0.0))
		var label: String = str(c.get("label", "Clear"))

		match rule:
			"frost_risk_above": if frost_risk  >= thresh: return label
			"temp_above":       if temperature >= thresh: return label
			"wind_above":       if wind        >= thresh: return label
			"rainfall_above":   if rainfall    >= thresh: return label
			"humidity_above":   if humidity    >= thresh: return label
			"rainfall_below":   if rainfall    <  thresh: return label
			"default":          return label

	return "Clear"


# ─── Private — score computation ─────────────────────────────────────────────

## Returns 0–1 score: 1.0 = ideal growing conditions, 0.0 = very poor.
func _compute_score() -> float:
	var score: float = 1.0

	var t_min: float = float(_score_cfg.get("ideal_temp_min",     15.0))
	var t_max: float = float(_score_cfg.get("ideal_temp_max",     25.0))
	var r_min: float = float(_score_cfg.get("ideal_rainfall_min", 20.0))
	var r_max: float = float(_score_cfg.get("ideal_rainfall_max", 55.0))
	var h_min: float = float(_score_cfg.get("ideal_humidity_min",  0.35))
	var h_max: float = float(_score_cfg.get("ideal_humidity_max",  0.65))

	# Penalise deviation from ideal ranges.
	if temperature < t_min:
		score -= (t_min - temperature) / t_min * 0.3
	elif temperature > t_max:
		score -= (temperature - t_max) / t_max * 0.3

	if rainfall < r_min:
		score -= (r_min - rainfall) / r_min * 0.2
	elif rainfall > r_max:
		score -= (rainfall - r_max) / r_max * 0.15

	if humidity < h_min:
		score -= (h_min - humidity) / h_min * 0.15
	elif humidity > h_max:
		score -= (humidity - h_max) / h_max * 0.15

	# Hard penalties for extreme conditions.
	if frost_risk >= 0.50:
		score -= float(_score_cfg.get("frost_penalty",    0.40))
	if temperature >= 32.0:
		score -= float(_score_cfg.get("heatwave_penalty", 0.30))
	if rainfall < 10.0:
		score -= float(_score_cfg.get("drought_penalty",  0.25))

	return clampf(score, 0.0, 1.0)


# ─── Private — helpers ────────────────────────────────────────────────────────

func _vary(base: float, variance: float) -> float:
	return base + randf_range(-variance, variance)


func _season_key(season_idx: int) -> String:
	match season_idx:
		0: return "spring"
		1: return "summer"
		2: return "autumn"
		3: return "winter"
	return "spring"
