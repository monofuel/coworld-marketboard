import std/[algorithm, json, monotimes, os, parseopt, strutils]
import pixie, windy
import bitworld/protocol, marketboard/sim, marketboard/replays, marketboard/legends
import marketboard/global_render
import client/global_client

const
  LegendDisplayTicks = 96   # sim ticks a caption stays before its slot frees
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
    slot.ticksLeft = LegendDisplayTicks
    viewer.pendingLegends.delete(bestIdx)

proc initFullmapViewer*(): FullmapViewer =
  result = FullmapViewer()
  result.sim = initSimServer(0)
  loadRenderAssets(result.sim)
  # Do NOT create app here — live path will create the correct spectator one.
  # Replay path will create its own in loadReplay.
  result.app = nil
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

proc tick*(viewer: FullmapViewer) =
  viewer.app.handleInput()

  if viewer.loaded:
    # Live mode: the real WebSocket (via global_client) calls parseMessage directly.
    # We only drive local legend events + maybeFit/draw. No replay in live mode.
    # replay is a value object (MbReplayPlayer), not a ref, so we detect "real replay loaded"
    # by the presence of actual replay data (populated only by loadReplay / file drop).
    if viewer.replay.data.gameName.len > 0 and viewer.replay.playing:
      for _ in 0 ..< viewer.replay.replaySpeed():
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
  )

proc parseArgs(): tuple[address: string, replayPath: string] =
  result.address = "ws://localhost:8080/global"
  result.replayPath = ""

  for kind, key, value in getopt():
    case kind
    of cmdLongOption:
      if key == "address" or key == "load" or key == "load-replay":
        if value.len > 0:
          result.address = value
          if not value.startsWith("ws://"):
            result.address = "ws://" & value
      elif key == "help" or key == "h":
        echo "Usage: fullmap_viewer [--address:ws://localhost:8080/global] [replay.mbreplay]"
        echo "  --address  Connect to live server global view (default)"
        echo "             Pure spectator mode (no player input, clean for lobby TV)"
        quit(0)
    of cmdArgument:
      if key.startsWith("ws://") or key.startsWith("wss://"):
        result.address = key
      else:
        result.replayPath = key
    else: discard

when isMainModule:
  let args = parseArgs()

  # Live path must create app FIRST (before installFileDrop and tick loop)
  var viewer: FullmapViewer
  if args.address.len > 0 and args.address.startsWith("ws://"):
    # Pure global spectator for lobby TV - let the real WebSocket handle packets
    # (remove packetSink so global_client opens the connection and calls parseMessage)
    let app = initGlobalApp(
      address = args.address,
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
      viewerState: GlobalViewerState()
    )
    loadRenderAssets(viewer.sim)
    viewer.installFileDrop()
  else:
    viewer = initFullmapViewer()
    viewer.installFileDrop()
    if args.replayPath.len > 0:
      viewer.loadReplay(args.replayPath)

  var lastTick = getMonoTime()
  while viewer.windowOpen():
    pollEvents()
    viewer.tick()
    runFrameLimiter(lastTick)
