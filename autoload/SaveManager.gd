## SaveManager.gd
## Singleton — handles all save/load operations.
##
## Responsibility:
##   - Serializes game state to disk (JSON).
##   - Deserializes and restores game state on load.
##   - Manages save slots.
##
## Architecture note:
##   SaveManager does NOT know about gameplay logic.
##   It calls get_save_data() / load_save_data() on each manager via Node reference.
##   Adding a new manager only requires adding its name to MANAGER_KEYS.
##
## Godot 4.6 notes:
##   - get_node_or_null returns Node (nullable) — null-checked before use.
##   - node.call() used instead of direct method calls to avoid typed reference issues.
##   - version is explicitly typed int.
##   - All path variables are explicitly typed String.

extends Node

# ─── Signals ──────────────────────────────────────────────────────────────────
signal save_completed(slot: int)
signal load_completed(slot: int)
signal save_failed(slot: int, error: String)
signal load_failed(slot: int, error: String)

# ─── Constants ────────────────────────────────────────────────────────────────
const SAVE_DIR:     String = "user://saves/"
const SAVE_VERSION: int    = 1

# Ordered list of [manager_autoload_name, save_key] pairs.
# Using explicit key mapping avoids ambiguity with the to_lower().replace() derivation
# (e.g. "WineMarket" has no "manager" suffix, "VineyardSimulation" is not a "Manager").
const MANAGER_KEYS: Array[String] = [
	"TimeManager",
	"WineMarket",
	"HarvestManager",
	"FermentationManager",
	"VineyardSimulation",
]

# Explicit save-key overrides for managers whose name doesn't follow the
# "strip 'manager' suffix" convention.
const KEY_OVERRIDES: Dictionary = {
	"WineMarket":         "winemarket",
	"VineyardSimulation": "vineyardsimulation",
}

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	_ensure_save_dir()


# ─── Public API ───────────────────────────────────────────────────────────────

func save_game(slot: int = 0) -> void:
	var save_data: Dictionary = {
		"version":   SAVE_VERSION,
		"timestamp": Time.get_unix_time_from_system(),
	}

	for manager_name: String in MANAGER_KEYS:
		var data_key: String = _key_for(manager_name)
		save_data[data_key] = _collect_save_data(manager_name)

	var path: String       = _slot_path(slot)
	var file: FileAccess   = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		var err: String = "could not open file for writing: %s" % path
		push_error("SaveManager: %s" % err)
		save_failed.emit(slot, err)
		return

	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()
	save_completed.emit(slot)


func load_game(slot: int = 0) -> void:
	var path: String     = _slot_path(slot)
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		var err: String = "save file not found: %s" % path
		push_warning("SaveManager: %s" % err)
		load_failed.emit(slot, err)
		return

	var raw: String     = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(raw)
	if parsed == null or not (parsed is Dictionary):
		var err: String = "corrupt or invalid save file at: %s" % path
		push_error("SaveManager: %s" % err)
		load_failed.emit(slot, err)
		return

	var data: Dictionary = parsed
	var version: int     = int(data.get("version", 0))
	if version < SAVE_VERSION:
		data = _migrate(data, version)

	_distribute_save_data(data)
	load_completed.emit(slot)


func save_exists(slot: int = 0) -> bool:
	return FileAccess.file_exists(_slot_path(slot))


func delete_save(slot: int = 0) -> void:
	var path: String = _slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


# ─── Private ──────────────────────────────────────────────────────────────────

func _slot_path(slot: int) -> String:
	return SAVE_DIR + "save_%d.json" % slot


func _ensure_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func _collect_save_data(manager_name: String) -> Dictionary:
	var node: Node = get_node_or_null("/root/" + manager_name)
	if node == null:
		push_warning("SaveManager: manager '%s' not found." % manager_name)
		return {}
	if not node.has_method("get_save_data"):
		return {}
	var result: Variant = node.call("get_save_data")
	if result is Dictionary:
		return result
	return {}


func _distribute_save_data(data: Dictionary) -> void:
	for manager_name: String in MANAGER_KEYS:
		var data_key: String      = _key_for(manager_name)
		var raw: Variant          = data.get(data_key, {})
		var manager_data: Dictionary = raw if raw is Dictionary else {}
		_restore_manager(manager_name, manager_data)


func _restore_manager(manager_name: String, manager_data: Dictionary) -> void:
	var node: Node = get_node_or_null("/root/" + manager_name)
	if node == null or not node.has_method("load_save_data"):
		return
	node.call("load_save_data", manager_data)


func _migrate(data: Dictionary, from_version: int) -> Dictionary:
	push_warning("SaveManager: migrating save from v%d to v%d." % [from_version, SAVE_VERSION])
	# Add version-specific migration logic here as the game evolves.
	return data


## Returns the save-file key for a manager name.
## Uses KEY_OVERRIDES for non-standard names, otherwise strips "manager" suffix.
func _key_for(manager_name: String) -> String:
	if KEY_OVERRIDES.has(manager_name):
		return str(KEY_OVERRIDES[manager_name])
	return manager_name.to_lower().replace("manager", "")
