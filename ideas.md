# Particle — Feature Ideas

## Hazards
- **Black holes / gravity wells** — pull boids in and destroy them; player has to fight the gravity ✅
- **Neon meteor strike** — wave 3+, 30% chance per wave (tunable in Config); targets the safe zone
  with the most boids (even if it's the only zone); no life lost, no score penalty — ejected boids
  return to wandering and can be re-herded for bonus points; boids ejected with large outward velocity
  burst; destroyed zone replaced by a new one spawning ~3s later, randomly placed away from predators;
  does NOT affect predators or black holes; warning = incoming sound + visible streak only (no UI text,
  no zone flash); visual: fast orange/white-hot neon streak with particle trail + ring shockwave on
  impact; need two sounds: incoming whoosh + impact hit
- **Electric fences / laser grids** — appear mid-wave; boids die if they cross
- **Corrupted boid** — infects neighbors it touches, turning them hostile until cured

## Safe Zone Mechanics
- **Moving safe zones** — drift slowly; player has to time entry
- **Decaying zones** — ring shrinks over time and eventually collapses, ejecting boids
- **Bonus zone** — appears briefly mid-wave, worth double points if filled before it vanishes

## Player Tools
- **Pulse ability** — tap/click repels all nearby boids at once; limited charges per wave
- **Tractor beam** — locks onto nearest boid and pulls it directly
- **Scare** — briefly spawns a fake predator glow at cursor position

## Progression / Variety
- **Boid personality types** — some fast and skittish, some slow and stubborn
- **Splitting predator** — splits into two smaller faster ones after eating enough boids
- **Sonar wave** — safe zones are invisible until a boid gets close; ping reveals them
- **Boss wave** — one giant predator that takes a specific path; can only be tricked, not outrun

## Atmosphere
- **Black holes** ✅ — gravity well pulls boids in and destroys them
- **Storm effect** — screen-wide turbulence briefly randomizes boid direction
- **Boid light trails** ✅ — fading trails show where the herd is moving
