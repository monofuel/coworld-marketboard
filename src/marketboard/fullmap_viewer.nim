import std/[algorithm, json, monotimes, os, parseopt, strutils, times]
import pixie, windy
import bitworld/protocol, marketboard/sim, marketboard/replays, marketboard/legends
import marketboard/global_render
import client/global_client

import marketboard/constants

const
  LegendDisplayTicks = constants.BaseLegendDisplayTicks
  MaxPendingLegends = 16

type
  FullmapViewer = ref object
    app: GlobalApp
    sim: SimServer
    replay: MbReplayPlayer
    loaded: bool
    viewerState: GlobalViewerState
    legendEvents: seq[LegendEvent]
    legendSlots: array[LegendSlotCount, tuple[text: string, ticksLeft: int]]
    pendingLegends: seq[LegendEvent]
    speedMultiplier: float   # 1.0 = normal game speed (24 TPS). Scales stepping and legend lifetime.
    showTick*: bool          # Whether to show the debug tick counter (disabled by default)

    # Time-based simulation advancement (decouples sim tick rate from render FPS)
    lastSimAdvance: MonoTime
    simAccumulator: float

proc bitworldClientDir(): string =
  getHomeDir() / ".nimby" / "pkgs" / "bitworld" / "client"

proc clientDataDir(): string =
  bitworldClientDir() / "data"

proc clientDistDir(): string =
  bitworldClientDir() / "dist"

proc loadLegendsForReplay(viewer: FullmapViewer, replayPath: string) =
  ## Loads legend events from the .legends.json sidecar file.
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
    except CatchableError:
      discard

proc resetLegends(viewer: FullmapViewer) =
  ## Clears all legend slots and the pending queue.
  for slot in viewer.legendSlots.mitems:
    slot = (text: "", ticksLeft: 0)
  viewer.pendingLegends = @[]

proc checkLegendEvents(viewer: FullmapViewer) =
  ## Per sim tick: age slots, queue events firing this tick, and fill freed
  ## slots with the most exciting pending events. Lifetime is counted in sim
  ## ticks (deterministic, freezes on pause), and the same line never shows in
  ## two slots at once.
  for slot in viewer.legendSlots.mitems:
    if slot.ticksLeft > 0:
      dec slot.ticksLeft
      if slot.ticksLeft == 0:
        slot.text = ""

  let tick = viewer.sim.tickCount
  for event in viewer.legendEvents:
    if event.tick == tick:
      viewer.pendingLegends.add event

  # Keep the backlog bounded, retaining the highest-excitement events.
  if viewer.pendingLegends.len > MaxPendingLegends:
    viewer.pendingLegends.sort(proc(a, b: LegendEvent): int = cmp(b.excitement, a.excitement))
    viewer.pendingLegends.setLen(MaxPendingLegends)

  for slot in viewer.legendSlots.mitems:
    if slot.ticksLeft > 0 or viewer.pendingLegends.len == 0:
      continue
    var bestIdx = -1
    for i in 0 ..< viewer.pendingLegends.len:
      var alreadyShown = false
      for other in viewer.legendSlots:
        if other.ticksLeft > 0 and other.text == viewer.pendingLegends[i].description:
          alreadyShown = true
          break
      if alreadyShown:
        continue
      if bestIdx < 0 or viewer.pendingLegends[i].excitement > viewer.pendingLegends[bestIdx].excitement:
        bestIdx = i
    if bestIdx < 0:
      continue
    slot.text = viewer.pendingLegends[bestIdx].description
    # Scale legend lifetime by speed so wall-time duration stays roughly constant
    slot.ticksLeft = int(LegendDisplayTicks * viewer.speedMultiplier)
    viewer.pendingLegends.delete(bestIdx)

proc initFullmapViewer*(): FullmapViewer =
  result = FullmapViewer()
  result.sim = initSimServer(0)
  loadRenderAssets(result.sim)
  # Do NOT create app here — live path will create the correct spectator one.
  # Replay path will create its own in loadReplay.
  result.app = nil
  result.showTick = false
  result.speedMultiplier = 1.0
  # replay remains uninitialized (nil) for live path

proc loadReplay*(viewer: FullmapViewer, path: string) =
  if not fileExists(path):
    viewer.app.setStatus("File not found: " & path)
    return
  let data = loadMbReplay(path)
  viewer.sim = initSimServer(0)
  loadRenderAssets(viewer.sim)
  viewer.replay = initMbReplayPlayer(data)
  viewer.loaded = true
  viewer.viewerState = GlobalViewerState()
  viewer.resetLegends()
  viewer.app.resetProtocolState()
  viewer.app.setStatus("")
  viewer.loadLegendsForReplay(path)

  # Reset time-based sim clock
  viewer.lastSimAdvance = MonoTime()
  viewer.simAccumulator = 0.0

proc tick*(viewer: FullmapViewer) =
  viewer.app.handleInput()

  if viewer.loaded:
    # Live mode: the real WebSocket (via global_client) calls parseMessage directly.
    # We only drive local legend events + maybeFit/draw. No replay in live mode.
    # replay is a value object (MbReplayPlayer), not a ref, so we detect "real replay loaded"
    # by the presence of actual replay data (populated only by loadReplay / file drop).
    if viewer.replay.data.gameName.len > 0 and viewer.replay.playing:
      # Time-based stepping at GameTPS * speedMultiplier (decoupled from render rate)
      let now = getMonoTime()
      if viewer.lastSimAdvance == MonoTime():
        viewer.lastSimAdvance = now
      let delta = (now - viewer.lastSimAdvance).inNanoseconds.float / 1_000_000_000.0
      viewer.lastSimAdvance = now

      let ticksToAdvance = delta * constants.GameTPS.float * viewer.speedMultiplier
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

    # Local legend overlay (works for both live and replay)
    var slotTexts: array[LegendSlotCount, string]
    for i in 0 ..< LegendSlotCount:
      slotTexts[i] = viewer.legendSlots[i].text
    let legendPacket = buildLegendPacket(viewer.sim, slotTexts)
    if legendPacket.len > 0:
      viewer.app.parseMessage(blobFromBytes(legendPacket))

    # In pure replay mode we are responsible for driving the entire global
    # protocol state (map, scoreboard, players, tick counter, etc.) locally
    # by injecting what the server would have sent.
    if viewer.replay.data.gameName.len > 0:
      let framePacket = buildGlobalFramePacket(viewer.sim, viewer.viewerState, viewer.showTick)
      if framePacket.len > 0:
        viewer.app.parseMessage(blobFromBytes(framePacket))

  viewer.app.maybeFit()
  viewer.app.draw()

proc windowOpen*(viewer: FullmapViewer): bool =
  viewer.app.windowOpen

proc installFileDrop*(viewer: FullmapViewer) =
  viewer.app.setFileDropCallback(
    proc(fileName, fileData: string) =
      let data = parseMbReplayBytes(fileData)
      viewer.sim = initSimServer(0)
      loadRenderAssets(viewer.sim)
      viewer.replay = initMbReplayPlayer(data)
      viewer.loaded = true
      viewer.viewerState = GlobalViewerState()
      viewer.resetLegends()
      viewer.app.resetProtocolState()
      viewer.app.setStatus("")
      viewer.loadLegendsForReplay(fileName)

      # Reset time-based sim clock
      viewer.lastSimAdvance = MonoTime()
      viewer.simAccumulator = 0.0
  )

proc parseArgs(): tuple[address: string, replayPath: string, speed: float, showTick: bool] =
  result.address = "ws://localhost:8080/global"
  result.replayPath = ""
  result.speed = 1.0
  result.showTick = false

  for kind, key, value in getopt():
    case kind
    of cmdLongOption:
      if key == "address" or key == "load" or key == "load-replay":
        if value.len > 0:
          result.address = value
          if not value.startsWith("ws://"):
            result.address = "ws://" & value
      elif key == "speed" or key == "multiplier":
        if value.len > 0:
          try:
            result.speed = parseFloat(value)
            if result.speed <= 0: result.speed = 1.0
          except:
            discard
      elif key == "tick" or key == "show-tick" or key == "debug-tick":
        result.showTick = true
      elif key == "help" or key == "h":
        echo "Usage: fullmap_viewer [--address:ws://localhost:8080/global] [replay.mbreplay] [--speed:2.0]"
        echo "  --address     Connect to live server global view (default)"
        echo "                Pure spectator mode (no player input, clean for lobby TV)"
        echo "  --speed:N     Replay speed multiplier (default 1.0). Affects sim rate and legend lifetime."
        echo "  --multiplier:N  Alias for --speed"
        echo "  --tick        Show the tick counter (disabled by default)"
        quit(0)
    of cmdArgument:
      if key.startsWith("ws://") or key.startsWith("wss://"):
        result.address = key
      else:
        result.replayPath = key
    else: discard

  # If a replay file was provided positionally, clear the default ws address
  # so we correctly take the replay branch instead of trying (and failing) to connect.
  if result.replayPath.len > 0:
    result.address = ""

when isMainModule:
  let (address, replayPath, speed, showTick) = parseArgs()

  # Live path must create app FIRST (before installFileDrop and tick loop)
  var viewer: FullmapViewer
  if replayPath.len > 0:
    # Pure replay / offline mode: create a non-connected GlobalApp so we can
    # locally drive the entire global protocol (map + scoreboard + players + tick + legends)
    # from the stepped local sim. This makes "quick_replay" (record + view) actually work.
    let app = initGlobalApp(
      address = "",
      options = GlobalOptions(
        title: "Marketboard Replay Fullmap",
        atlasPath: clientDistDir() / "atlas.png",
        palettePath: clientDataDir() / "pallete.png",
        playerMode: false,
        packetSink: proc(packet: string) = discard   # offline only — we feed packets via parseMessage
      )
    )
    app.setStatus("")
    viewer = FullmapViewer(
      app: app,
      sim: initSimServer(0),
      loaded: false,
      viewerState: GlobalViewerState(),
      speedMultiplier: speed,
      showTick: showTick
    )
    loadRenderAssets(viewer.sim)
    viewer.installFileDrop()
    if replayPath.len > 0:
      viewer.loadReplay(replayPath)
  elif address.len > 0 and address.startsWith("ws://"):
    # Live / connected spectator mode
    let app = initGlobalApp(
      address = address,
      options = GlobalOptions(
        title: "Marketboard Live Fullmap",
        atlasPath: clientDistDir() / "atlas.png",
        palettePath: clientDataDir() / "pallete.png",
        playerMode: false
      )
    )
    app.setStatus("")  # clean TV view - no prompts
    viewer = FullmapViewer(
      app: app,
      sim: initSimServer(0),  # kept for local legend/events but not used for rendering
      loaded: true,
      viewerState: GlobalViewerState(),
      speedMultiplier: 1.0,
      showTick: true  # always show in live for now
    )
    loadRenderAssets(viewer.sim)
    viewer.installFileDrop()
  else:
    viewer = initFullmapViewer()
    viewer.installFileDrop()
    if replayPath.len > 0:
      viewer.loadReplay(replayPath)

  var lastTick = getMonoTime()
  while viewer.windowOpen():
    pollEvents()
    viewer.tick()
    runFrameLimiter(lastTick)
