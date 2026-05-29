# Iteration 02

**Date**: During Legends Reel Generation Sprint  
**Focus**: Small hysteresis improvement to Solenne (the altruistic gap-filler) to reduce overly reactive role switching, aiming for more committed "heroic" behavior during market crises and higher-quality dramatic events.

## Changes Made

- **Solenne** (`players/solenne.nim`): Added light hysteresis on `EvaluateRole`. She now sticks with her current role decision for ~25 ticks before re-evaluating market gaps. 
  - Personality preserved: She still tries to fill holes altruistically.
  - Intended effect: Cleaner "altruist holding the line during drought/cornering" stories and more decisive MassRoleSwitch or WealthReversal moments instead of constant flipping.

This was the only code change in this iteration.

## Eval Deltas (12k tick runs, same fixed mixed lineup)

Comparison to Iteration 01 results:

| Metric                        | Iteration 01 | Iteration 02 | Delta    | Notes |
|-------------------------------|--------------|--------------|----------|-------|
| Legend events (full matches)  | 170          | **232**      | +62      | Strong increase in event volume |
| Lead changes                  | 68           | 42           | -26      | High but down from previous spike |
| Supply droughts               | 32           | **76**       | **+44**  | Excellent — much more visible scarcity drama |
| Market cornering events       | 12–13        | **17**       | +4–5     | Good rise in exploitation moments |
| Wealth reversals              | 1            | 1            | 0        | Stable |
| Players completing gear       | 8            | 8            | 0        | Consistent |
| Top single-event excitement   | 228          | **449.1**    | **+221** | Very large jump in peak drama |
| Match excitement score        | 378.65       | 364.31       | -14      | Slight dip but still strong |

## Notable Observations

- The biggest wins were in **supply droughts** (+44) and **peak event excitement** (doubled to 449). This suggests the Solenne tweak helped create longer, more sustained crisis periods that the legends system rewards heavily.
- Cornering also increased, which is great for TV (clear "someone is screwing the market" moments).
- Lead changes were still very high (42), even if not quite at the previous spike level.
- One of the three runs was a shorter 4k-tick match with much lower numbers (as expected). The two full 12k-tick matches were the strong ones.

## TV / Legends Quality

This iteration produced some of the highest-excitement individual events we've seen so far (449 peak). The combination of high drought + cornering counts with sustained lead changes creates excellent narrative arcs for highlight reels.

The top matches from this run (`match_0001.mbreplay` and `match_0002.mbreplay`) are currently among the best candidates for the TV Reel Pack.

## Next Direction

Continue with one more small targeted tweak (possibly to another old FSM bot or a utility scoring adjustment), then run the next focused batch + legends analysis. We are successfully pushing the "crisis density" metrics that matter most for exciting, watchable matches.

---

*Format evolving. Feedback welcome.*
