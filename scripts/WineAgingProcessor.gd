## WineAgingProcessor.gd
## Pure static class — yearly wine aging simulation.
##
## Responsibility:
##   - Computes aging_potential at batch creation.
##   - Advances age_years and evolves wine profile each year.
##   - Determines maturity_stage from age vs potential.
##
## Aging model:
##   aging_potential (0–1) determines the peak year:
##     peak_year = round(aging_potential × 12) + 1   (range: 1–13 years)
##
##   Maturity stages by age relative to peak_year:
##     young:      age < peak_year × 0.4
##     developing: age < peak_year × 0.8
##     peak:       age < peak_year × 1.2
##     declining:  age ≥ peak_year × 1.2
##
##   Each year:
##     complexity  += small gain (more in developing, less at peak/declining)
##     freshness   -= small loss (accelerates in declining)
##     wine_quality follows a bell curve peaking at peak_year
##
##   Oaked wines (old_oak, new_oak) have higher aging_potential.
##
## No Node, no signals, no scene tree dependency.

class_name WineAgingProcessor
extends RefCounted

# Stage constants.
const STAGE_YOUNG:      String = "young"
const STAGE_DEVELOPING: String = "developing"
const STAGE_PEAK:       String = "peak"
const STAGE_DECLINING:  String = "declining"


## Compute and set aging_potential on a newly created WineBatch.
## Called once by FermentationManager._create_batch() after all other fields are set.
static func compute_aging_potential(batch: WineBatch) -> void:
	# Base from acidity (high acid = longer life) and complexity.
	var base: float = batch.source_acidity * 0.35 + batch.complexity * 0.30

	# Quality ceiling contribution.
	base += batch.source_grape_quality * 0.20

	# Method bonus: oak adds structure that supports aging.
	var method_bonus: float = 0.0
	match batch.fermentation_method:
		"old_oak": method_bonus = 0.08
		"new_oak": method_bonus = 0.15

	base += method_bonus

	batch.aging_potential = clampf(base, 0.05, 1.0)
	batch.maturity_stage  = STAGE_YOUNG


## Age one WineBatch by one year. Mutates the batch in-place.
## Returns true if the stage changed (useful for logging).
static func tick_year(batch: WineBatch) -> bool:
	batch.age_years += 1

	var old_stage: String = batch.maturity_stage
	var peak_year: int    = _peak_year(batch.aging_potential)

	# ── Update maturity stage ─────────────────────────────────────────────
	batch.maturity_stage = _stage_for(batch.age_years, peak_year)

	# ── Evolve wine profile ───────────────────────────────────────────────
	match batch.maturity_stage:
		STAGE_YOUNG:
			# Young: slight complexity gain, minimal freshness loss.
			batch.complexity = clampf(batch.complexity + 0.02, 0.0, 1.0)
			batch.freshness  = clampf(batch.freshness  - 0.01, 0.0, 1.0)

		STAGE_DEVELOPING:
			# Developing: stronger complexity gain, moderate freshness loss.
			batch.complexity = clampf(batch.complexity + 0.04, 0.0, 1.0)
			batch.freshness  = clampf(batch.freshness  - 0.02, 0.0, 1.0)

		STAGE_PEAK:
			# Peak: complexity stabilises, freshness holds.
			batch.complexity = clampf(batch.complexity + 0.01, 0.0, 1.0)
			batch.freshness  = clampf(batch.freshness  - 0.01, 0.0, 1.0)

		STAGE_DECLINING:
			# Declining: complexity fades, freshness drops faster.
			batch.complexity = clampf(batch.complexity - 0.03, 0.0, 1.0)
			batch.freshness  = clampf(batch.freshness  - 0.04, 0.0, 1.0)

	# ── Recompute wine_quality from bell curve ────────────────────────────
	batch.wine_quality = _quality_at_age(batch, peak_year)

	return batch.maturity_stage != old_stage


## Returns the peak year for a given aging_potential.
static func _peak_year(aging_potential: float) -> int:
	return maxi(1, roundi(aging_potential * 12.0))


## Returns the maturity stage for a given age and peak year.
static func _stage_for(age: int, peak_year: int) -> String:
	var p: float = float(peak_year)
	if float(age) < p * 0.4:
		return STAGE_YOUNG
	elif float(age) < p * 0.8:
		return STAGE_DEVELOPING
	elif float(age) < p * 1.2:
		return STAGE_PEAK
	else:
		return STAGE_DECLINING


## Bell-curve quality: rises to peak_year, then declines.
## Starts at 70% of peak quality at creation (age=0) to avoid a year-1 quality crash.
## The curve reaches 1.0 (full peak quality) at peak_year, then falls.
static func _quality_at_age(batch: WineBatch, peak_year: int) -> float:
	var age: float  = float(batch.age_years)
	var peak: float = float(peak_year)

	# Normalised position: 0 at birth, 1.0 at peak, >1 past peak.
	var t: float = age / peak if peak > 0.0 else 1.0

	var curve: float
	if t <= 1.0:
		# Rising phase: smoothstep from 0→1, then offset so it starts at 0.70.
		# curve(0) = 0.70, curve(1) = 1.00 — no quality crash in year 1.
		var ss: float = t * t * (3.0 - 2.0 * t)   # smoothstep 0→1
		curve = 0.70 + 0.30 * ss
	else:
		# Declining phase: steeper fall after peak.
		var over: float = t - 1.0
		curve = maxf(1.0 - over * over * 1.5, 0.0)

	# Scale by the batch's base quality (aging can't exceed original ceiling).
	var base_quality: float = (
		batch.source_grape_quality * 0.40 +
		batch.freshness            * 0.20 +
		batch.body                 * 0.15 +
		batch.complexity           * 0.25
	)
	return clampf(base_quality * curve, 0.0, 1.0)
