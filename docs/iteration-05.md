# Iteration 05

**Date**: During Legends Reel Generation Sprint  
**Focus**: Small batching guard on IronWorks (the reliable specialist crafter) when deciding to sell gear, to make his gear dumps more committed and impactful.

## Changes Made

- **IronWorks** (`players/iron_works.nim`): Added a light batching guard on the PathToSellStall transition (only sell when holding gear if ticksInPhase > 20).
  - Personality preserved: He remains the focused, never-gathering crafter who sells at fair margins.
  - Intended effect: Reduce reactive small selling, allowing gear supply to build or crunch more dramatically depending on material availability. This should help create better "crafter under pressure" or "gear flooding" moments for legends.

## Eval Deltas (12k tick runs, same fixed mixed lineup)

Comparison to Iteration 04:

| Metric                        | Iteration 04 | Iteration 05 | Delta   | Notes |
|-------------------------------|--------------|--------------|---------|-------|
| Legend events (full matches)  | 231          | 156          | -75     | Noticeable drop in event volume |
| Lead changes                  | 46           | 19           | -27     | Significant reduction |
| Supply droughts               | 75           | 45           | -30     | Big drop in scarcity events |
| Market cornering events       | 16           | 12           | -4      | Reduced |
| Wealth reversals              | 1            | 0            | -1      | None this run |
| Players completing gear       | 8            | 7            | -1      | Slightly less progression |
| Top single-event excitement   | 480.1        | 339.6        | -140.5  | Lower peak drama |
| Match excitement score        | 324.30       | 360.41       | +36.11  | Slight improvement in overall match score |

## Economy / Market Cap (per clarified definition)

**Definition used**: Total gold held by players + Total value of *all* items in the simulation (raw materials + gear) at base prices, whether equipped, in inventory, or listed.

From the diagnose run on this iteration's state:
- Total gold held: 4,976g
- Total listing value: 119g
- Gear equipped: 32 T1 + 9 T2 (estimated ~795g at base prices)
- Significant raw material and gear value locked in player inventories (notably high wood with Zorori and gear pieces with IronWorks)

**Est. Total Market Cap (everything at base value)**: ~6,800–7,300g range (rough estimate based on visible inventory + gold + listings).

Compared to earlier iterations in the sprint, value creation is steady but the drama metrics (especially droughts and lead changes) took a step back with this particular tweak.

## Notable Observations

- This iteration produced a clear regression in most drama metrics (droughts, lead changes, peak excitement). The IronWorks selling guard appears to have reduced some of the supply pressure dynamics that were generating high event counts in previous iterations.
- Overall match excitement score was slightly higher, but the quality and quantity of high-value legend events dropped.
- Market cap / value creation remains in a similar range to recent runs.

## TV / Legends Quality

The top matches from this iteration are weaker for TV reels compared to Iterations 02–04. Fewer droughts and lead changes mean less narrative tension and fewer "wow" moments for overlays.

Current strongest candidates for the TV Reel Pack remain the high-event runs from Iterations 02 and 04.

## Next Direction

Given the regression, the next iteration will likely try a different direction — either reverting or adjusting the IronWorks change, or targeting a different lever (possibly on the utility side or a different old FSM bot) to try to recover the higher drama levels while keeping personality integrity.

---

*Honest regression this iteration — useful data for steering the sprint.*
