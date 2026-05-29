# Iteration 06

**Date**: During Legends Reel Generation Sprint  
**Focus**: Small increase to K'torra's (the opportunist) `batchPatience` from 0.5 to 0.8 to allow slightly more gathering before she sells or flips, aiming for better build-ups and sharper opportunistic reactions.

## Changes Made

- **K'torra** (`players/ktorra.nim`): Increased `batchPatience` from 0.5 → 0.8 in her PersonalityWeights.
  - Personality preserved: She remains a high-sell-urgency, high-gear-priority opportunist who reacts quickly. The change is small and keeps her core identity.
  - Intended effect: Slightly less hyper "sell after 2 items" behavior, allowing a bit more inventory pressure to build before she flips or sells. This could lead to more pronounced scarcity moments followed by sharp opportunistic responses.

## Eval Deltas (12k tick runs, same fixed mixed lineup)

Comparison to Iteration 05:

| Metric                        | Iteration 05 | Iteration 06 | Delta | Notes |
|-------------------------------|--------------|--------------|-------|-------|
| Legend events (full matches)  | 156          | 156          | 0     | No change |
| Lead changes                  | 19           | 19           | 0     | Stable |
| Supply droughts               | 45           | 45           | 0     | Stable |
| Market cornering events       | 12           | 12           | 0     | Stable |
| Wealth reversals              | 0            | 0            | 0     | None |
| Players completing gear       | 7            | 7            | 0     | Stable |
| Top single-event excitement   | 339.6        | 339.6        | 0     | Stable |
| Match excitement score        | 360.41       | 360.41       | 0     | No movement |

## Economy / Market Cap (gold + value of all items at base prices)

**Definition**: Total gold held + Total value of *every* item in the simulation (raw materials + gear) at base prices, whether equipped, in inventories, or listed.

From the diagnose run:
- Total gold held: 4,976g
- Total listing value: 119g
- Gear equipped: 32 T1 + 9 T2 (≈ 795g at base prices)
- Additional value in player inventories (raw materials + some gear)

**Est. Total Market Cap (everything at base value)**: ~6,800 – 7,200g range (very similar to recent iterations).

**Change since Iteration 05**: Negligible / essentially flat. Gold and overall value creation remain very stable across these runs.

## Notable Observations

- This tweak had almost no measurable impact on the metrics in this particular deterministic run. The numbers are identical to Iteration 05.
- The sprint has reached a plateau with the current set of small dampening/hysteresis/batching adjustments on the old FSM bots and minor weight tweaks on the utility side.
- Drama metrics (especially droughts, lead changes, and peak excitement) have been relatively stable since the stronger gains in Iterations 02–04.

## TV / Legends Quality

The matches remain at the same solid-but-not-record level as the last iteration. They are still watchable, but we have not pushed the high-drama peaks higher with this change.

Current best candidates for the TV Reel Pack are still the higher-event runs from earlier in the sprint (particularly those with 449+ and 480+ peak excitement).

## Next Direction

We may need a different kind of change for the next iteration — either a more significant (but still small) adjustment to one of the utility bots, a tweak to the legends/excitement detection itself, or exploring a different lever (such as how bots respond to cornering or role pressure). The current style of incremental reactivity dampening is maintaining a good baseline but not breaking new ground in drama.

---

*Plateau reached with the current tweak style.*
