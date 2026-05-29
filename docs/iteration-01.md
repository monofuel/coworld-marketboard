# Iteration 01

**Date**: 2026-05 (during Legends Reel Generation Sprint)  
**Focus**: Initial set of small, personality-respecting dampening + commitment tweaks aimed at reducing self-thrashing and increasing dramatic event density (especially lead changes, crises, and reversals) for better TV legend material.

## Changes Made

- **Zorori** (`players/zorori.nim`): Added anti-thrashing dampener in `PathToNode` → only transition to `EvaluateSell` after >25 ticks of movement. Goal: stop constant flipping while preserving his "only sell under good scarcity conditions" personality.
- **Colm** (`players/colm.nim`): Added light batching guard before flooding the market with -1g undercuts. Goal: create cleaner price pressure waves instead of constant noise.
- **Kukumo** (`players/kukumo.nim`): Small increase to `batchPatience` (2.0 → 2.2) to encourage longer hoarding runs and more visible supply crises.
- **Utility engine** (`players/utility.nim`): Added mild scarcity bias in the interrupt logic — when a bot is gathering a material with very low market supply, the effective interrupt threshold is raised slightly. Goal: help patient hoarders create bigger, more dramatic droughts.
- **R'khenna** (`players/rkhenna.nim`): Added light hysteresis on `EvaluateMarket` (stick with current role decision for ~30 ticks). Goal: make role flips more decisive so they create clearer "mass pivot" moments instead of noisy oscillation.

All changes were intentionally small and reversible.

## Eval Deltas (12k tick runs, fixed mixed lineup)

| Metric                        | Before (early sprint) | After (post-01 changes) | Delta   | Notes |
|-------------------------------|-----------------------|---------------------------|---------|-------|
| Legend events per match       | 137–142               | 170                       | +28–33  | Clear increase in event density |
| Lead changes                  | 25–28                 | 68                        | +40–43  | **Biggest win** — much more dynamic positioning |
| Supply droughts               | 34–39                 | 32                        | -2 to -7| Slightly fewer but still strong |
| Market cornering events       | 13                    | 12                        | -1      | Stable |
| Wealth reversals              | 1                     | 1                         | 0       | Holding |
| Players completing gear       | 8–9                   | 8                         | -1      | Minor |
| Top single-event excitement   | ~161–212              | 228                       | +16–67  | Higher peak drama |
| Match excitement score        | ~334–350              | 378.65                    | +28–44  | Meaningful lift |

## Notable Observations

- The biggest movement was in **lead changes** (+40). This is excellent for TV — constant underdog stories, positioning swings, and reversals.
- Supply droughts and cornering remained high, which is what we want for narrative tension (hoarder + undercutter pressure creating visible crises).
- The combination of old FSM dampeners + utility commitment tweaks is starting to produce "livelier" matches without homogenizing the personalities.
- R'khenna's change in particular seems to have helped turn noisy flipping into more decisive role pressure, contributing to the lead change spike.

## TV / Legends Quality

The 12k-tick matches from this iteration already contain strong material:
- Multiple supply crises
- Sustained cornering
- High volume of lead changes
- At least one wealth reversal per match

These are significantly more watchable than earlier, more static runs.

## Next Direction

Continue the sprint with one or two more targeted tweaks (mix of old FSM and utility personalities), then run another focused batch + legends analysis. Goal is to push lead changes, reversals, and high-excitement events even higher while keeping the personality distinctions clear.

---

*Format is intentionally lightweight and will be refined in later iterations as needed.*
