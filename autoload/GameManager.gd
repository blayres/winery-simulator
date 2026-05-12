## GameManager.gd
## Singleton — top-level game state orchestrator.
##
## Responsibility:
##   - Owns the canonical game state (current season, year, phase).
##   - Drives the main game loop by advancing seasons/years.
##   - Broadcasts state changes via signals so all systems stay in sync.
##
## Architecture note:
##   GameManager does NOT contain gameplay logic.
##   It only manages STATE and TRANSITIONS.
##   Gameplay logic lives in domain managers (ClimateManager, WineManager, etc.)
##
## Godot 4.6 notes:
##   - Enum arithmetic uses explicit int cast before modulo to avoid type errors.
##   - SEASON_NAMES uses int keys (enum values are ints at runtime).
##   - load_save_data casts Variant → int explicitly before assigning to enum vars.

extends Node

# ─── Enums ────────────────────────────────────────────────────────────────────
enum Season    { SPRING, SUMMER, AUTUMN, WINTER }
enum GamePhase { MAIN_MENU, PLAYING, PAUSED, GAME_OVER }

# ─── Signals ──────────────────────────────────────────────────────────────────
signal season_changed(new_season: Season)
signal year_advanced(new_year: int)
signal phase_changed(new_phase: GamePhase)
signal game_started()
signal game_paused()
signal game_resumed()

# ─── State ────────────────────────────────────────────────────────────────────
var current_season: Season    = Season.SPRING
var current_year:   int       = 1
var current_phase:  GamePhase = GamePhase.MAIN_MENU

# Season display names keyed by int (enum values are ints at runtime).
# Stored as a plain Dictionary — callers use get_season_name() for safe access.
const SEASON_NAMES: Dictionary = {
	0: "Spring",  # Season.SPRING
	1: "Summer",  # Season.SUMMER
	2: "Autumn",  # Season.AUTUMN
	3: "Winter",  # Season.WINTER
}

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	pass  # Initialization triggered explicitly via start_game().


# ─── Public API ───────────────────────────────────────────────────────────────

## Call this to begin a new game session.
func start_game() -> void:
	current_year   = 1
	current_season = Season.SPRING
	_set_phase(GamePhase.PLAYING)
	game_started.emit()


## Advance to the next season. Rolls over to next year after Winter.
func advance_season() -> void:
	if current_phase != GamePhase.PLAYING:
		return

	# Explicit int arithmetic then cast back to Season enum.
	var next_int: int = (int(current_season) + 1) % 4
	current_season = next_int as Season
	season_changed.emit(current_season)

	# Year advances when we wrap back to Spring.
	if current_season == Season.SPRING:
		current_year += 1
		year_advanced.emit(current_year)


func pause_game() -> void:
	if current_phase == GamePhase.PLAYING:
		_set_phase(GamePhase.PAUSED)
		game_paused.emit()


func resume_game() -> void:
	if current_phase == GamePhase.PAUSED:
		_set_phase(GamePhase.PLAYING)
		game_resumed.emit()


## Returns the human-readable name for the current season.
func get_season_name() -> String:
	var key: int = int(current_season)
	if SEASON_NAMES.has(key):
		return str(SEASON_NAMES[key])
	return "Unknown"


## Returns the human-readable name for any given season value.
func get_season_name_for(season: Season) -> String:
	var key: int = int(season)
	if SEASON_NAMES.has(key):
		return str(SEASON_NAMES[key])
	return "Unknown"


# ─── Private ──────────────────────────────────────────────────────────────────

func _set_phase(phase: GamePhase) -> void:
	if current_phase == phase:
		return
	current_phase = phase
	phase_changed.emit(current_phase)


# ─── Save / Load interface (called by SaveManager) ────────────────────────────

func get_save_data() -> Dictionary:
	return {
		"current_year":   current_year,
		"current_season": int(current_season),
		"current_phase":  int(current_phase),
	}


func load_save_data(data: Dictionary) -> void:
	current_year   = int(data.get("current_year",   1))
	current_season = int(data.get("current_season", int(Season.SPRING))) as Season
	current_phase  = int(data.get("current_phase",  int(GamePhase.PLAYING))) as GamePhase
