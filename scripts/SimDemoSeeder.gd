## SimDemoSeeder.gd
## class_name: SimDemoSeeder
## Type: static class (no Node, no instance needed)
##
## Responsibility:
##   Seeds a portion of the grid with demo vine data so the inspector
##   has interesting content to display immediately in the prototype.
##
## Architecture note:
##   Completely separate from VineyardSimulation to keep that file under 300 lines.
##   This entire file is prototype scaffolding — delete or replace with
##   player-driven planting actions when gameplay is implemented.
##
##   Takes a VineyardSimulation reference to call get_tile_data() and
##   _recompute_quality() — both are public API.

class_name SimDemoSeeder


## Seeds ~35% of the grid with varied vine data.
## [param sim] — the VineyardSimulation autoload instance.
static func seed_vines(sim: Node, cols: int, rows: int) -> void:
	var grape_ids: Array[String] = ["pinot_noir", "chardonnay"]
	var planted:   int           = 0
	var target:    int           = int(float(cols * rows) * 0.35)

	for row: int in rows:
		for col: int in cols:
			if planted >= target:
				return

			# Diagonal band pattern for visual variety across the grid.
			var band: int = (col + row) % 5
			if band != 0 and band != 2:
				continue

			# Call public API — SimDemoSeeder never accesses private members.
			var data: TileSimData = sim.get_tile_data(col, row)
			if data == null or data.is_planted:
				continue

			data.is_planted    = true
			data.grape_variety = grape_ids[(col + row) % grape_ids.size()]
			# Varied ages: 0–47 seasons (0–11 years) for a mix of young/mature.
			data.vine_age      = (col * 3 + row * 2) % 48
			data.vine_health   = clampf(0.60 + randf() * 0.35, 0.0, 1.0)

			# Recompute derived quality via public method.
			sim.recompute_quality_public(data)
			planted += 1
