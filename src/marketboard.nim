import mummy
import bitworld/protocol except TileSize
import bitworld/cogame_runtime
import marketboard/sim
import marketboard/sprite_render
import std/[json, locks, monotimes, os, parseopt, strutils, tables, times]

const
  TargetFps = 24
  WebSocketPath = "/player"

type
  RunConfig = object
    address: string
    port: int
    seed: int

  WebSocketAppState = object
    lock: Lock
    inputMasks: Table[WebSocket, uint8]
    lastAppliedMasks: Table[WebSocket, uint8]
    playerIndices: Table[WebSocket, int]
    playerNames: Table[WebSocket, string]
    closedSockets: seq[WebSocket]
    rewardViewers: Table[WebSocket, bool]
    stateViewers: Table[WebSocket, bool]
    spriteViewerStates: Table[WebSocket, PlayerViewerState]
    resetRequested: bool

  ServerThreadArgs = object
    server: ptr Server
    address: string
    port: int

var appState: WebSocketAppState

proc initAppState() =
  initLock(appState.lock)
  appState.inputMasks = initTable[WebSocket, uint8]()
  appState.lastAppliedMasks = initTable[WebSocket, uint8]()
  appState.playerIndices = initTable[WebSocket, int]()
  appState.playerNames = initTable[WebSocket, string]()
  appState.closedSockets = @[]
  appState.rewardViewers = initTable[WebSocket, bool]()
  appState.stateViewers = initTable[WebSocket, bool]()
  appState.spriteViewerStates = initTable[WebSocket, PlayerViewerState]()
  appState.resetRequested = false

proc playerInputFromMasks(currentMask, previousMask: uint8): PlayerInput =
  let decoded = decodeInputMask(currentMask)
  result.up = decoded.up
  result.down = decoded.down
  result.left = decoded.left
  result.right = decoded.right
  result.aPressed = (currentMask and ButtonA) != 0 and (previousMask and ButtonA) == 0
  result.aHeld = (currentMask and ButtonA) != 0
  result.bPressed = (currentMask and ButtonB) != 0 and (previousMask and ButtonB) == 0
  result.selectPressed = (currentMask and ButtonSelect) != 0 and (previousMask and ButtonSelect) == 0

proc removePlayer(sim: var SimServer, websocket: WebSocket) =
  if websocket in appState.rewardViewers:
    appState.rewardViewers.del(websocket)
  if websocket in appState.stateViewers:
    appState.stateViewers.del(websocket)
  if websocket in appState.spriteViewerStates:
    appState.spriteViewerStates.del(websocket)
  if websocket notin appState.playerIndices:
    return

  let removedIndex = appState.playerIndices[websocket]
  appState.playerIndices.del(websocket)
  appState.playerNames.del(websocket)
  appState.inputMasks.del(websocket)
  appState.lastAppliedMasks.del(websocket)

  if removedIndex >= 0 and removedIndex < sim.players.len:
    sim.players.delete(removedIndex)
    for ws, value in appState.playerIndices.mpairs:
      if value > removedIndex:
        dec value
    for listing in sim.npcListings.mitems:
      if listing.sellerIndex == removedIndex:
        listing.sellerIndex = -1
      elif listing.sellerIndex > removedIndex:
        dec listing.sellerIndex

proc cleanPlayerName(name: string): string =
  result = name.strip()
  for ch in result.mitems:
    if ch.isSpaceAscii:
      ch = '_'

proc playerIdentity(request: Request): string =
  let name = request.queryParams.getOrDefault("name", "").cleanPlayerName()
  if name.len > 0:
    return name
  let parts = request.remoteAddress.splitWhitespace()
  if parts.len >= 2:
    return parts[0] & ":" & parts[1]
  request.remoteAddress

proc clientDir(): string =
  let nimbyDir = getHomeDir() / ".nimby" / "pkgs" / "bitworld" / "client"
  if dirExists(nimbyDir): return nimbyDir
  getCurrentDir() / "client"

proc serveStaticFile(request: Request, path, contentType: string) =
  if fileExists(path):
    var headers: HttpHeaders
    headers["Content-Type"] = contentType
    request.respond(200, headers, readFile(path))
  else:
    var headers: HttpHeaders
    headers["Content-Type"] = "text/plain"
    request.respond(404, headers, "Not found")

proc httpHandler(request: Request) =
  if request.path == WebSocketPath and request.httpMethod == "GET":
    let websocket = request.upgradeToWebSocket()
    {.gcsafe.}:
      withLock appState.lock:
        appState.playerNames[websocket] = request.playerIdentity()
  elif request.path == "/state" and request.httpMethod == "GET":
    let websocket = request.upgradeToWebSocket()
    {.gcsafe.}:
      withLock appState.lock:
        appState.playerNames[websocket] = request.playerIdentity()
        appState.stateViewers[websocket] = true
  elif request.path == "/reward" and request.httpMethod == "GET":
    let websocket = request.upgradeToWebSocket()
    {.gcsafe.}:
      withLock appState.lock:
        appState.rewardViewers[websocket] = true
  elif request.path in ["/", "/player_client.html"]:
    serveStaticFile(request, clientDir() / "player_client.html", "text/html")
  elif request.path == "/global_client.html":
    serveStaticFile(request, clientDir() / "global_client.html", "text/html")
  elif request.path == "/snappyjs.min.js":
    serveStaticFile(request, clientDir() / "snappyjs.min.js", "application/javascript")
  else:
    var headers: HttpHeaders
    headers["Content-Type"] = "text/plain"
    request.respond(200, headers, "Marketboard WebSocket server")

proc websocketHandler(
  websocket: WebSocket,
  event: WebSocketEvent,
  message: Message
) =
  case event
  of OpenEvent:
    {.gcsafe.}:
      withLock appState.lock:
        if websocket notin appState.rewardViewers and
           websocket notin appState.stateViewers:
          appState.playerIndices[websocket] = 0x7fffffff
          appState.inputMasks[websocket] = 0
          appState.lastAppliedMasks[websocket] = 0
        elif websocket in appState.stateViewers:
          appState.playerIndices[websocket] = 0x7fffffff
          appState.inputMasks[websocket] = 0
          appState.lastAppliedMasks[websocket] = 0
  of MessageEvent:
    if message.kind == BinaryMessage and (isInputPacket(message.data) or isSpriteInputPacket(message.data)):
      {.gcsafe.}:
        withLock appState.lock:
          let mask =
            if isSpriteInputPacket(message.data): spriteInputMask(message.data)
            else: blobToMask(message.data)
          if mask == 255'u8:
            appState.resetRequested = true
            appState.inputMasks[websocket] = 0
            appState.lastAppliedMasks[websocket] = 0
          else:
            appState.inputMasks[websocket] = mask
  of ErrorEvent:
    discard
  of CloseEvent:
    {.gcsafe.}:
      withLock appState.lock:
        appState.closedSockets.add(websocket)

proc serverThreadProc(args: ServerThreadArgs) {.thread.} =
  args.server[].serve(Port(args.port), args.address)

proc runFrameLimiter(previousTick: var MonoTime) =
  let frameDuration = initDuration(microseconds = 1_000_000 div TargetFps)
  let elapsed = getMonoTime() - previousTick
  if elapsed < frameDuration:
    sleep(int((frameDuration - elapsed).inMilliseconds))
  previousTick = getMonoTime()

proc runServerLoop(
  host = DefaultHost,
  port = DefaultPort,
  seed = 0
) =
  initAppState()

  let httpServer = newServer(
    httpHandler,
    websocketHandler,
    workerThreads = 4
  )

  var serverThread: Thread[ServerThreadArgs]
  var serverPtr = cast[ptr Server](unsafeAddr httpServer)
  createThread(serverThread, serverThreadProc, ServerThreadArgs(server: serverPtr, address: host, port: port))
  httpServer.waitUntilReady()

  var
    currentSeed = seed
    sim = initSimServer(currentSeed)
    lastTick = getMonoTime()

  sim.loadRenderAssets()

  while true:
    var
      sockets: seq[WebSocket] = @[]
      playerIndices: seq[int] = @[]
      inputs: seq[PlayerInput]
      shouldReset = false
      rewardViewers: seq[WebSocket] = @[]
      stateViewerSockets: seq[WebSocket] = @[]
      stateViewerIndices: seq[int] = @[]

    {.gcsafe.}:
      withLock appState.lock:
        for websocket in appState.closedSockets:
          sim.removePlayer(websocket)
        appState.closedSockets.setLen(0)

        if appState.resetRequested:
          shouldReset = true
          appState.resetRequested = false
          for _, value in appState.playerIndices.mpairs:
            value = 0x7fffffff
          for _, value in appState.inputMasks.mpairs:
            value = 0
          for _, value in appState.lastAppliedMasks.mpairs:
            value = 0
        else:
          for websocket in appState.playerIndices.keys:
            if appState.playerIndices[websocket] == 0x7fffffff:
              let name = appState.playerNames.getOrDefault(websocket, "unknown")
              appState.playerIndices[websocket] = sim.addPlayer(name)

          inputs = newSeq[PlayerInput](sim.players.len)
          for websocket, playerIndex in appState.playerIndices.pairs:
            if playerIndex < 0 or playerIndex >= inputs.len:
              continue
            let currentMask = appState.inputMasks.getOrDefault(websocket, 0)
            let previousMask = appState.lastAppliedMasks.getOrDefault(websocket, 0)
            inputs[playerIndex] = playerInputFromMasks(currentMask, previousMask)
            appState.lastAppliedMasks[websocket] = currentMask
            if websocket in appState.stateViewers:
              stateViewerSockets.add(websocket)
              stateViewerIndices.add(playerIndex)
            else:
              sockets.add(websocket)
              playerIndices.add(playerIndex)

        for websocket in appState.rewardViewers.keys:
          rewardViewers.add(websocket)

    if shouldReset:
      inc currentSeed
      sim = initSimServer(currentSeed)
      sim.loadRenderAssets()
      {.gcsafe.}:
        withLock appState.lock:
          for websocket in appState.playerIndices.keys:
            if appState.playerIndices[websocket] == 0x7fffffff:
              let name = appState.playerNames.getOrDefault(websocket, "unknown")
              appState.playerIndices[websocket] = sim.addPlayer(name)
            if websocket in appState.stateViewers:
              stateViewerSockets.add(websocket)
              stateViewerIndices.add(appState.playerIndices[websocket])
            else:
              sockets.add(websocket)
              playerIndices.add(appState.playerIndices[websocket])
          for _, vs in appState.spriteViewerStates.mpairs:
            vs.initialized = false
      for i in 0 ..< sockets.len:
        var vs = appState.spriteViewerStates.mgetOrPut(sockets[i], PlayerViewerState())
        let packet = buildFramePacket(sim, playerIndices[i], vs)
        appState.spriteViewerStates[sockets[i]] = vs
        sockets[i].send(blobFromBytes(packet), BinaryMessage)
      for i in 0 ..< stateViewerSockets.len:
        stateViewerSockets[i].send(sim.buildStateJson(stateViewerIndices[i]), TextMessage)
      let rewardPacket = sim.buildRewardPacket()
      for websocket in rewardViewers:
        websocket.send(rewardPacket, TextMessage)
      runFrameLimiter(lastTick)
      continue

    sim.step(inputs)

    for i in 0 ..< sockets.len:
      try:
        var vs = appState.spriteViewerStates.mgetOrPut(sockets[i], PlayerViewerState())
        let packet = buildFramePacket(sim, playerIndices[i], vs)
        appState.spriteViewerStates[sockets[i]] = vs
        sockets[i].send(blobFromBytes(packet), BinaryMessage)
      except:
        {.gcsafe.}:
          withLock appState.lock:
            sim.removePlayer(sockets[i])

    for i in 0 ..< stateViewerSockets.len:
      try:
        stateViewerSockets[i].send(sim.buildStateJson(stateViewerIndices[i]), TextMessage)
      except:
        {.gcsafe.}:
          withLock appState.lock:
            sim.removePlayer(stateViewerSockets[i])

    let rewardPacket = sim.buildRewardPacket()
    for websocket in rewardViewers:
      websocket.send(rewardPacket, TextMessage)

    runFrameLimiter(lastTick)

proc readConfigString(node: JsonNode, name: string, value: var string) =
  if not node.hasKey(name):
    return
  let item = node[name]
  if item.kind != JString:
    raise newException(ValueError, "Config field " & name & " must be a string.")
  value = item.getStr()

proc readConfigInt(node: JsonNode, name: string, value: var int) =
  if not node.hasKey(name):
    return
  let item = node[name]
  if item.kind != JInt:
    raise newException(ValueError, "Config field " & name & " must be an integer.")
  value = item.getInt()

proc update(config: var RunConfig, jsonText: string) =
  if jsonText.len == 0:
    return
  let node = parseJson(jsonText)
  if node.kind != JObject:
    raise newException(ValueError, "Config must be a JSON object.")
  node.readConfigString("address", config.address)
  node.readConfigInt("port", config.port)
  node.readConfigInt("seed", config.seed)

when isMainModule:
  var
    config = RunConfig(
      address: cogameHost(DefaultHost),
      port: cogamePort(DefaultPort),
      seed: 0,
    )
    configJson = ""
    configPath = pathFromCogameEnv(CogameConfigUriEnv)
    pendingOption = ""
  for kind, key, val in getopt():
    case kind
    of cmdLongOption:
      pendingOption = ""
      case key
      of "address":
        if val.len > 0:
          config.address = val
        else:
          pendingOption = "address"
      of "port":
        if val.len > 0:
          config.port = parseInt(val)
        else:
          pendingOption = "port"
      of "config":
        configJson = val
      of "config-file":
        configPath = val
      else: discard
    of cmdArgument:
      case pendingOption
      of "address":
        config.address = key
      of "port":
        config.port = parseInt(key)
      else: discard
      pendingOption = ""
    else: discard
  if configPath.len > 0:
    config.update(readFile(configPath))
  if configJson.len > 0:
    config.update(configJson)
  runServerLoop(config.address, config.port, seed = config.seed)
