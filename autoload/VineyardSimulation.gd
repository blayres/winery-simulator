## VineyardSimulation.gd
## Singleton — simulation brain for all vineyard tiles.
##
## Owns all TileSimData instances, initializes terroir, runs season ticks,
## emits tile_data_changed so the visual layer stays in sync.
##
## Single-writer rule: only this autoload writes TileSimData.
## All other systems (visuals, UI, economy) are read-only consumers.
##
## Godot 4.6: uses FastNoiseLite for spatial variation (built-in).
## All config values come from data/simulation/vineyard_sim_config.json.

extends Node

# ─── Signals ──────────────────────────────────────────────────────────────────
## Emitted after a tile's sim data changes (visual layer listens to this).
signal tile_data_changed(data: TileSimData)
## Emitted once after the full grid is initialized.
signal simulation_initialized()

# ─── State ────────────────────────────────────────────────────────────────────
## "col,row" → TileSimData
var _tile_data: Dictionary = {}

## Parsed soil archetypes from soils.json, keyed by soil id.
var _soil_archetypes: Dictionary = {}

## Sim config values.
var _cfg: Dictionary = {}

## Noise generator for spatial humidity/fertility variation.
var _noise: FastNoiseLite = null

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.seed       = randi()

	DataManager.data_loaded.connect(_on_data_loaded)

	# If data is already loaded (DataManager runs before this in autoload order),
	# build archetypes immediately.
	if DataManager.is_loaded("soils") and DataManager.is_loaded("vineyard_sim"):
		_build_archetypes()


# ─── Public API ───────────────────────────────────────────────────────────────

## Initialize simulation data for a grid of [param cols] × [param rows] tiles.
func initialize_grid(cols: int, rows: int) -> void:
	_tile_data.clear()

	if _soil_archetypes.is_empty():
		push_error("VineyardSimulation: archetypes empty — attempting late build.")
		_build_archetypes()
		if _soil_archetypes.is_empty():
			push_error("VineyardSimulation: late build failed. Check soils.json.")
	var noise_scale: float = float(_cfg.get("noise_scale", 0.18))
	_noise.frequency = noise_scale

	for row: int in rows:
		for col: int in cols:
			var data: TileSimData = _create_tile_data(col, row)
			_tile_data[_key(col, row)] = data

	_seed_demo_vines(cols, rows)
	simulation_initialized.emit()
	print("VineyardSimulation: initialized %d tiles." % _tile_data.size())


## Returns the TileSimData for (col, row), or null if not found.
func get_tile_data(col: int, row: int) -> TileSimData:
	var key: String = _key(col, row)
	if _tile_data.has(key):
		var d: Variant = _tile_data[key]
		if d is TileSimData:
			return d
	return null


## Returns all TileSimData instances as an Array.
func get_all_tile_data() -> Array:
	return _tile_data.values()


## Public wrapper for quality recomputation — used by SimDemoSeeder.
func recompute_quality_public(data: TileSimData) -> void:
	_recompute_quality(data)


## Plant a grape variety on a tile. Returns false if already planted.
func plant_vine(col: int, row: int, grape_id: String) -> bool:
	var data: TileSimData = get_tile_data(col, row)
	if data == null or data.is_planted:
		return false
	data.is_planted    = true
	data.grape_variety = grape_id
	data.vine_age      = 0
	data.vine_health   = float(_cfg.get("starting_health", 0.85))
	_recompute_quality(data)
	tile_data_changed.emit(data)
	return true


## Remove a vine from a tile.
func uproot_vine(col: int, row: int) -> void:
	var data: TileSimData = get_tile_data(col, row)
	if data == null or not data.is_planted:
		return
	data.is_planted    = false
	data.grape_variety = ""
	data.vine_age      = 0
	data.vine_health   = 0.0
	_recompute_quality(data)
	tile_data_changed.emit(data)

## Run one simulation tick (called each season by GameManager).
func tick_season() -> void:
	for key: String in _tile_data:
		var raw: Variant = _tile_data[key]
		if not raw is TileSimData:
			continue
		var data: TileSimData = raw
		if data.is_planted:
			_tick_vine(data)
			tile_data_changed.emit(data)


# ─── Private — initialization ─────────────────────────────────────────────────

func _on_data_loaded(key: String) -> void:
	if key == "soils" or key == "vineyard_sim":
		if DataManager.is_loaded("soils") and DataManager.is_loaded("vineyard_sim"):
			_build_archetypes()


func _build_archetypes() -> void:
	_cfg = DataManager.get_data("vineyard_sim")

	var soils_raw: Dictionary = DataManager.get_data("soils")
	var soils_arr: Variant    = soils_raw.get("soils", [])
	if not soils_arr is Array:
		push_error("VineyardSimulation: soils.json 'soils' key is not an Array.")
		return
	var soils: Array = soils_arr
	for i: int in soils.size():
		if not soils[i] is Dictionary:
			continue
		var s: Dictionary = soils[i]
		var sid: String   = str(s.get("id", ""))
		if sid != "":
			_soil_archetypes[sid] = s

	print("VineyardSimulation: archetypes built — soils=%s  cfg_keys=%s" \
			% [str(_soil_archetypes.keys()), str(_cfg.keys())])


func _create_tile_data(col: int, row: int) -> TileSimData:
	var data: TileSimData = TileSimData.new()
	data.grid_col = col
	data.grid_row = row

	# Assign soil type using noise-based spatial clustering.
	data.soil_type = _pick_soil_for(col, row)

	var archetype: Dictionary = _get_archetype(data.soil_type)

	# Base values from soil archetype + small per-tile noise variation.
	var hum_cfg: Dictionary  = _get_cfg_section("humidity")
	var fert_cfg: Dictionary = _get_cfg_section("fertility")

	var noise_val: float = (_noise.get_noise_2d(float(col), float(row)) + 1.0) * 0.5

	data.fertility = clampf(
		float(archetype.get("base_fertility", 0.60)) +
		noise_val * float(fert_cfg.get("variation_strength", 0.10)) - 0.05,
		0.10, 1.00
	)
	data.drainage = float(archetype.get("base_drainage", 0.60))
	data.humidity = clampf(
		float(archetype.get("base_humidity", 0.50)) +
		noise_val * float(hum_cfg.get("variation_strength", 0.12)) - 0.06,
		float(hum_cfg.get("base_min", 0.20)),
		float(hum_cfg.get("base_max", 0.85))
	)
	data.quality_potential = clampf(
		float(archetype.get("quality_modifier", 1.0)) *
		lerp(
			float(_get_vine_cfg("quality_base_min", 0.40)),
			float(_get_vine_cfg("quality_base_max", 1.00)),
			noise_val
		),
		0.10, 1.00
	)

	# Disease risk baseline from humidity.
	var dis_cfg: Dictionary = _get_cfg_section("disease_risk")
	data.disease_risk = clampf(
		float(dis_cfg.get("base", 0.05)) +
		data.humidity * float(dis_cfg.get("humidity_factor", 0.20)),
		0.0, 1.0
	)

	data.is_planted    = false
	data.grape_variety = ""
	data.vine_age      = 0
	data.vine_health   = 0.0
	_recompute_quality(data)
	return data


## Picks a soil type for (col, row) using a second noise layer for clustering.
func _pick_soil_for(col: int, row: int) -> String:
	if _soil_archetypes.is_empty():
		return "limestone_clay"

	# Use a different noise offset to get independent soil clustering.
	var n: float = (_noise.get_noise_2d(float(col) + 100.0, float(row) + 100.0) + 1.0) * 0.5
	var ids: Array = _soil_archetypes.keys()
	var idx: int   = int(n * float(ids.size()))
	idx = clampi(idx, 0, ids.size() - 1)
	return str(ids[idx])


# ─── Private — per-season tick ────────────────────────────────────────────────

func _tick_vine(data: TileSimData) -> void:
	# Age the vine by one season.
	data.vine_age = mini(data.vine_age + 1, int(_get_vine_cfg("max_age", 50)) * 4)

	# Health drifts slightly — future systems (climate, disease) will modify this.
	# For now, healthy vines stay healthy with minor noise.
	var health_drift: float = randf_range(-0.01, 0.005)
	data.vine_health = clampf(
		data.vine_health + health_drift,
		float(_get_vine_cfg("min_health", 0.0)),
		float(_get_vine_cfg("max_health", 1.0))
	)

	# Disease risk nudges with humidity.
	var dis_cfg: Dictionary = _get_cfg_section("disease_risk")
	data.disease_risk = clampf(
		float(dis_cfg.get("base", 0.05)) +
		data.humidity * float(dis_cfg.get("humidity_factor", 0.20)) +
		randf_range(-0.01, 0.01),
		0.0, 1.0
	)

	_recompute_quality(data)


func _recompute_quality(data: TileSimData) -> void:
	if not data.is_planted:
		data.effective_quality = 0.0
		return
	# Effective quality = potential × health factor × age bonus.
	# Age bonus: peaks at ~15 years (60 seasons), then plateaus.
	var age_years: float  = float(data.vine_age) / 4.0
	var age_factor: float = clampf(age_years / 15.0, 0.0, 1.0)
	data.effective_quality = clampf(
		data.quality_potential * data.vine_health * (0.7 + age_factor * 0.3),
		0.0, 1.0
	)


# ─── Private — demo seeding (prototype only) ─────────────────────────────────
## Plants a spread of vines across the grid so the inspector has interesting
## data to show immediately. Remove or replace with player actions later.
func _seed_demo_vines(cols: int, rows: int) -> void:
	SimDemoSeeder.seed_vines(self, cols, rows)


# ─── Private — helpers ────────────────────────────────────────────────────────

func _key(col: int, row: int) -> String:
	return "%d,%d" % [col, row]


func _get_archetype(soil_id: String) -> Dictionary:
	if _soil_archetypes.has(soil_id):
		var a: Variant = _soil_archetypes[soil_id]
		if a is Dictionary:
			return a
	# Fallback to first archetype.
	if not _soil_archetypes.is_empty():
		var first: Variant = _soil_archetypes.values()[0]
		if first is Dictionary:
			return first
	return {}


func _get_cfg_section(section: String) -> Dictionary:
	var raw: Variant = _cfg.get(section, {})
	return raw if raw is Dictionary else {}


func _get_vine_cfg(key: String, default: float) -> float:
	var vine_cfg: Dictionary = _get_cfg_section("vine")
	return float(vine_cfg.get(key, default))
