import std/[json, monotimes, os, parseopt, strutils, times]
import pixie, silky, windy
import bitworld/protocol, bitworld/server, marketboard/sim, marketboard/replays, marketboard/legends
import marketboard/constants

const
  PixelScale = 4
  WindowWidth = ScreenWidth * PixelScale
  WindowHeight = ScreenHeight * PixelScale
  AtlasPath = "replay_atlas.png"

type
  ReplayViewerApp = ref object
    window: Window
    silky: Silky
    sim: SimServer
    replay: MbReplayPlayer
    loaded: bool
    followPlayer: int
    unpacked: seq[uint8]
    statusText: string
    legendEvents: seq[LegendEvent]
    legendsEnabled: bool
    activeOverlay: string
    overlayTicksLeft: int
    speedMultiplier: float = 1.0
    showTick: bool = false

    # Time-based simulation advancement (decouples sim tick rate from render FPS)
    lastSimAdvance: MonoTime
    simAccumulator: float

proc unpack4bpp(packed: openArray[uint8], unpacked: var seq[uint8]) =
  let targetLen = packed.len * 2
  if unpacked.len != targetLen:
    unpacked.setLen(targetLen)
  for i, b in packed:
    unpacked[i * 2] = b and 0x0F
    unpacked[i * 2 + 1] = (b shr 4) and 0x0F

proc sampleColor(index: uint8): ColorRGBX =
  let swatch = Palette[index.int and 0x0F]
  rgbx(swatch.r, swatch.g, swatch.b, swatch.a)

proc initViewer(): ReplayViewerApp =
  result = ReplayViewerApp()
  result.sim = initSimServer(0)
  result.followPlayer = 0
  result.unpacked = newSeq[uint8](ScreenWidth * ScreenHeight)
  result.statusText = "Drop a .mbreplay file or pass --load path"
  result.legendsEnabled = true

  result.sim.loadRenderAssets()

  let builder = newAtlasBuilder(64, 2)
  builder.write(AtlasPath)

  result.window = newWindow("Marketboard Replay Viewer",
    ivec2(WindowWidth.int32, WindowHeight.int32),
    style = DecoratedResizable, visible = true)
  result.window.runeInputEnabled = true
  makeContextCurrent(result.window)
  when not defined(useDirectX):
    loadExtensions()
  result.silky = newSilky(result.window, AtlasPath)

proc loadLegendsForReplay(viewer: ReplayViewerApp, replayPath: string) =
  viewer.legendEvents = @[]
  let legendsPath = replayPath.replace(".mbreplay", ".legends.json")
  if fileExists(legendsPath):
    try:
      let jsonData = parseJson(readFile(legendsPath))
      if jsonData.hasKey("events"):
        for e in jsonData["events"]:
          viewer.legendEvents.add LegendEvent(
            tick: e["tick"].getInt(),
            kind: parseEnum[LegendEventKind](e["kind"].getStr()),
            description: e["description"].getStr(),
            excitement: e["excitement"].getFloat()
          )
      echo "Loaded ", viewer.legendEvents.len, " legend events from ", legendsPath
    except CatchableError as e:
      echo "Could not load legends: ", e.msg

proc loadReplay(viewer: ReplayViewerApp, path: string) =
  if path.len == 0:
    return
  try:
    let data = loadMbReplay(path)
    viewer.sim = initSimServer(0)
    viewer.sim.loadRenderAssets()
    viewer.replay = initMbReplayPlayer(data)
    viewer.followPlayer = 0
    viewer.loaded = true
    viewer.statusText = ""
    viewer.loadLegendsForReplay(path)

    # Reset time-based simulation clock
    viewer.lastSimAdvance = MonoTime()
    viewer.simAccumulator = 0.0

    echo "Loaded replay: ", path
  except CatchableError as e:
    viewer.loaded = false
    viewer.statusText = "Error: " & e.msg
    echo "Could not load replay ", path, ": ", e.msg

proc wrapText(text: string, maxChars: int): tuple[line1, line2: string] =
  if text.len <= maxChars:
    return (text, "")
  var splitAt = maxChars
  while splitAt > 0 and text[splitAt] != ' ':
    dec splitAt
  if splitAt == 0:
    splitAt = maxChars
  let rest = text[splitAt ..< text.len].strip()
  if rest.len < 4:
    var earlier = splitAt - 1
    while earlier > 0 and text[earlier] != ' ':
      dec earlier
    if earlier > 0:
      splitAt = earlier
  result.line1 = text[0 ..< splitAt].strip()
  let finalRest = text[splitAt ..< text.len].strip()
  result.line2 = if finalRest.len > maxChars: finalRest[0 ..< maxChars] else: finalRest

proc renderLegendOverlay(viewer: ReplayViewerApp) =
  if not viewer.legendsEnabled or viewer.overlayTicksLeft <= 0:
    return
  if viewer.sim.letterSprites.len == 0:
    return
  let maxChars = (ScreenWidth - 6) div 6
  let (line1, line2) = wrapText(viewer.activeOverlay, maxChars)
  let hasLine2 = line2.len > 0
  let lineWidth = max(line1.len, line2.len) * 6
  let boxWidth = min(lineWidth + 4, ScreenWidth - 2)
  let boxHeight = if hasLine2: 17 else: 9
  let boxX = (ScreenWidth - boxWidth) div 2
  let boxY = 10
  for y in boxY ..< boxY + boxHeight:
    for x in boxX ..< boxX + boxWidth:
      if x >= 0 and x < ScreenWidth and y >= 0 and y < ScreenHeight:
        viewer.sim.fb.indices[y * ScreenWidth + x] = 0
  let x1 = (ScreenWidth - line1.len * 6) div 2
  viewer.sim.fb.blitText(viewer.sim.letterSprites, line1, x1, boxY + 2)
  if hasLine2:
    let x2 = (ScreenWidth - line2.len * 6) div 2
    viewer.sim.fb.blitText(viewer.sim.letterSprites, line2, x2, boxY + 10)
  viewer.sim.fb.packFramebuffer()

proc checkLegendEvents(viewer: ReplayViewerApp) =
  if not viewer.legendsEnabled: return
  if viewer.overlayTicksLeft > 0:
    dec viewer.overlayTicksLeft
  let tick = viewer.sim.tickCount
  for event in viewer.legendEvents:
    if event.tick == tick:
      viewer.activeOverlay = event.description
      # Scale by speed multiplier so legends last consistent wall time
      viewer.overlayTicksLeft = int(constants.BaseLegendDisplayTicks * viewer.speedMultiplier)
      break

proc renderFrame(viewer: ReplayViewerApp) =
  let playerIndex =
    if viewer.loaded and viewer.sim.players.len > 0:
      viewer.followPlayer mod viewer.sim.players.len
    else:
      -1

  discard viewer.sim.render(playerIndex)
  viewer.renderLegendOverlay()
  unpack4bpp(viewer.sim.fb.packed, viewer.unpacked)

  let frameSize = viewer.window.size
  viewer.silky.beginUi(viewer.window, frameSize)
  viewer.silky.clearScreen(rgbx(0, 0, 0, 255))

  let
    logicalWidth = int(frameSize.x.float32 / viewer.silky.uiScale)
    logicalHeight = int(frameSize.y.float32 / viewer.silky.uiScale)
    pixelScale = min(logicalWidth div ScreenWidth, logicalHeight div ScreenHeight)
    viewportWidth = ScreenWidth * pixelScale
    viewportHeight = ScreenHeight * pixelScale
    originX = (logicalWidth - viewportWidth) div 2
    originY = (logicalHeight - viewportHeight) div 2

  for y in 0 ..< ScreenHeight:
    for x in 0 ..< ScreenWidth:
      let index = viewer.unpacked[y * ScreenWidth + x]
      if index == TransparentColorIndex:
        continue
      let px = originX + x * pixelScale
      let py = originY + y * pixelScale
      viewer.silky.drawRect(
        vec2(px.float32, py.float32),
        vec2(pixelScale.float32, pixelScale.float32),
        sampleColor(index)
      )

  viewer.silky.endUi()
  viewer.window.swapBuffers()

proc handleKeyboard(viewer: ReplayViewerApp) =
  viewer.window.onRune = proc(rune: Rune) =
    if not viewer.loaded:
      return
    let ch = char(rune.uint32 and 0x7F)
    case ch
    of '[':
      viewer.followPlayer = max(0, viewer.followPlayer - 1)
    of ']':
      if viewer.sim.players.len > 0:
        viewer.followPlayer = min(viewer.sim.players.len - 1, viewer.followPlayer + 1)
    of 'l', 'L':
      viewer.legendsEnabled = not viewer.legendsEnabled
      echo "Legends overlay: ", (if viewer.legendsEnabled: "ON" else: "OFF")
    of 'n':
      if viewer.legendEvents.len > 0:
        let curTick = viewer.sim.tickCount
        var nextTick = -1
        for e in viewer.legendEvents:
          if e.tick > curTick:
            nextTick = e.tick
            break
        if nextTick >= 0:
          viewer.replay.applyReplaySeek(viewer.sim, nextTick)
          viewer.replay.playing = false
    of 'N':
      if viewer.legendEvents.len > 0:
        let curTick = viewer.sim.tickCount
        var prevTick = -1
        for i in countdown(viewer.legendEvents.high, 0):
          if viewer.legendEvents[i].tick < curTick:
            prevTick = viewer.legendEvents[i].tick
            break
        if prevTick >= 0:
          viewer.replay.applyReplaySeek(viewer.sim, prevTick)
          viewer.replay.playing = false
    else:
      viewer.replay.applyReplayCommand(viewer.sim, ch)

proc stepReplay(viewer: ReplayViewerApp) =
  if not viewer.loaded or not viewer.replay.playing:
    return
  try:
    # Time-based advancement: advance simulation at (GameTPS * current speed) TPS
    # regardless of how fast the GUI is rendering. This fixes the previous
    # "tick rate locked to FPS + multiplier" problem.
    let now = getMonoTime()
    if viewer.lastSimAdvance == MonoTime():
      viewer.lastSimAdvance = now

    let deltaSeconds = (now - viewer.lastSimAdvance).inNanoseconds.float / 1_000_000_000.0
    viewer.lastSimAdvance = now

    let multiplier = viewer.speedMultiplier  # set via CLI or keyboard
    let ticksToAdvance = deltaSeconds * constants.GameTPS.float * multiplier

    viewer.simAccumulator += ticksToAdvance
    let steps = viewer.simAccumulator.int
    viewer.simAccumulator -= steps.float

    for _ in 0 ..< steps:
      if viewer.replay.playing:
        viewer.replay.stepReplay(viewer.sim)
        viewer.checkLegendEvents()

    if viewer.replay.looping and not viewer.replay.playing:
      viewer.replay.seekReplay(viewer.sim, 0)
      viewer.replay.playing = true
  except CatchableError as e:
    viewer.replay.playing = false
    viewer.statusText = "Replay error: " & e.msg
    echo "Replay stopped: ", e.msg

proc tick(viewer: ReplayViewerApp) =
  viewer.stepReplay()
  viewer.renderFrame()

proc parseReplayArgs(): tuple[path: string, speed: float, showTick: bool] =
  var path = ""
  var speed = 1.0
  var showTick = false
  for kind, key, value in getopt():
    case kind
    of cmdLongOption:
      if key == "load":
        path = value
      elif key == "speed" or key == "multiplier":
        if value.len > 0:
          try:
            speed = parseFloat(value)
            if speed <= 0: speed = 1.0
          except:
            discard
      elif key == "tick" or key == "show-tick":
        showTick = true
    of cmdArgument:
      path = key
    else:
      discard
  (path, speed, showTick)

proc runReplayViewer() =
  let viewer = initViewer()
  viewer.handleKeyboard()

  let (replayPath, speed, showTick) = parseReplayArgs()
  if replayPath.len > 0:
    viewer.loadReplay(replayPath)
    viewer.speedMultiplier = speed
    viewer.showTick = showTick

  viewer.window.onFileDrop = proc(fileName, fileData: string) =
    try:
      let data = parseMbReplayBytes(fileData)
      viewer.sim = initSimServer(0)
      viewer.sim.loadRenderAssets()
      viewer.replay = initMbReplayPlayer(data)
      viewer.followPlayer = 0
      viewer.loaded = true
      viewer.statusText = ""
      viewer.loadLegendsForReplay(fileName)

      # Reset time-based simulation clock
      viewer.lastSimAdvance = MonoTime()
      viewer.simAccumulator = 0.0

      echo "Loaded replay: ", fileName
    except CatchableError as e:
      viewer.loaded = false
      viewer.statusText = "Error: " & e.msg
      echo "Could not load replay ", fileName, ": ", e.msg

  var lastTick = getMonoTime()
  # Render at a pleasant fixed rate (e.g. 60 FPS) for smooth UI.
  # Simulation advancement is now handled with a time accumulator in stepReplay()
  # so it stays locked to GameTPS * multiplier regardless of render rate.
  let renderFps = 60
  let frameDuration = initDuration(microseconds = 1_000_000 div renderFps)

  while not viewer.window.closeRequested:
    pollEvents()
    viewer.tick()

    let elapsed = getMonoTime() - lastTick
    if elapsed < frameDuration:
      sleep(int((frameDuration - elapsed).inMilliseconds))
    lastTick = getMonoTime()

  try:
    removeFile(AtlasPath)
  except CatchableError:
    discard

when isMainModule:
  runReplayViewer()
