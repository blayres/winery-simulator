## TileVisualController.gd
## class_name: TileVisualController
## Type: RefCounted (pure logic object, not a Node)
##
## Responsibility:
##   Translates TileSimData values into visual properties for a VineyardTile.
##   Called by VineyardTile when its sim data is updated.
##
## Architecture note:
##   This is the ONLY place where simulation values map to colors/visuals.
##   Keeping this logic separate from both VineyardTile (input/animation)
##   and TileSimData (pure data) means:
##     - Changing visuals never touches simulation code
##     - Changing simulation never touches visual code
##     - Both can be tested independently
##
##   All color palettes are defined here as constants.
##   Future: move palettes to a theme resource or JSON for artist control.

class_name TileVisualController
extends RefCounted

# ─── Soil color palette ───────────────────────────────────────────────────────
## Maps soil_type id → base tile color.
## Brightened slightly vs prototype v1 so owned empty land reads clearly.
const SOIL_COLORS: Dictionary = {
	"limestone_clay": Color("d4c4a8"),   # warm cream
	"clay":           Color("b08868"),   # terracotta
	"gravel":         Color("c4b890"),   # sandy stone
	"sandy":          Color("ddd0a0"),   # pale gold
}
const SOIL_COLOR_DEFAULT: Color = Color("9aaa8a")   # muted sage

# ─── Vine overlay colors ──────────────────────────────────────────────────────
## Each stage has a distinct, readable hue.
const VINE_COLOR_YOUNG:     Color = Color("72c080")   # bright fresh green
const VINE_COLOR_MATURE:    Color = Color("3a8048")   # deep vineyard green
const VINE_COLOR_OLD:       Color = Color("285c38")   # dark, concentrated
const VINE_COLOR_DECLINING: Color = Color("786030")   # olive-brown, stressed

# ─── Health tint ──────────────────────────────────────────────────────────────
## Reddish-brown for sick vines — more readable than the old yellow.
const HEALTH_POOR_TINT: Color = Color("904030")   # deep red-brown

# ─── Outline colors ───────────────────────────────────────────────────────────
const OUTLINE_EMPTY:    Color = Color("2a4a35")
const OUTLINE_PLANTED:  Color = Color("1a3a28")
const OUTLINE_SICK:     Color = Color("8a3820")   # reddish — matches health tint
const OUTLINE_HARVEST:  Color = Color("d4a820")   # bright gold — harvest ready

# ─── Locked tile colors ───────────────────────────────────────────────────────
## Desaturated blue-grey — clearly unavailable, slightly cooler than soil.
const LOCKED_COLOR:   Color = Color("3a3e44")
const LOCKED_OUTLINE: Color = Color("252830")

# ─── Seasonal atmosphere tints ────────────────────────────────────────────────
## Subtle overlay blended onto the final tile color each season.
## Applied at low strength so individual tile identity is preserved.
const SEASON_TINT: Array = [
	Color("a8d8a0"),   # Spring  — fresh pale green
	Color("e8d880"),   # Summer  — warm golden
	Color("d89050"),   # Autumn  — orange-amber
	Color("a0b8d0"),   # Winter  — cool blue-grey
]
const SEASON_TINT_STRENGTH: Array = [
	0.08,   # Spring  — gentle
	0.10,   # Summer  — warm
	0.12,   # Autumn  — noticeable
	0.10,   # Winter  — cool
]

# ─── Public API ───────────────────────────────────────────────────────────────

## Computes the base polygon color for a tile given its sim data.
## [param checkerboard] applies a subtle brightness shift for grid readability.
## [param season] 0–3 applies a seasonal atmosphere tint.
static func compute_base_color(data: TileSimData, checkerboard: bool,
		season: int = -1) -> Color:
	if data == null:
		return SOIL_COLOR_DEFAULT

	# Locked tiles: cool blue-grey, clearly unavailable.
	if not data.is_owned:
		var locked: Color = LOCKED_COLOR
		if checkerboard:
			locked = locked.darkened(0.06)
		# Locked tiles still get a faint seasonal tint so they feel part of the world.
		if season >= 0 and season < SEASON_TINT.size():
			locked = locked.lerp(SEASON_TINT[season], SEASON_TINT_STRENGTH[season] * 0.4)
		return locked

	# Start from soil color.
	var base: Color = SOIL_COLORS.get(data.soil_type, SOIL_COLOR_DEFAULT)

	# Checkerboard: darken alternate tiles slightly for grid readability.
	if checkerboard:
		base = base.darkened(0.07)

	if not data.is_planted:
		# Empty owned land: show soil with a subtle humidity darkening.
		var result: Color = base.lerp(base.darkened(0.18), data.humidity * 0.35)
		return _apply_season(result, season)

	# ── Planted tile ──────────────────────────────────────────────────────
	var vine_color: Color
	match data.lifecycle_stage:
		"young":     vine_color = VINE_COLOR_YOUNG
		"mature":    vine_color = VINE_COLOR_MATURE
		"old":       vine_color = VINE_COLOR_OLD
		"declining": vine_color = VINE_COLOR_DECLINING
		_:           vine_color = VINE_COLOR_MATURE

	# Blend soil → vine. Young vines show more soil; mature vines are fully covered.
	var age_years: int    = data.vine_age / 4
	var vine_blend: float = clampf(float(age_years) / 6.0, 0.25, 0.80)
	var result: Color     = base.lerp(vine_color, vine_blend)

	# Health tint: reddish-brown for sick vines. Kicks in below 0.50 health.
	if data.vine_health < 0.50:
		var sick_factor: float = clampf(1.0 - data.vine_health / 0.50, 0.0, 0.65)
		result = result.lerp(HEALTH_POOR_TINT, sick_factor)

	# Ripening tint: warm amber as grapes approach harvest.
	# Stronger than before so harvest-ready tiles are clearly golden.
	if data.ripeness > 0.0:
		var ripe_tint: Color  = Color("d4a830")   # warm amber-gold
		var ripe_blend: float = clampf(data.ripeness * 0.45, 0.0, 0.45)
		result = result.lerp(ripe_tint, ripe_blend)

	return _apply_season(result, season)


## Computes the outline color for a tile.
static func compute_outline_color(data: TileSimData) -> Color:
	if data == null:
		return OUTLINE_EMPTY
	if not data.is_owned:
		return LOCKED_OUTLINE
	if data.is_planted and data.harvest_ready:
		return OUTLINE_HARVEST
	if data.is_planted and data.vine_health < 0.35:
		return OUTLINE_SICK
	if data.is_planted:
		return OUTLINE_PLANTED
	return OUTLINE_EMPTY


## Returns a short status string for the tile label (shown in debug mode).
static func tile_label(data: TileSimData) -> String:
	if data == null:
		return "?"
	if not data.is_owned:
		return "🔒"
	if not data.is_planted:
		return data.soil_type.substr(0, 2).to_upper()
	return data.grape_variety.substr(0, 2).to_upper() if data.grape_variety != "" else "V"


## Returns the seasonal tint color for a given season index (0–3).
## Used by VineyardTile to tint hover/select colors seasonally.
static func get_season_tint(season: int) -> Color:
	if season >= 0 and season < SEASON_TINT.size():
		return SEASON_TINT[season]
	return Color.WHITE


# ─── Private ──────────────────────────────────────────────────────────────────

static func _apply_season(color: Color, season: int) -> Color:
	if season < 0 or season >= SEASON_TINT.size():
		return color
	return color.lerp(SEASON_TINT[season], SEASON_TINT_STRENGTH[season])
