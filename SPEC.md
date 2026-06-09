# Particle — Game Specification

## Overview

Particle is a casual arcade game with a neon 80s/90s aesthetic. The player uses the mouse to shepherd glowing boids (particle-like creatures) into safe zones before predators hunt them down. Inspired by Craig Reynolds' 1986 Boids algorithm and the classic Swarm screensaver.

**Platforms:** macOS (primary), iOS/iPadOS (planned)  
**Engine:** SpriteKit  
**Language:** Swift  
**Distribution:** Swift Package Manager executable (macOS POC), native app targets planned

---

## Aesthetic

- Deep dark purple/black background with a faint dot grid
- Neon palette: electric cyan, hot pink, acid green (boids), orange (predators), purple (safe zones), deep purple/violet (wormhole)
- Monospace font (Courier-Bold) throughout all UI
- All effects use glow, bloom, and particle bursts — no photorealistic rendering

---

## Game States / Phases

| Phase | Description |
|---|---|
| `title` | Attract screen with ambient boids and scrolling high scores |
| `playing` | Active wave gameplay |
| `waveComplete` | Between-wave animation and score display |
| `gameOver` | Overlay shown when lives reach zero |
| `enteringInitials` | Player types 3-letter initials for the scoreboard |
| `scoreboard` | Top 10 persistent high scores displayed |

---

## Title Screen

- 35 ambient boids drift with gentle wander (no predators, no HUD)
- "PARTICLE" title pulses in hot pink at 72pt
- Tagline: *herd the swarm · escape the predators*
- Controls hint: *hover to attract · right-click to repel*
- Pulsing purple "CLICK TO START" button
- **Scrolling high score ticker** at bottom of screen (waves upward through a crop window, looping):
  - Gold / silver / bronze for top 3, white for the rest
  - Columns: Rank · Initials · Score · Wave · Date (MM/DD/YY)
  - Top and bottom edges fade out for arcade feel
- Background intro music loops at 80% volume

---

## Controls

| Input | Action |
|---|---|
| Mouse hover / move | Attract nearby boids toward cursor |
| Left mouse button (hold) | Attract mode active |
| Right mouse button (hold) | Repel mode — push boids away |
| Mouse drag | Continue attracting/repelling while moving |

Mouse influence uses **linear falloff** within `rPlayer` (190px) radius, scaled up proportionally with wave speed so the player's authority stays consistent at any difficulty level.

---

## Boids

### What is a Boid?
A boid ("bird-oid object") is an agent that follows Craig Reynolds' three emergent flocking rules: **Separation** (avoid crowding neighbors), **Alignment** (steer toward average heading of neighbors), **Cohesion** (steer toward average position of neighbors). Together these produce organic swarm behavior with no central control.

### Properties
- **Count:** 50 per wave (constant)
- **Colors:** Random from palette — electric cyan, hot pink, acid green
- **Visual:** Glowing core (4px radius) + soft halo (10px radius)
- **Physics:** Velocity-based with per-frame damping; wave-scaled min/max speed

### Lifecycle States

| State | Visual | Behavior |
|---|---|---|
| `spawning` | Neon color, dim glow | Fading in, not yet active |
| `wandering` | Neon color, medium glow | Normal flocking |
| `threatened` | White core, red halo | Predator within 115px |
| `safe` | Brighter neon, strong halo | Inside a safe zone |
| `dying` | — | Death animation playing |

### Physics Config (Wave 1 baseline)

| Parameter | Value |
|---|---|
| Max speed | 55 px/s (wave 1) |
| Min speed | 6 px/s (wave 1), 42% of max (wave 2+) |
| Damping | 0.965 (wave 1), decreasing each wave |
| Separation radius | 28px |
| Alignment radius | 55px |
| Cohesion radius | 80px |
| Threat radius | 115px |
| Catch radius | 22px |
| Player influence radius | 190px |

### Force Weights

| Force | Weight |
|---|---|
| Separation | 1.0 |
| Alignment | 0.6 |
| Cohesion | 0.35 |
| Wander noise | 0.18 |
| Flee predator | 0.7 |
| Mouse influence | 3.5 × speed scale |

Flee force is **suppressed at point-blank range** (< catch radius) so predators can land kills. Boids do not flee ghost-phase predators.

### Death Animation
1. Core flashes white and spikes to 2.2× scale (0.07s)
2. Core implodes to zero while halo blooms and fades (0.28s)
3. Two shockwave rings expand from the position (colored + white, staggered)
4. 10 sparks fly outward at random angles in the boid's neon color, orange, and white

---

## Predators

### Properties
- Orange glowing body (9px radius) with pulse animation
- Count scales with wave: `1 + (wave - 1) / 3`
- Faster than boids at every wave level — can actively hunt

### Speed Scaling

| Wave | Predator max speed | Boid max speed |
|---|---|---|
| 1 | 75 px/s | 55 px/s |
| 2 | 120 px/s | 95 px/s |
| N (3+) | 120 + (N-2) × 20, cap 440 | 95 + (N-2) × 16, cap 320 |

### Behavior

**Ghost phase (wave start grace period):**
- Spawns invisible (alpha 0), fades in over 2 seconds as a **blue ghost**
- Drifts slowly for another 2 seconds — fully visible but not hunting
- At 4 seconds: **activation flash** (white burst → snaps to orange), begins hunting
- During ghost phase: boids don't react, no catches, no flee response

**Active hunting:**
- Pursues nearest non-safe boid using **predictive steering** (leads the target)
- Steers around safe zones with quadratic avoidance force
- Shows a brighter red body color when within 80px of target

**Wave end (rage exit):**
- Shakes and grows (0.96s) then shrinks and vanishes (0.3s)
- `pred_lose` sound plays at start of rage exit

---

## Safe Zones

### Waves 1–3 (Tutorial)
- Always **3 zones**
- **Unlimited capacity** — any number of boids can enter
- Label: "SAFE" in purple
- Large radius (baseline `safeZoneRadius()`)

### Wave 4+ (Capacity System)
- **1–3 zones** chosen randomly each wave
- **Total capacity always ≥ boid count** — the wave can always be completed
  - Remainder distributed as +1 to some zones (never rounds down below survivability)
- Zone **radius reflects capacity**: 1 zone = large (1.0×), 2 zones = medium (0.85×), 3 zones = small (0.72×)
- Centre label shows **remaining slots**, counting down as boids enter
  - > 66% remaining: cyan
  - 33–66% remaining: yellow
  - < 33% remaining: orange
  - Full: red "FULL" label

### Full Zone Behavior
- When full: ring turns red and pulses faster, zone briefly shakes
- New boids **cannot enter** — enforced by a **hard position constraint** (not just a force)
  - Each frame after physics: any non-safe boid inside a full zone is moved to the zone surface and its inward velocity is reflected (physical bounce)
  - This cannot be overridden by mouse force

### Zone Repositioning
Safe zones reposition at every wave advance with a 0.7s fade-in. Zone radius shrinks every 5 waves (minimum 38px).

---

## Wave System

### Wave Progression

| Metric | Formula |
|---|---|
| Wave timer | `max(90 - (wave-1) × 3, 40)` seconds |
| Boid max speed | See Predators table |
| Predator count | `1 + (wave-1) / 3` |
| Safe zone radius | `max(65 - floor((wave-1)/5) × 7, 38)` |

### Wave Start Sequence
1. Boids ejected from safe zones with outward velocity scaled to wave
2. New safe zones fade in at randomised positions
3. Wave predator count spawned in ghost phase (4s grace period)
4. Timer starts; gameplay begins

### Wave Complete
- Triggered when all non-dying boids are either safe or eliminated
- Score bonus: `(seconds remaining × 2) + (safe boid count × 5)`
- "WAVE N CLEAR +X" banner shown
- All predators play rage exit animation simultaneously
- `pred_lose` sound effect

### Timer Expiry
When the wave timer reaches zero, a predator is added as a pressure mechanic.

---

## Wormhole

Appears starting wave 5 with a **50% random chance per wave**.

### Spawn Conditions
- Triggered once per wave when ≥ 50% of boids are safe
- Spawns at a point maximally far from all boids and safe zones (7×5 grid search, 2 jittered samples/cell)

### Visual
- Inner ring: 10 dots orbiting counter-clockwise (1.7s)
- Outer ring: 7 dots orbiting clockwise (3.1s)
- Event horizon glow ring pulses
- Faint gravity-field disc (160px radius)

### Mechanics
- **Gravity field** (160px radius): pulls boids toward centre with quadratic falloff, scales with alpha during fade-in
- **Kill zone** (24px radius): destroys boids once wormhole alpha > 0.7 (not lethal while materialising)
- Drifts slowly with random initial velocity

---

## Scoring

| Event | Points |
|---|---|
| Boid reaches safe zone | +10 |
| Wave clear bonus | (seconds remaining × 2) + (safe boids × 5) |

Score is persistent per session. A floating "+10" label animates from each boid as it enters a safe zone.

---

## Lives

- Player starts with 3 lives
- Each boid killed by a predator or wormhole costs 1 life
- At 0 lives: game over

---

## HUD

| Element | Position | Color |
|---|---|---|
| Score | Top-left | Yellow |
| Lives | Top-right | Hot pink |
| Wave | Top-center | Cyan |
| Timer | Second row center | Cyan → orange (≤20s) → red (≤10s) |
| SAFE: X FREE: Y | Second row left | Acid green |

---

## Audio

| File | Trigger | Volume |
|---|---|---|
| `background_intro.wav` | Title screen (loops) | 80% |
| `background_gameplay.wav` | Wave gameplay (loops) | 40% |
| `boid_safe.wav` | Boid enters safe zone | 70% |
| `boid_dead.wav` | Boid killed | 70% |
| `pred_lose.wav` | Wave clear rage exit starts | 70% |
| `wormhole_appear.wav` | Wormhole spawns | 70% |
| `gameover.wav` | Game over | 70% (one-shot) |

All effect sounds use a pool of 6 `AVAudioPlayer` instances per effect with an 80ms debounce to prevent cutting each other off during rapid events.

---

## High Score System

### Storage
Persistent via `UserDefaults` (key: `particle_highscores`), encoded as JSON. Top 10 scores retained.

### Entry
1. Game over screen shows score/wave for 1.8 seconds
2. Initials entry prompt: type 1–3 letters, Backspace to delete, Return (or auto after 3 chars) to confirm
3. Empty entry defaults to "AAA"

### Scoreboard Display
- Full-screen overlay after initials entry
- Columns: Rank · Initials · Score · Wave · Date (MM/DD/YY)
- New entry highlighted in gold
- Click anywhere to return to title screen

### Title Screen Ticker
- Scores scroll upward through a 130px-tall crop window at the bottom of the title screen
- Loops seamlessly; 1-second pause before first scroll
- Gold / silver / bronze for top 3, white for rest

---

## Debug Keys (development only)

| Key | Action |
|---|---|
| `w` | Win current wave instantly (scatter all loose boids into safe zones) |
| `k` | Kill one wandering boid |

---

## Technical Notes

- **Boid flocking** runs O(n²) neighbor search each frame — acceptable at n=50
- **Spawn placement** uses a 7×5 grid with 2 jittered samples per cell, picking the candidate maximally far from all existing boids and safe zones
- **Safe zone boundary enforcement** uses position correction (not forces) so full zones act as solid walls regardless of player mouse strength
- **SPM resources** use `.process("sounds")` which flattens all files to the bundle root — no subdirectory in URL lookups
- **Predator catch** is checked at the top of `updateBoid` before position is updated, preventing fast-moving boids from tunnelling through the catch radius
