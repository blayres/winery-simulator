## CameraController.gd
## Attached to: Camera2D node inside World.tscn
##
## Responsibility:
##   - Smooth pan via keyboard (WASD / arrow keys) and middle-mouse drag.
##   - Smooth zoom via scroll wheel.
##   - Bounded movement so the player can't pan off the grid.
##   - All values driven from world_config.json — nothing hardcoded.
##
## Architecture note:
##   CameraController is self-contained. It reads config once in _ready()
##   and then operates independently. It emits no signals — it only moves itself.
##   Future mobile support: replace keyboard/mouse input with touch gestures here.

class_name CameraController
extends Camera2D

# ─── Config (from JSON) ───────────────────────────────────────────────────────
var _zoom_min:          float = 0.4
var _zoom_max:          float = 2.5
var _zoom_step:         float = 0.15
var _zoom_smooth_speed: float = 8.0
var _pan_speed_kb:      float = 400.0
var _pan_smooth_speed:  float = 10.0
var _bounds_margin:     float = 200.0

# ─── Runtime state ────────────────────────────────────────────────────────────
var _target_zoom:     float   = 1.0
var _target_position: Vector2 = Vector2.ZERO

# Middle-mouse drag state.
var _dragging:        bool    = false
var _drag_start_mouse: Vector2 = Vector2.ZERO
var _drag_start_cam:   Vector2 = Vector2.ZERO

# Camera movement bounds in world space (set by World after grid is built).
var _bounds: Rect2 = Rect2(-2000.0, -2000.0, 4000.0, 4000.0)

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	_target_zoom     = zoom.x
	_target_position = position

	if DataManager.is_loaded("world_config"):
		_load_config()
	else:
		DataManager.data_loaded.connect(_on_data_loaded)


func _process(delta: float) -> void:
	_handle_keyboard_pan(delta)
	_smooth_position(delta)
	_smooth_zoom(delta)


func _unhandled_input(event: InputEvent) -> void:
	_handle_scroll_zoom(event)
	_handle_drag(event)


# ─── Public API ───────────────────────────────────────────────────────────────

## Called by World once the grid is built so the camera knows its limits.
## [param bounds] is the world-space Rect2 of the full grid.
## [param margin] extra padding beyond the grid edge.
func set_bounds(bounds: Rect2, margin: float = 0.0) -> void:
	_bounds = bounds.grow(margin)


## Snap the camera to a world-space position immediately (no smoothing).
func snap_to(world_pos: Vector2) -> void:
	_target_position = world_pos
	position         = world_pos


# ─── Private ──────────────────────────────────────────────────────────────────

func _on_data_loaded(key: String) -> void:
	if key == "world_config":
		_load_config()


func _load_config() -> void:
	var cfg: Dictionary = DataManager.get_data("world_config")
	var raw_cam: Variant = cfg.get("camera", {})
	if not raw_cam is Dictionary:
		return
	var cam: Dictionary = raw_cam

	_zoom_min          = float(cam.get("zoom_min",           0.4))
	_zoom_max          = float(cam.get("zoom_max",           2.5))
	_zoom_step         = float(cam.get("zoom_step",          0.15))
	_zoom_smooth_speed = float(cam.get("zoom_smooth_speed",  8.0))
	_pan_speed_kb      = float(cam.get("pan_speed_keyboard", 400.0))
	_pan_smooth_speed  = float(cam.get("pan_smooth_speed",   10.0))
	_bounds_margin     = float(cam.get("bounds_margin",      200.0))

	_target_zoom = clampf(_target_zoom, _zoom_min, _zoom_max)


func _handle_keyboard_pan(delta: float) -> void:
	var dir: Vector2 = Vector2.ZERO

	if Input.is_action_pressed("ui_left")  or Input.is_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		dir.x += 1.0
	if Input.is_action_pressed("ui_up")    or Input.is_key_pressed(KEY_W):
		dir.y -= 1.0
	if Input.is_action_pressed("ui_down")  or Input.is_key_pressed(KEY_S):
		dir.y += 1.0

	if dir != Vector2.ZERO:
		# Scale pan speed by current zoom so it feels consistent at all zoom levels.
		var speed: float = _pan_speed_kb / zoom.x
		_target_position += dir.normalized() * speed * delta
		_clamp_target()


func _handle_scroll_zoom(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mb: InputEventMouseButton = event
	if not mb.pressed:
		return

	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		_target_zoom = clampf(_target_zoom + _zoom_step, _zoom_min, _zoom_max)
		get_viewport().set_input_as_handled()
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_target_zoom = clampf(_target_zoom - _zoom_step, _zoom_min, _zoom_max)
		get_viewport().set_input_as_handled()


func _handle_drag(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_dragging          = true
				_drag_start_mouse  = mb.position
				_drag_start_cam    = _target_position
			else:
				_dragging = false

	elif event is InputEventMouseMotion and _dragging:
		var mm: InputEventMouseMotion = event
		var delta_mouse: Vector2 = mm.position - _drag_start_mouse
		# Divide by zoom so drag distance matches visual movement.
		_target_position = _drag_start_cam - delta_mouse / zoom.x
		_clamp_target()
		get_viewport().set_input_as_handled()


func _smooth_position(delta: float) -> void:
	position = position.lerp(_target_position, clampf(_pan_smooth_speed * delta, 0.0, 1.0))


func _smooth_zoom(delta: float) -> void:
	var target_zoom_vec: Vector2 = Vector2(_target_zoom, _target_zoom)
	zoom = zoom.lerp(target_zoom_vec, clampf(_zoom_smooth_speed * delta, 0.0, 1.0))


func _clamp_target() -> void:
	_target_position.x = clampf(_target_position.x, _bounds.position.x, _bounds.end.x)
	_target_position.y = clampf(_target_position.y, _bounds.position.y, _bounds.end.y)
