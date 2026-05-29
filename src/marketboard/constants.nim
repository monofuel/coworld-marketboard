## Shared simulation and replay constants
##
## This module centralizes core rates and defaults so that the server,
## replays, viewers, and tools all agree on the authoritative tick rate
## and default playback behavior.

const
  GameTPS* = 24
    ## Authoritative simulation tick rate (ticks per second).
    ## The live server runs at this rate. Replays are recorded against it.

  DefaultReplayMultiplier* = 1
    ## Default playback speed multiplier (1 = original recording speed).

  PlaybackSpeeds* = [1, 2, 3, 4, 8]
    ## Available playback speed multipliers for replay viewers.
    ## These are indices into this array via speedIndex.

  MbReplayFps* = GameTPS
    ## Frames per second used when recording and timing replays.
    ## Kept as a separate name for clarity in replay code, but tied to GameTPS.

  # Legend timing (in sim ticks at 1x speed)
  BaseLegendDisplayTicks* = 96
    ## How long a legend caption lives in simulation ticks when running at 1x.
    ## At higher multipliers this is typically scaled so wall-time duration
    ## remains consistent.

  # Legend generation rules (tick-based)
  DroughtThresholdTicks* = 48
  MassRoleSwitchWindow* = 48
  PriceEventCooldown* = 192
    ## Minimum ticks between price spikes/crashes per item.
