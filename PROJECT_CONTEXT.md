# WINERY SIMULATION

## PROJECT OVERVIEW

Winery Simulation is a cozy yet deeply strategic vineyard and wine-making simulation game inspired by French wine culture.

The player begins with a small inherited vineyard and slowly transforms it into a legendary wine estate through:
- terroir mastery
- vineyard management
- climate adaptation
- wine crafting
- economic strategy
- long-term reputation building

The core emotional fantasy is:

> “This vintage is mine.”

The game should create:
- emotional attachment to the land
- pride in successful vintages
- fear of climate disasters
- satisfaction from mastering wine production

The tone is:
- cozy
- elegant
- atmospheric
- intelligent
- emotional
- relaxing but strategic

The game is NOT spreadsheet-focused.
Players should FEEL the wine rather than read raw statistics.

Example:
BAD:
+3 acidity

GOOD:
“Bright freshness with vibrant citrus tension.”

---

# CORE GAME PILLARS

## P1 — TERROIR MATTERS

Soil, climate, altitude, humidity, and sun exposure all influence wine outcome.

Every vineyard tile should feel unique.

Wine quality is heavily influenced by:
- terroir
- weather
- grape variety
- player decisions

---

## P2 — DECISIONS HAVE CONSEQUENCES

No neutral choices.

Every action creates tradeoffs.

Examples:
- harvest early = freshness but less richness
- new oak = prestige but can overpower elegance
- high yield = more money but lower quality

The player should constantly make meaningful decisions.

---

## P3 — WINE TELLS STORIES

Every vintage should feel emotionally unique.

The game should generate memorable harvest years through:
- climate variation
- wine descriptors
- critic reactions
- aging evolution
- market response

The player should remember:
- disastrous frost years
- miraculous harvests
- legendary bottles

---

## P4 — COZY + DEEP

The game atmosphere must feel:
- calm
- warm
- beautiful
- immersive

But beneath the cozy presentation:
- deep management systems
- meaningful optimization
- long-term strategy

The complexity should emerge naturally over time.

---

## P5 — INVISIBLE LEARNING

Players should learn about wine naturally through gameplay.

The game teaches:
- terroir
- viticulture
- climate effects
- wine aging
- fermentation
- appellation logic

Without feeling educational.

---

# GAME VISION

## CORE FANTASY

Transform a small forgotten French vineyard into a world-famous wine estate.

The player evolves from:
- unknown producer
→ respected domaine
→ prestigious château
→ legendary wine icon

---

## PLAYER EXPERIENCE GOALS

The player should feel:
- emotionally attached to their vineyard
- responsible for every harvest
- rewarded for patience
- anxious during difficult climate years
- proud when creating exceptional wines

The game loop should create:
- anticipation
- experimentation
- emotional investment
- replayability

---

# CORE GAMEPLAY LOOP

## MAIN LOOP

Spring
- prepare vineyard
- prune vines
- plan strategy

↓

Summer
- monitor climate
- manage disease
- irrigate
- optimize vine growth

↓

Autumn
- decide harvest timing
- manage harvest risk
- collect grapes

↓

Winter
- ferment wine
- age bottles
- sell inventory
- improve infrastructure

↓

Expand estate
- buy land
- improve cellar
- unlock prestige

↓

Next vintage

---

# MICRO LOOP

The player repeatedly:
- checks vineyard conditions
- analyzes weather
- monitors vine health
- makes tactical decisions
- receives dynamic wine outcomes

This creates emergent gameplay.

---

# ARTISTIC DIRECTION

## VISUAL STYLE

Low Poly Painterly Cozy French Aesthetic

Inspired by:
- Bourgogne
- Provence
- Loire Valley
- French countryside

Visual atmosphere:
- warm sunsets
- rolling vineyards
- lavender fields
- foggy mornings
- stone villages
- underground wine cellars

---

## CAMERA

Isometric 3/4 camera.

Reasons:
- readability
- management gameplay
- visual beauty
- future mobile support

---

## AUDIO STYLE

Music:
- soft piano
- subtle accordion
- smooth French jazz

Ambient sounds:
- birds
- wind
- rain
- vineyard ambience
- cellar sounds

The atmosphere should feel peaceful but emotionally tense.

---

# TECH STACK

| Component | Choice |
|---|---|
| Engine | Godot 4.x |
| Language | GDScript |
| IDE | Kiro |
| Version Control | GitHub |
| Data Format | JSON |
| Art Pipeline | Blender + AI concepts |
| Audio | Lightweight royalty-free packs |
| Target Platform | PC first |

---

# TECHNICAL PHILOSOPHY

## CORE PRINCIPLE — DATA-DRIVEN DESIGN

Gameplay systems should avoid hardcoded data.

All gameplay configuration should come from JSON files:
- grapes
- soils
- climate presets
- economy values
- events
- wines
- regions

Benefits:
- easier balancing
- scalable content
- AI-friendly workflow
- moddability
- lower maintenance cost

---

# ARCHITECTURE OVERVIEW

## PROJECT STRUCTURE

```text
/project
    /assets
    /audio
    /data
    /scenes
    /scripts
    /systems
    /ui
    /autoload
    /resources
    /save