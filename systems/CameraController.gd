## CameraController.gd
## Attached to: Camera2D (WorldCamera) in World.tscn
##
## Responsibility:
##   - WASD / arrow key pan
##   - Edge scrolling (mouse near viewport edge)
##   - Middle-mouse drag pan
##   - Scroll-wheel zoom (zooms toward mouse cursor position)
##   - Smooth lerped movement and zoom
##   - Hard bounds clamping so the player can't leave the grid
##
## All numeric values come from world_config.json — nothing hardcoded.
## Mobile note: swap _handle_keyboard_pan / _handle_edge_scroll / _handle_drag
##              for touch gesture handlers when targeting mobile.

class_name CameraController
extends Camera2D

# ─── Config ───────────────────────────────────────────────────────────────────
var _zoom_min:            float = 0.4
var _zoom_max:            float = 2.5
var _zoom_step:           float = 0.15
var _zoom_smooth_speed:   float = 8.0
var _pan_speed_kb:        float = 500.0
var _pan_speed_edge:      float = 350.0
var _pan_smooth_speed:    float = 12.0
var _edge_margin:         float = 20.0
var _bounds_margin:       float = 300.0

# ─── Runtime state ────────────────────────────────────────────────────────────
var _target_zoom:     float   = 1.0
var _target_position: Vector2 = Vector2.ZERO

# Middle-mouse drag
var _dragging:          bool    = false
var _drag_start_mouse:  Vector2 = Vector2.ZERO
var _drag_start_cam:    Vector2 = Vector2.ZERO

# Bounds in world space — set by World after grid is built.
var _bounds: Rect2 = Rect2(-2000.0, -2000.0, 4000.0, 4000.0)

# Viewport size cache — updated on resize.
var _viewport_size: Vector2 = Vector2(1280.0, 720.0)

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	_target_zoom     = zoom.x
	_target_position = position

	get_viewport().size_changed.connect(_on_viewport_resized)
	_viewport_size = Vector2(get_viewport().get_visible_rect().size)

	if DataManager.is_loaded("world_config"):
		_load_config()
	else:
		DataManager.data_loaded.connect(_on_data_loaded)


func _process(delta: float) -> void:
	_handle_keyboard_pan(delta)
	_handle_edge_scroll(delta)
	_smooth_position(delta)
	_smooth_zoom(delta)


func _unhandled_input(event: InputEvent) -> void:
	_handle_scroll_zoom(event)
	_handle_drag(event)


# ─── Public API ───────────────────────────────────────────────────────────────

## Set movement bounds from the grid world rect + margin.
func set_bounds(bounds: Rect2, margin: float = 0.0) -> void:
	_bounds = bounds.grow(margin)


## Instantly snap camera to a world position (no lerp).
func snap_to(world_pos: Vector2) -> void:
	_target_position = _clamped(world_pos)
	position         = _target_position


## Returns current zoom level as a float.
func get_zoom_level() -> float:
	return zoom.x


# ─── Private — config ─────────────────────────────────────────────────────────

func _on_data_loaded(key: String) -> void:
	if key == "world_config":
		_load_config()


func _load_config() -> void:
	var cfg: Dictionary = DataManager.get_data("world_config")
	var raw: Variant    = cfg.get("camera", {})
	if not raw is Dictionary:
		return
	var c: Dictionary = raw

	_zoom_min          = float(c.get("zoom_min",              0.4))
	_zoom_max          = float(c.get("zoom_max",              2.5))
	_zoom_step         = float(c.get("zoom_step",             0.15))
	_zoom_smooth_speed = float(c.get("zoom_smooth_speed",     8.0))
	_pan_speed_kb      = float(c.get("pan_speed_keyboard",    500.0))
	_pan_speed_edge    = float(c.get("pan_speed_edge_scroll", 350.0))
	_pan_smooth_speed  = float(c.get("pan_smooth_speed",      12.0))
	_edge_margin       = float(c.get("edge_scroll_margin",    20.0))
	_bounds_margin     = float(c.get("bounds_margin",         300.0))

	_target_zoom = clampf(_target_zoom, _zoom_min, _zoom_max)


func _on_viewport_resized() -> void:
	_viewport_size = Vector2(get_viewport().get_visible_rect().size)


# ─── Private — input ──────────────────────────────────────────────────────────

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

	if dir == Vector2.ZERO:
		return

	# Scale speed by zoom so movement feels consistent at all zoom levels.
	var speed: float = _pan_speed_kb / zoom.x
	_target_position += dir.normalized() * speed * delta
	_target_position  = _clamped(_target_position)


func _handle_edge_scroll(delta: float) -> void:
	# Skip edge scrolling while dragging — it conflicts.
	if _dragging:
		return

	var mouse: Vector2 = get_viewport().get_mouse_position()
	var dir:   Vector2 = Vector2.ZERO
	var m:     float   = _edge_margin

	if mouse.x < m:
		dir.x -= 1.0
	elif mouse.x > _viewport_size.x - m:
		dir.x += 1.0
	if mouse.y < m:
		dir.y -= 1.0
	elif mouse.y > _viewport_size.y - m:
		dir.y += 1.0

	if dir == Vector2.ZERO:
		return

	var speed: float = _pan_speed_edge / zoom.x
	_target_position += dir.normalized() * speed * delta
	_target_position  = _clamped(_target_position)


func _handle_scroll_zoom(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mb: InputEventMouseButton = event
	if not mb.pressed:
		return
	if mb.button_index != MOUSE_BUTTON_WHEEL_UP and \
	   mb.button_index != MOUSE_BUTTON_WHEEL_DOWN:
		return

	# Zoom toward the mouse cursor position.
	# 1. Record world position under cursor before zoom.
	var mouse_screen: Vector2 = mb.position
	var world_before: Vector2 = _screen_to_world(mouse_screen)

	# 2. Apply zoom delta.
	var direction: float = 1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
	_target_zoom = clampf(_target_zoom + direction * _zoom_step, _zoom_min, _zoom_max)

	# 3. Compute where that world point will be after zoom and offset camera
	#    so the point stays under the cursor (zoom-toward-cursor feel).
	#    We approximate using the target zoom since lerp hasn't applied yet.
	var new_zoom:    float   = _target_zoom
	var world_after: Vector2 = _target_position + (mouse_screen - _viewport_size * 0.5) / new_zoom
	_target_position += world_before - world_after
	_target_position  = _clamped(_target_position)

	get_viewport().set_input_as_handled()


func _handle_drag(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging         = mb.pressed
			_drag_start_mouse = mb.position
			_drag_start_cam   = _target_position

	elif event is InputEventMouseMotion and _dragging:
		var mm: InputEventMouseMotion = event
		# Divide by zoom so drag distance matches visual movement exactly.
		_target_position = _drag_start_cam - (mm.position - _drag_start_mouse) / zoom.x
		_target_position = _clamped(_target_position)
		get_viewport().set_input_as_handled()


# ─── Private — movement ───────────────────────────────────────────────────────

func _smooth_position(delta: float) -> void:
	var t: float = clampf(_pan_smooth_speed * delta, 0.0, 1.0)
	position = position.lerp(_target_position, t)


func _smooth_zoom(delta: float) -> void:
	var t:    float   = clampf(_zoom_smooth_speed * delta, 0.0, 1.0)
	var tzvec: Vector2 = Vector2(_target_zoom, _target_zoom)
	zoom = zoom.lerp(tzvec, t)


func _clamped(pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, _bounds.position.x, _bounds.end.x),
		clampf(pos.y, _bounds.position.y, _bounds.end.y)
	)


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	# Convert screen pixel → world position given current camera state.
	return position + (screen_pos - _viewport_size * 0.5) / zoom.x
