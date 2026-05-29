# TV Reel Pack — Marketboard

## Goal
Curated set of high-drama, personality-rich matches that are directly watchable on a TV (living room / hallway style) using the existing replay viewers with timed legend overlays.

These matches highlight the core research theme: heterogeneous agent personalities interacting in a social dilemma economy, including hoarding, undercutting, role pivots, supply crises, and wealth reversals.

## How to Play the Reels

### Recommended Viewer (best for TV / group viewing)
```bash
nim r src/marketboard/fullmap_viewer.nim --replay:replays/match_0001.mbreplay
```

- Use arrow keys or on-screen controls to seek.
- Legend events fire automatically as timed text overlays at the exact ticks.
- Higher-excitement events are prioritized.

Alternative (single-player follow cam):
```bash
nim r src/marketboard/replay_viewer.nim --replay:replays/match_0001.mbreplay
```

### Quick Legend Inspection
```bash
nim r tools/analyze_legends.nim --replay:replays/match_0001.mbreplay
```

## Current Recommended Pack (as of this sprint)

**Top tier (strong narrative arcs, high event density):**

- `replays/match_0001.mbreplay` + `match_0001.legends.json` (and the deterministic duplicates 0002, etc. from the same run)
  - ~142 legend events
  - 28 lead changes
  - 39 supply droughts
  - 13 market cornering events
  - 1 wealth reversal
  - 9 players completing gear
  - Clear supply pressure from hoarder/undercutter personalities leading to pivots and reversals

All three matches from the final focused batch run are essentially identical in content (fixed lineup determinism) and excellent for TV.

## How These Reels Were Generated (for reproducibility)

1. Small personality-respecting tweaks:
   - Zorori (hoarder): anti-thrashing dampener on EvaluateSell transitions.
   - Colm (undercutter): light batching guard before flooding.
   - Kukumo (utility hoarder): modest batchPatience increase for longer crises.
   - Utility engine: slight scarcity bias on interrupt threshold during low-supply gathering (helps patient bots create more visible droughts).

2. Focused eval runs:
   ```bash
   nim r tools/batch_market.nim --matches:3 --ticks:12000 --fixed-lineup
   nim r tools/analyze_legends.nim --replay-dir:replays/ --top:3
   ```

3. Curated the highest event-density / excitement matches.

## Future Regeneration

The same small changes + the above two commands will produce comparable or better reels as the bot personalities continue to improve.

## Notes on What Makes These Exciting for TV
- Supply droughts + cornering from hoarder + undercutter personalities create clear "crisis" moments.
- Wealth reversals and lead swings provide satisfying underdog / comeback stories.
- Multiple gear completions + role tension show specialization and adaptation under pressure.
- The mix of old rigid FSM bots and newer scored-commitment bots creates visible contrast in behavior during stress.

These are not "perfect economy" runs — they are *dramatic* social-dilemma stories, which is the intended output for this project.
