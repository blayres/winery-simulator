## EventManager.gd
## Singleton — drives narrative and gameplay events.
##
## Responsibility:
##   - Loads event definitions from JSON.
##   - Evaluates trigger conditions each season.
##   - Queues events and dispatches their effects to other managers.
##   - Maintains event history for the playthrough.
##
## Architecture note:
##   Events are pure data (JSON). This manager is the interpreter.
##   Effects are applied by calling EconomyManager and ClimateManager directly.
##
## Godot 4.6 notes:
##   - _event_queue and _event_data use untyped Array (JSON produces untyped).
##   - _triggered_ids uses Array[String] — always populated via str() conversion.
##   - All Dictionary.get() results assigned to Variant first, then type-checked.
##   - season_name is explicitly typed String.

extends Node

# ─── Signals ──────────────────────────────────────────────────────────────────
signal event_triggered(event_data: Dictionary)
signal event_resolved(event_id: String, choice_index: int)
signal event_queue_changed(queue: Array)

# ─── State ────────────────────────────────────────────────────────────────────
var _event_queue:   Array          = []
var _triggered_ids: Array[String]  = []
var _event_data:    Array          = []

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	DataManager.data_loaded.connect(_on_data_loaded)
	GameManager.season_changed.connect(_on_season_changed)


# ─── Public API ───────────────────────────────────────────────────────────────

## Resolve a queued event. [param choice_index] indexes into the event's choices array.
func resolve_event(event_id: String, choice_index: int) -> void:
	var idx: int = _find_queue_index(event_id)
	if idx == -1:
		push_warning("EventManager: tried to resolve unknown event '%s'." % event_id)
		return

	if not _event_queue[idx] is Dictionary:
		return
	var event: Dictionary = _event_queue[idx]
	_event_queue.remove_at(idx)

	event_resolved.emit(event_id, choice_index)
	event_queue_changed.emit(_event_queue.duplicate())

	var raw_choices: Variant = event.get("choices", [])
	if not raw_choices is Array:
		return
	var choices: Array = raw_choices

	if choice_index < choices.size() and choices[choice_index] is Dictionary:
		var chosen: Dictionary = choices[choice_index]
		var raw_effects: Variant = chosen.get("effects", [])
		if raw_effects is Array:
			_apply_effects(raw_effects)


func get_event_queue() -> Array:
	return _event_queue.duplicate()


func has_pending_events() -> bool:
	return not _event_queue.is_empty()


# ─── Private ──────────────────────────────────────────────────────────────────

func _on_data_loaded(key: String) -> void:
	if key == "events":
		var raw: Dictionary = DataManager.get_data("events")
		var raw_events: Variant = raw.get("events", [])
		_event_data = raw_events if raw_events is Array else []


func _on_season_changed(season: GameManager.Season) -> void:
	_evaluate_events(season)


func _evaluate_events(season: GameManager.Season) -> void:
	# Explicit String — avoids Variant inference.
	var season_name: String = GameManager.get_season_name_for(season).to_lower()

	for i: int in _event_data.size():
		if not _event_data[i] is Dictionary:
			continue
		var event: Dictionary = _event_data[i]
		var event_id: String  = str(event.get("id", ""))

		# Skip one-shot events that already fired.
		if bool(event.get("one_shot", false)) and _triggered_ids.has(event_id):
			continue

		# Season filter.
		var raw_seasons: Variant = event.get("seasons", [])
		if raw_seasons is Array:
			var allowed_seasons: Array = raw_seasons
			if not allowed_seasons.is_empty() and not allowed_seasons.has(season_name):
				continue

		# Year range filter.
		var min_year: int = int(event.get("min_year", 1))
		var max_year: int = int(event.get("max_year", 9999))
		if GameManager.current_year < min_year or GameManager.current_year > max_year:
			continue

		# Probability roll.
		var chance: float = float(event.get("chance", 1.0))
		if randf() > chance:
			continue

		_queue_event(event)


func _queue_event(event: Dictionary) -> void:
	var event_id: String = str(event.get("id", ""))
	_event_queue.append(event.duplicate(true))
	_triggered_ids.append(event_id)
	event_triggered.emit(event.duplicate(true))
	event_queue_changed.emit(_event_queue.duplicate())


## Supported effect types:
##   "economy_delta"    — { "type": "economy_delta",    "value": float }
##   "climate_override" — { "type": "climate_override", "profile_id": String }
func _apply_effects(effects: Array) -> void:
	for i: int in effects.size():
		if not effects[i] is Dictionary:
			continue
		var effect: Dictionary  = effects[i]
		var effect_type: String = str(effect.get("type", ""))

		match effect_type:
			"economy_delta":
				var val: float = float(effect.get("value", 0.0))
				if val >= 0.0:
					EconomyManager.earn(val, "event_effect")
				else:
					EconomyManager.spend(-val, "event_effect")
			"climate_override":
				ClimateManager.set_profile(str(effect.get("profile_id", "")))
			_:
				push_warning("EventManager: unhandled effect type '%s'" % effect_type)


func _find_queue_index(event_id: String) -> int:
	for i: int in _event_queue.size():
		if not _event_queue[i] is Dictionary:
			continue
		var entry: Dictionary = _event_queue[i]
		if str(entry.get("id", "")) == event_id:
			return i
	return -1


# ─── Save / Load interface ────────────────────────────────────────────────────

func get_save_data() -> Dictionary:
	return {
		"triggered_ids": _triggered_ids,
		"event_queue":   _event_queue,
	}


func load_save_data(data: Dictionary) -> void:
	var raw_ids: Variant = data.get("triggered_ids", [])
	_triggered_ids.clear()
	if raw_ids is Array:
		var ids: Array = raw_ids
		for i: int in ids.size():
			_triggered_ids.append(str(ids[i]))

	var raw_queue: Variant = data.get("event_queue", [])
	_event_queue = raw_queue if raw_queue is Array else []
	event_queue_changed.emit(_event_queue.duplicate())
