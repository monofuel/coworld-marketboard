import std/[json, monotimes, os, parseopt, strutils]
import pixie, windy
import bitworld/protocol, marketboard/sim, marketboard/replays, marketboard/legends
import marketboard/global_render
import client/global_client

type
  FullmapViewer = ref object
    app: GlobalApp
    sim: SimServer
    replay: MbReplayPlayer
    loaded: bool
    viewerState: GlobalViewerState
    legendEvents: seq[LegendEvent]
    activeOverlay: string
    overlayTicksLeft: int

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

proc checkLegendEvents(viewer: FullmapViewer) =
  ## Checks if the current tick matches a legend event and activates the overlay.
  if viewer.overlayTicksLeft > 0:
    dec viewer.overlayTicksLeft
  let tick = viewer.sim.tickCount
  for event in viewer.legendEvents:
    if event.tick == tick:
      viewer.activeOverlay = event.description
      viewer.overlayTicksLeft = 72
      break

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
  viewer.activeOverlay = ""
  viewer.overlayTicksLeft = 0
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

    let overlayText = if viewer.overlayTicksLeft > 0: viewer.activeOverlay else: ""
    let legendPacket = buildLegendPacket(viewer.sim, overlayText)
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
      viewer.activeOverlay = ""
      viewer.overlayTicksLeft = 0
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
