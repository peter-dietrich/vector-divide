# Vector Divide — modern visualization study

## Creative direction: **CONTAINMENT**

The original line-drawing mechanic becomes a cinematic energy-containment system. You command a moving *field architect* that stitches brilliant energy walls across unstable environments. Each capture seals a region, extinguishes the fog inside it, and reveals an underlying world or engineered structure.

This should look like a polished modern arcade game, **not** a transparent wireframe laid over stock graphics. Art, particles, lighting and HUD are distinct production systems, while capture logic remains in `DivideEngine`.

### Environment candidates

1. **Neon reactor** — colossal dark reactor interior; captured regions become pulsing armor panels, and enemies are electrical arcs.
2. **Cyber metropolis** — luminous aerial city grid; secured regions light blocks of buildings while the remaining sector stays black and dangerous.
3. **Ocean trench** — deep-sea bioluminescent research site; clean fields illuminate structures and creatures under the water.
4. **Alien ruin** — layered monolithic geometry; captures activate buried symbols and structures, with an unstable anomaly in the open field.

### Motion and feedback

- Active trace: sharp, readable luminous energy ribbon with risk progression.
- Capture: a fast, localized sealing wave, followed by a solid new surface rather than glass transparency.
- Threats: distinct silhouettes and attack motion rather than mere recolored Qix-line copies.
- Sparks: animated patrol drones along the boundary and captured circuits.
- HUD: refined, legible telemetry consistent with Fun City's newer games, not an imitation of a vintage Qix cabinet.
- Preserve 4-direction movement and 75% objective across graphical modes.

### Implementation sequencing

1. Prove territory-capture, fail states, and game feel in Classic, including Mac key-focus behavior.
2. Tune enemy collisions, pacing, and boundary AI using player feedback before graphical complexity.
3. Establish a shared renderer protocol or read-only rendering snapshot derived from the engine.
4. Produce one premium modern arena (recommend **Neon reactor**) before branching into the other environments.
5. Add performance budget, effects/reduced-flash settings and Mac QA, then modern-mode selection in UI.

**IP discipline:** derive gameplay concepts from the broader territory-capture genre; do not incorporate the Qix name, logo, audio, original sprite designs, game source code, or distinctive commercial trade dress into the shipped game.
