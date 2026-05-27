import std/[monotimes, os, parseopt]
import pixie, windy
import bitworld/protocol, bitworld/server, marketboard/sim, marketboard/replays
import marketboard/global_render
import client/global_client

type
  FullmapViewer = ref object
    app: GlobalApp
    sim: SimServer
    replay: MbReplayPlayer
    loaded: bool
    viewerState: GlobalViewerState
    inputPackets: seq[string]

proc bitworldClientDir(): string =
  getHomeDir() / ".nimby" / "pkgs" / "bitworld" / "client"

proc clientDataDir(): string =
  bitworldClientDir() / "data"

proc clientDistDir(): string =
  bitworldClientDir() / "dist"

proc addInputPacket(viewer: FullmapViewer, packet: string) =
  viewer.inputPackets.add(packet)

proc initFullmapViewer*(): FullmapViewer =
  result = FullmapViewer()
  result.sim = initSimServer(0)
  loadRenderAssets(result.sim)
  let viewer = result
  result.app = initGlobalApp(
    options = GlobalOptions(
      title: "Marketboard Fullmap Viewer",
      atlasPath: clientDistDir() / "atlas.png",
      palettePath: clientDataDir() / "pallete.png",
      packetSink: proc(packet: string) =
        viewer.addInputPacket(packet)
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
  viewer.inputPackets.setLen(0)
  viewer.app.resetProtocolState()
  viewer.app.setStatus("")

proc tick*(viewer: FullmapViewer) =
  viewer.app.handleInput()

  if viewer.loaded:
    if viewer.replay.playing:
      for _ in 0 ..< viewer.replay.replaySpeed():
        if viewer.replay.playing:
          viewer.replay.stepReplay(viewer.sim)
      if viewer.replay.looping and not viewer.replay.playing:
        viewer.replay.seekReplay(viewer.sim, 0)
        viewer.replay.playing = true

    let packet = buildGlobalFramePacket(viewer.sim, viewer.viewerState)
    if packet.len > 0:
      viewer.app.parseMessage(blobFromBytes(packet))

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
      viewer.inputPackets.setLen(0)
      viewer.app.resetProtocolState()
      viewer.app.setStatus("")
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
