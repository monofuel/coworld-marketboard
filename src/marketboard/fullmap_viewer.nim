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
  result.app = initGlobalApp(
    options = GlobalOptions(
      title: "Marketboard Fullmap Viewer",
      atlasPath: clientDistDir() / "atlas.png",
      palettePath: clientDataDir() / "pallete.png",
      packetSink: proc(packet: string) = discard
    )
  )
  result.app.setStatus("Drop a .mbreplay file or pass --load path")

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
    if viewer.replay.playing:
      for _ in 0 ..< viewer.replay.replaySpeed():
        if viewer.replay.playing:
          viewer.replay.stepReplay(viewer.sim)
          viewer.checkLegendEvents()
      if viewer.replay.looping and not viewer.replay.playing:
        viewer.replay.seekReplay(viewer.sim, 0)
        viewer.replay.playing = true

    let packet = buildGlobalFramePacket(viewer.sim, viewer.viewerState)
    if packet.len > 0:
      viewer.app.parseMessage(blobFromBytes(packet))

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

when isMainModule:
  var replayPath = ""
  for kind, key, value in getopt():
    case kind
    of cmdLongOption:
      if key == "load" or key == "load-replay":
        replayPath = value
    of cmdArgument:
      replayPath = key
    else: discard

  let viewer = initFullmapViewer()
  viewer.installFileDrop()
  if replayPath.len > 0:
    viewer.loadReplay(replayPath)

  var lastTick = getMonoTime()
  while viewer.windowOpen():
    pollEvents()
    viewer.tick()
    runFrameLimiter(lastTick)
