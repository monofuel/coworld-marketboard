import os

const RootDir = thisDir()

# Local source roots for this project.
# "src" gives us the package-style imports: import marketboard/sim, etc.
# "players" gives us the flat bot personality imports: import common, import still_forge, etc.
switch("path", RootDir / "src")
switch("path", RootDir / "players")

switch("threads", "on")
switch("mm", "orc")

when not defined(debug):
  --define:release
  --define:noAutoGLCheck

# Note: External dependencies (bitworld, mummy, pixie, etc.) are provided
# automatically by the nim.cfg generated via `nimby sync -g nimby.lock`.
