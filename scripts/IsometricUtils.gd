## IsometricUtils.gd
## Pure static utility — isometric coordinate math.
##
## This is NOT a Node. It holds only static functions.
## No scene tree dependency, no autoload required.
##
## Coordinate systems used throughout the project:
##   Grid coords  — (col, row) integer cell address
##   World coords — Vector2 pixel position in the 2D scene
##
## Isometric layout (staggered diamond):
##   Each tile is tile_width × tile_height pixels.
##   Tiles are offset so they form a diamond grid:
##     world_x = (col - row) * (tile_width  / 2)
##     world_y = (col + row) * (tile_height / 2)
##
## This gives the classic isometric look without a TileMap.

class_name IsometricUtils


## Convert grid (col, row) to world-space pixel position (top-center of tile).
static func grid_to_world(col: int, row: int, tile_w: float, tile_h: float) -> Vector2:
	var x: float = float(col - row) * (tile_w * 0.5)
	var y: float = float(col + row) * (tile_h * 0.5)
	return Vector2(x, y)


## Convert world-space pixel position back to the nearest grid (col, row).
## Returns Vector2i for integer grid coordinates.
static func world_to_grid(world_pos: Vector2, tile_w: float, tile_h: float) -> Vector2i:
	# Inverse of the grid_to_world transform.
	var col_f: float = (world_pos.x / (tile_w * 0.5) + world_pos.y / (tile_h * 0.5)) * 0.5
	var row_f: float = (world_pos.y / (tile_h * 0.5) - world_pos.x / (tile_w * 0.5)) * 0.5
	return Vector2i(roundi(col_f), roundi(row_f))


## Returns the axis-aligned bounding rect of the entire grid in world space.
## Useful for clamping camera bounds.
static func grid_bounds(cols: int, rows: int, tile_w: float, tile_h: float) -> Rect2:
	# The four corners of the diamond grid.
	var top:    Vector2 = grid_to_world(0,        0,        tile_w, tile_h)
	var right:  Vector2 = grid_to_world(cols - 1, 0,        tile_w, tile_h)
	var bottom: Vector2 = grid_to_world(cols - 1, rows - 1, tile_w, tile_h)
	var left:   Vector2 = grid_to_world(0,        rows - 1, tile_w, tile_h)

	var min_x: float = minf(minf(top.x, right.x), minf(bottom.x, left.x))
	var max_x: float = maxf(maxf(top.x, right.x), maxf(bottom.x, left.x))
	var min_y: float = minf(minf(top.y, right.y), minf(bottom.y, left.y))
	var max_y: float = maxf(maxf(top.y, right.y), maxf(bottom.y, left.y))

	# Add half a tile height so the bottom row is fully visible.
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y + tile_h)


## Returns true if (col, row) is within the grid bounds.
static func is_valid_cell(col: int, row: int, cols: int, rows: int) -> bool:
	return col >= 0 and col < cols and row >= 0 and row < rows
