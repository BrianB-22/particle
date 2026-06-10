# Screen Size & Speed Scaling

## The Problem

Game speeds are defined in absolute pts/sec. SpriteKit's `.resizeFill` scale mode expands the scene to fill the window, so at larger sizes (fullscreen on a 14" MBP = ~1512×982 logical pts vs 1180×820 windowed) boids and predators cover a smaller *fraction* of the screen per second. The game feels slightly slower and easier in fullscreen.

## Reference Window

**1180 × 820** pts — the default windowed size used as the baseline for all speed tuning.

## Options Considered

### Option 1 — Width-ratio multiplier (IMPLEMENTED)

Compute `sizeScale = size.width / 1180` in `adaptToCurrentSize()` and multiply all speeds by it at runtime.

**Pros:** One multiplier, minimal code change, invisible to the player.  
**Cons:** Speeds are still expressed as absolute numbers in Config — someone reading the code won't immediately know the runtime value.

**What is scaled:**
- `waveBoidMaxSpeed()` — boid velocity cap per wave
- `wavePredatorMaxSpeed()` — predator velocity cap per wave
- `waveEjectSpeed()` — post-black-hole boid ejection
- `ag.steerStrength` — predator steering/acceleration force (call site in `updatePredator`)
- Ghost predator drift speed (30 cap, 80 entry force)
- `Config.Meteor.speed` — meteor travel speed
- `Config.Meteor.ejectSpeed` — boid ejection on meteor impact
- `Config.minSpeed` — wave 1 boid minimum speed

**What is NOT scaled:**
- Safe zone radii, black hole gravity radius, neighbourhood radii (visual layout, not feel)
- HUD positions, font sizes, UI elements

**Code location:** `sizeScale` var on GameScene, set in `adaptToCurrentSize()`.  
Clamped to `max(0.5, ...)` so extremely small windows don't break physics.

---

### Option 2 — Scale interaction radii / zone sizes, not speeds

Keep speeds fixed, but make safe zones and predator threat radii proportionally larger at bigger screens so the effective challenge stays constant.

**Pros:** Speeds remain the same "feel" — just more real estate.  
**Cons:** Touches more systems (SafeZoneNode, neighbourhood radii, black hole pull radius). More places to miss something.

---

### Option 3 — Fractional screen widths (speed as proportion of screen)

Define all speeds as fractions of screen width per second (e.g. `0.076` not `90`), derive pts/sec at runtime: `speed = fraction * size.width`.

**Current fractions at 1180 reference width:**

| Speed | pts/sec | Fraction of width |
|---|---|---|
| Boid wave 1 | 55 | 0.0466 |
| Boid wave 2 | 95 | 0.0805 |
| Boid max (wave 15+) | 320 | 0.2712 |
| Predator wave 1 | 75 | 0.0636 |
| Predator wave 2 | 120 | 0.1017 |
| Predator max (wave 15+) | 440 | 0.3729 |
| Predator SS L1 | ~10 | 0.0085 |
| Predator SS L3 | ~30 | 0.0254 |
| Predator SS L5 | ~50 | 0.0424 |
| Meteor | 700 | 0.5932 |
| Meteor eject | 220 | 0.1864 |

**Pros:** Resolution-independent from the ground up. Correct architecture for a game targeting multiple display sizes.  
**Cons:** All speed constants become unintuitive decimals. 8–10 constants to rewrite plus wave formulas. Bigger refactor with no gameplay benefit beyond Option 1.

---

## Decision

Option 1 implemented. Revisit Option 3 if the game ships to significantly different form factors (e.g. Apple TV, iPad 12.9") where the width ratio range is large enough that the approximation breaks down.
