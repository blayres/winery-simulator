## TimeManager.gd
## Singleton — owns the game clock: weeks, seasons, years.
##
## Responsibility:
##   - Tracks current_week (1–4), current_season, current_year.
##   - Advances time one week at a time via advance_week().
##   - Rolls season after week 4, rolls year after Winter.
##   - Drives GameManager.advance_season() so existing season signals fire.
##   - Runs optional auto-advance via an internal Timer.
##   - Emits week_changed / season_changed / year_changed for any system
##     that needs finer-grained time hooks than GameManager provides.
##
## Architecture note:
##   TimeManager is the ONLY writer of week/season/year state.
##   Other systems (ClimateManager, VineyardSimulation, etc.) subscribe
##   to its signals — they never advance time themselves.
##
##   Signal hierarchy:
##     week_changed   → fine-grained (UI, animations)
##     season_changed → medium (climate, vine growth)
##     year_changed   → coarse (economy, reputation)
##
##   GameManager.season_changed is also emitted (via advance_season()) so
##   existing listeners on GameManager keep working without changes.

extends Node

# ─── Constants ────────────────────────────────────────────────────────────────
const WEEKS_PER_SEASON: int = 4
const SEASONS_PER_YEAR: int = 4

# Auto-advance interval in real seconds (configurable at runtime).
const AUTO_ADVANCE_INTERVAL: float = 2.0

# ─── Signals ──────────────────────────────────────────────────────────────────
signal week_changed(year: int, season: int, week: int)
signal season_changed(year: int, season: int)
signal year_changed(year: int)

# ─── State ────────────────────────────────────────────────────────────────────
var current_year:   int  = 1
var current_season: int  = 0   # 0=Spring 1=Summer 2=Autumn 3=Winter
var current_week:   int  = 1   # 1–4

var auto_advance:   bool = false

# Internal timer for auto-advance.
var _timer: Timer = null

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time   = AUTO_ADVANCE_INTERVAL
	_timer.autostart   = false
	_timer.one_shot    = false
	_timer.timeout.connect(_on_timer_timeout)
	add_child(_timer)


# ─── Public API ───────────────────────────────────────────────────────────────

## Advance time by exactly one week.
## This is the single entry point for all time progression.
func advance_week() -> void:
	current_week += 1

	if current_week > WEEKS_PER_SEASON:
		current_week = 1
		_advance_season()
	else:
		week_changed.emit(current_year, current_season, current_week)
		print("TimeManager: Year %d  %s  Week %d" % [
			current_year, get_season_name(), current_week
		])


## Advance a full season (4 weeks) in one call.
func advance_season_full() -> void:
	for _i: int in WEEKS_PER_SEASON:
		advance_week()


## Toggle auto-advance on/off.
func toggle_auto_advance() -> void:
	auto_advance = not auto_advance
	if auto_advance:
		_timer.start()
	else:
		_timer.stop()
	print("TimeManager: auto-advance %s" % ("ON" % [] if auto_advance else "OFF"))


## Returns the display name for the current season.
func get_season_name() -> String:
	return _season_name(current_season)


## Returns a formatted time string for UI display.
func get_time_string() -> String:
	return "Year %d  ·  %s  ·  Week %d" % [
		current_year, get_season_name(), current_week
	]


# ─── Save / Load interface (called by SaveManager) ────────────────────────────

func get_save_data() -> Dictionary:
	return {
		"current_year":   current_year,
		"current_season": current_season,
		"current_week":   current_week,
	}


func load_save_data(data: Dictionary) -> void:
	current_year   = int(data.get("current_year",   1))
	current_season = int(data.get("current_season", 0))
	current_week   = int(data.get("current_week",   1))
	week_changed.emit(current_year, current_season, current_week)


# ─── Private ──────────────────────────────────────────────────────────────────

func _advance_season() -> void:
	current_season = (current_season + 1) % SEASONS_PER_YEAR

	# Year rolls over when we return to Spring (season 0).
	if current_season == 0:
		current_year += 1
		year_changed.emit(current_year)
		print("TimeManager: ── New Year %d ──" % current_year)

	# Drive GameManager so its season_changed signal fires for existing listeners.
	# GameManager.advance_season() handles its own season/year state internally.
	GameManager.advance_season()

	season_changed.emit(current_year, current_season)
	week_changed.emit(current_year, current_season, current_week)

	print("TimeManager: Year %d  %s  Week %d" % [
		current_year, get_season_name(), current_week
	])


func _on_timer_timeout() -> void:
	advance_week()


func _season_name(season_idx: int) -> String:
	match season_idx:
		0: return "Spring"
		1: return "Summer"
		2: return "Autumn"
		3: return "Winter"
	return "Unknown"
