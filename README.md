# Vector Divide — Fun City Arcade

**Version: v0.3.0 (build 3) — Classic + Modern / Containment**

Vector Divide is an original native macOS territory-capture arcade game inspired by the genre established by the 1981 arcade game Qix. It does not use the original game's code, graphics, sounds, logo or other assets, and is not affiliated with its rights holders.

This is an independent Xcode project with its own GitHub repository. Fun City can launch the built application using **ADD GAME**; it is not embedded into the launcher.

## Clone and run on your Mac

For a fresh local checkout:

```sh
mkdir -p ~/Documents/GitHub
cd ~/Documents/GitHub
git clone https://github.com/peter-dietrich/vector-divide.git
cd vector-divide
open VectorDivide.xcodeproj
```

In Xcode 16+, select the **VectorDivide** scheme, **My Mac**, and press Command-R. Requires macOS 14+. The bundle ID is `io.vectordivide.game`.

For updates after the initial clone:

```sh
cd ~/Documents/GitHub/vector-divide
git pull --ff-only origin main
open VectorDivide.xcodeproj
```

If you already cloned the older downloadable Git bundle, see [docs/GITHUB_SETUP.md](docs/GITHUB_SETUP.md) before syncing: that bundle has an independent local Git history and must not be blindly merged with the GitHub bootstrap.

Build from Terminal (macOS only):

```sh
xcodebuild -project VectorDivide.xcodeproj -scheme VectorDivide -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

## Controls

| Control | Action |
| --- | --- |
| Return | Start, advance level, or restart |
| Arrow keys / WASD | Move on safe paths or guide an active open trace |
| Hold Space + direction | Fast trace (lower points) |
| Hold Shift + direction | Slow trace (double points) |
| P | Pause/resume |
| R | New game |
| Click game board | Restore keyboard focus |

Start an open line from protected territory. Reconnect to a safe border to capture regions without enemies. Avoid energy anomalies, boundary sparks and the fuse that catches idle open traces. Capture **75%** to complete the level.

## v0.3.0 — Modern / Containment

- **Classic / Modern selector** lets you switch graphics live without resetting the current game, changing physics, or replacing a saved session. Choice persists on this Mac.
- Modern mode introduces a newly written, opaque, layered reactor environment: solid armored captured tiles, dimensional machinery, animated reactor cores, illuminated capture barriers, rotating armored threats, sentry units, and an original command drone.
- Classic retains the original wireframe environment and colors, with unchanged game rules.
- Standard Veteran starts at **2.5× the previous default enemy velocity** (17.75 cells/second at level one; Cadet and Ace still apply their skill multipliers). Custom Game speed now ranges **0.5×–4.0×** of the prior baseline.
- Saved games from v0.2.0 retain their previously configured speeds, so loading an older session does not silently change an active game.
- The new rendering layer is intentionally independent of gameplay and save-state encoding.
- Uses no commercial artwork, licensed content or external dependencies.

## v0.2.0 gameplay and persistence

- v0.2.0 raised base enemy velocity from 6.1 to 7.1 cells/second; v0.3.0 now applies 2.5× as the standard starting speed.
- **Scores** opens a local top-ten leaderboard with initials, achieved level and difficulty. Qualifying runs prompt for up to three initials at Game Over. Earlier single best score is migrated into the table. Scores are local to this Mac, not yet aggregated in Fun City.
- **Custom** opens adjustable starting lives, additional enemies, enemy speed, spark speed, drawing speed, target territory and fuse delay. Save and delete named custom-game presets independently of in-progress battles.
- **Save** writes the full grid, trail, enemy movement, timers, score, difficulty and rules to one of eight local save slots.
- **Load** restores a saved game in a paused state. Press P or Return to resume; level-clear states continue with Return.
- Challenge customization begins a fresh session; custom scores share the local board with standard scores and are labeled by base difficulty.
- All local data uses UserDefaults; there is no external server or account.

## v0.1.0 implementation

- Original 68 × 44 grid simulation and orthogonal territory tracing.
- Region flood-fill that respects multiple enemies.
- Slow/fast scoring, level bonus, three difficulty settings, multiple lives and progressive levels.
- Native SwiftUI / AppKit window with procedural vector artwork and telemetry.
- Local high-score record and three-letter initials via UserDefaults (expanded into the v0.2.0 top-ten table).
- On-screen version from Xcode `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.
- No bundled third-party assets, external packages or network dependence.

## Validation

The v0.1.0 standalone engine passed Linux Swift 6.2 smoke tests. The v0.2.0 regression test now covers new settings and snapshot encoding. **The v0.3.0 full macOS Xcode app requires CI validation and in-person Mac gameplay testing.**

```sh
bash scripts/test_engine.sh
```

The source code, artwork generated by code, Xcode project, test code and documentation are stored in this repository; do not store built binaries or personal saved-game data here.

## Version strategy

- **0.1.x**: initial classic prototype.
- **0.2.x**: custom rules, high scores, snapshots, classic refinement and bug fixes.
- **0.3.x**: two selectable visual modes sharing the same game engine; modern renderer and balancing refinement.
- **1.0.0**: only after successful Mac validation, gameplay testing and Fun City integration.

Design ideas for the modern edition are documented in [docs/MODERN_DIRECTION.md](docs/MODERN_DIRECTION.md).
