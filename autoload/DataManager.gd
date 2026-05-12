## DataManager.gd
## Singleton — loaded first in autoload order.
##
## Responsibility: Central JSON loading pipeline.
## All other managers pull their config through DataManager.
## This keeps file I/O in one place and makes data easy to mock/swap.
##
## Architecture note:
##   Managers do NOT load their own JSON files.
##   They call DataManager.get_data("grapes") etc.
##   This decouples file paths from business logic.
##
## Godot 4.6 notes:
##   - get_data() returns Dictionary (not Variant) so callers never need to cast.
##   - FILE_REGISTRY values are String — always access via String cast to avoid
##     Variant inference issues in _load_file().

extends Node

# ─── Internal cache ───────────────────────────────────────────────────────────
var _cache: Dictionary = {}

const DATA_ROOT: String = "res://data/"

# Registry: logical key → path relative to DATA_ROOT.
# Add new data files here only — no other code changes needed.
const FILE_REGISTRY: Dictionary = {
	"grapes":   "grapes/grapes.json",
	"soils":    "terroir/soils.json",
	"climate":  "climate/climate_presets.json",
	"events":   "events/events.json",
	"wines":    "wines/wine_profiles.json",
	"economy":  "economy/economy_config.json",
	"regions":  "regions/regions.json",
	"upgrades": "upgrades/upgrades.json",
}

# ─── Signals ──────────────────────────────────────────────────────────────────
signal data_loaded(key: String)
signal data_load_failed(key: String, error: String)

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	for key: String in FILE_REGISTRY:
		_load_file(key)


# ─── Public API ───────────────────────────────────────────────────────────────

## Returns the parsed Dictionary for [param key], or {} on failure.
## Returns Dictionary (not Variant) so callers never need to cast.
func get_data(key: String) -> Dictionary:
	if _cache.has(key):
		var cached: Variant = _cache[key]
		if cached is Dictionary:
			return cached as Dictionary
	push_warning("DataManager: key '%s' not found or not a Dictionary." % key)
	return {}


## Returns an Array for keys whose JSON root is an Array (rare — prefer Dictionary roots).
func get_array(key: String) -> Array:
	if _cache.has(key):
		var cached: Variant = _cache[key]
		if cached is Array:
			return cached as Array
	push_warning("DataManager: key '%s' not found or not an Array." % key)
	return []


## Force-reload a specific key from disk (useful for hot-reload in dev).
func reload(key: String) -> void:
	_load_file(key)


## Returns true if the key was loaded successfully.
func is_loaded(key: String) -> bool:
	return _cache.has(key)


# ─── Private ──────────────────────────────────────────────────────────────────

func _load_file(key: String) -> void:
	if not FILE_REGISTRY.has(key):
		push_error("DataManager: no registry entry for key '%s'." % key)
		data_load_failed.emit(key, "unregistered key")
		return

	# Explicit String cast — FILE_REGISTRY values are Variant at compile time.
	var rel_path: String = str(FILE_REGISTRY[key])
	var full_path: String = DATA_ROOT + rel_path

	var file: FileAccess = FileAccess.open(full_path, FileAccess.READ)
	if file == null:
		var err_msg: String = "file not found: %s" % full_path
		push_warning("DataManager: %s" % err_msg)
		data_load_failed.emit(key, err_msg)
		return

	var raw: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(raw)
	if parsed == null:
		var err_msg: String = "JSON parse error in: %s" % full_path
		push_error("DataManager: %s" % err_msg)
		data_load_failed.emit(key, err_msg)
		return

	_cache[key] = parsed
	data_loaded.emit(key)
