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
## These are prototype colors — replace with sprites/textures later.
const SOIL_COLORS: Dictionary = {
	"limestone_clay": Color("c8b89a"),
	"clay":           Color("a0785a"),
	"gravel":         Color("b8a882"),
	"sandy":          Color("d4c090"),
}

# Fallback color when soil id is unknown.
const SOIL_COLOR_DEFAULT: Color = Color("8a9a7a")

# ─── Vine overlay colors ──────────────────────────────────────────────────────
## Tinted over the soil color when a vine is planted.
const VINE_COLOR_YOUNG:    Color = Color("5a9e6a")   # bright fresh green
const VINE_COLOR_MATURE:   Color = Color("3d7a4a")   # deep vineyard green
const VINE_COLOR_OLD:      Color = Color("2d5c38")   # dark, gnarled

# ─── Health tint ──────────────────────────────────────────────────────────────
## Lerp target when vine health is low.
const HEALTH_POOR_TINT:    Color = Color("8a7a3a")   # yellowed, stressed

# ─── Outline colors ───────────────────────────────────────────────────────────
const OUTLINE_EMPTY:       Color = Color("2a4a35")
const OUTLINE_PLANTED:     Color = Color("1a3a28")
const OUTLINE_SICK:        Color = Color("7a6020")

# ─── Public API ───────────────────────────────────────────────────────────────

## Computes the base polygon color for a tile given its sim data.
## [param checkerboard] applies a subtle brightness shift for grid readability.
static func compute_base_color(data: TileSimData, checkerboard: bool) -> Color:
	if data == null:
		return SOIL_COLOR_DEFAULT

	# Start from soil color.
	var base: Color = SOIL_COLORS.get(data.soil_type, SOIL_COLOR_DEFAULT)

	# Checkerboard: darken alternate tiles slightly.
	if checkerboard:
		base = base.darkened(0.06)

	if not data.is_planted:
		# Empty tile: tint slightly by humidity (wetter = slightly darker/greener).
		return base.lerp(base.darkened(0.15), data.humidity * 0.4)

	# Planted tile: blend toward vine color based on age.
	var vine_color: Color
	var age_years: int = data.vine_age / 4
	if age_years < 3:
		vine_color = VINE_COLOR_YOUNG
	elif age_years < 20:
		vine_color = VINE_COLOR_MATURE
	else:
		vine_color = VINE_COLOR_OLD

	# Blend soil → vine (vine coverage increases with age, caps at 70%).
	var vine_blend: float = clampf(float(age_years) / 8.0, 0.25, 0.70)
	var result: Color     = base.lerp(vine_color, vine_blend)

	# Health tint: poor health yellows the tile.
	if data.vine_health < 0.55:
		var sick_factor: float = clampf(1.0 - data.vine_health / 0.55, 0.0, 0.6)
		result = result.lerp(HEALTH_POOR_TINT, sick_factor)

	return result


## Computes the outline color for a tile.
static func compute_outline_color(data: TileSimData) -> Color:
	if data == null:
		return OUTLINE_EMPTY
	if data.is_planted and data.vine_health < 0.35:
		return OUTLINE_SICK
	if data.is_planted:
		return OUTLINE_PLANTED
	return OUTLINE_EMPTY


## Returns a short status string for the tile label (shown in debug mode).
static func tile_label(data: TileSimData) -> String:
	if data == null:
		return "?"
	if not data.is_planted:
		return data.soil_type.substr(0, 2).to_upper()
	return data.grape_variety.substr(0, 2).to_upper() if data.grape_variety != "" else "V"
