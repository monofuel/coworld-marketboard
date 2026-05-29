# Graphics & UI Improvements for Marketboard

Marketboard's current graphics are intentionally minimal. The global/fullmap view uses a custom sprite protocol on top of bitworld's infrastructure, but the visual execution is very basic compared to sibling Coworld projects.

This document outlines concrete improvements we should make to bring the visuals up to the standard of other games in the ecosystem (crewrift, heartleaf, asteroid-arena, etc.).

## Current State (as of late 2026)

- **Protocol**: We correctly use the bitworld sprite protocol (layers, objects, compressed sprites) via the shared `global_client.nim`.
- **Rendering**: Custom `global_render.nim` that manually builds init + frame packets.
  - One zoomable map layer
  - Simple UI layers for scoreboard, legends, and (toggleable) debug tick counter
- **Assets**: A handful of basic PNGs in `data/` (palette, letters, numbers). No Aseprite pipeline.
- **Typography**: Basic blocky/tiny fonts rendered at runtime.
- **Visual Style**: Colored rectangles for players, basic progress bars, text-only scoreboard and legends. Very "programmer art."
- **Recent Wins**:
  - Scoreboard height increased to prevent cutoff.
  - Debug tick counter made optional via `--tick` flag (disabled by default).
  - Time-based replay stepping + speed multiplier support.

The result works functionally for iteration and lobby TVs, but looks significantly less polished than peer projects.

## Key Problems

1. **No real asset pipeline** — Everything is hand-authored minimal PNGs. Other games use Aseprite extensively for spritesheets, UI, animations, and characters.
2. **Minimal reuse of shared bitworld components** — We reimplement a lot of what lives in bitworld's `client/data/` (fonts, UI atlas elements) and what other games have built (aseprite loaders, resource systems, pixelfont helpers).
3. **Very basic UI layers** — Scoreboard and legends are functional but lack visual hierarchy, animations, or polish.
4. **No animations or visual feedback** — Players don't animate, no particle effects, no state transitions, limited use of color/emphasis.
5. **Hardcoded / limited visual vocabulary** — Player representation is just 7x7 colored squares. Other games have proper character sprites, clothing layers, expressions, etc.
6. **Debug/UI elements still feel bolted on** — Even with the recent `--tick` flag, the overall aesthetic is "prototype" rather than "game."

## Recommended Improvements

### 1. Adopt a Proper Aseprite Asset Pipeline (Highest Priority)

Look at how sibling projects do this:

- **crewrift**: `src/crewrift/aseprite.nim` + `resources.nim`
- **heartleaf**: `src/heartleaf/aseprite.nim` + `resources.nim`
- **bitworld** itself: `client/data/` contains many `.aseprite` + exported PNGs

**Actions**:
- Create (or copy/adapt) an `aseprite.nim` module that can read Aseprite JSON exports.
- Define a clear asset structure in `data/` (e.g. `characters/`, `ui/`, `effects/`, `environment/`).
- Export a proper atlas + metadata instead of scattered PNGs.
- Support animation frames and tags.

### 2. Reuse and Extend Shared Bitworld Graphics Primitives

- Use the fonts and UI elements from `../bitworld/client/data/` (tiny5, transport, atlas with buttons/dpad, etc.).
- Consider forking or contributing to bitworld's common `pixelfonts.nim` and framebuffer helpers instead of rolling our own.
- Align our layer kinds and anchoring strategy with what the shared `global_client.nim` expects for best results.

### 3. Improve the Global / Fullmap View

The lobby-TV global view is one of our main deliverables. Make it look good:

- Richer scoreboard (icons, better typography, visual states for roles/levels).
- Animated or more expressive player representations on the map.
- Better legend/event presentation (icons, color coding by excitement, subtle animations).
- Consistent visual language with other Coworld games (colors, icon style, UI chrome).
- Optional "cinematic" mode for the TV displays (hide debug, nicer framing).

### 4. Player View Polish (Future)

While the current focus is the global spectator view, the player view will eventually need love too:

- Proper character sprites instead of colored squares.
- Equipment visualization.
- Better stall / market UI.
- Animated gathering/crafting actions.

### 5. Technical / Architectural Improvements

- Move more rendering logic into reusable modules (similar to how crewrift has `common/`).
- Add support for sprite atlases and batched rendering where possible.
- Make the legend and scoreboard systems more data-driven (define layouts in data files rather than code).
- Support for particle-like effects or simple VFX (important for "exciting" economy moments).
- Better integration with the bitworld client (e.g. using more of its built-in UI layer kinds and anchoring).

## Prioritization Suggestion

1. **Aseprite pipeline + basic character sprites** (biggest visual jump)
2. **Reuse bitworld fonts + UI atlas elements**
3. **Polish the global scoreboard + legend presentation**
4. **Add simple animations / state visuals** for players and actions
5. **Make the global view feel like a first-class "lobby TV" experience**

## References / Examples to Steal From

- `../bitworld/client/` — the canonical protocol + client implementation and asset examples.
- `../coworld-crewrift/src/crewrift/` — mature Aseprite + resource system + rich global UI.
- `../coworld-games/coworld-heartleaf/src/heartleaf/` — cleaner, smaller example of the same patterns.
- `../coworld-games/coworld-tribal-quest/docs/asset_pipeline.md` — explicit documentation of their process.
- `../bitworld/docs/sprite_v1.md` — protocol specification.

## Open Questions

- Should we try to upstream useful marketboard rendering components back into bitworld?
- How much of the current custom `global_render.nim` logic should we keep vs. replace with shared patterns?
- Do we want a "cinematic" global spectator mode that looks different from the in-game global view?

---

*Document created to guide focused graphics work while another agent handles AI/eval.*

## Recent Autonomous Progress

Implemented the quick-win graphics tasks without manual art direction:

- **Palette fix (bright red ground)**: Copied canonical `pallete.png` from `../bitworld/client/data/` into `data/pallete.png`. Added real loader in `loadRenderAssets` (sim.nim:1251) that forces `Palette[]` from local PNG (bitworld's `loadPalette` ignores its arg and bakes old embed). Remapped terrain indices in sprite_protocol.nim:304 and sim.nim object sprites: grass 3->11 (now 0,228,54 vibrant green), path 13->5, wall 5->12, plus wood/hardwood outlines for visual match. Verified: ground no longer awful red.
- **Typography**: Good `readTiny5Font` from bitworld/pixelfonts already in use for compact scoreboard text. Kept the big outlined blocky font (letters.png + numbers.png via renderBlockyTextToRgba) for legends + debug tick — easy to read across the room on lobby TVs. No change there.
- **Player sprites**: Replaced crude 7x7 square-blob in `makeRgbaPlayer` (sprite_protocol.nim:124) with clearer head+arms+torso+stance silhouette. Affects map agents + identity swatches.
- **UI atlas + scoreboard/legend polish**: Synced `shell.png` + `dpad.png` from bitworld atlas into `data/atlas/` (ready for icons without bloat). Scoreboard uses tiny5 + swatches (height pre-fixed at 256). Legends keep their large blocky letters at original sizing for readability; palette + other tweaks improve overall contrast/hierarchy for the spectator view.
- **Other**: `make check` passes clean. All changes minimal, follow Nim style (## docs inside procs, grouped consts, sibling source reliance, no unrelated refactors). Palette loader + green ground, player shapes, and atlas staging landed. Blocky for legends preserved per preference.

Next candidates (still autonomous-friendly): wire one atlas icon (e.g. shell as legend marker), directional player variants (4 facings x roles), header in scoreboard layer, or full Aseprite pipeline if we vendor crewrift's aseprite.nim.

All per "delete > simplify" and lobby-TV clean spectator rules.