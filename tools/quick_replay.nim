import std/[monotimes, net, os, osproc, parseopt, sequtils, strformat, strutils, times]

const
  BatchSource = "tools" / "batch_market.nim"
  ViewerSource = "src" / "marketboard" / "replay_viewer.nim"
  FullmapSource = "src" / "marketboard" / "fullmap_viewer.nim"
  HeadlessSource = "tools" / "headless_sim.nim"
  ServerSource = "src" / "marketboard.nim"
  DefaultTicks = 4000
  DefaultReplayDir = "replays"
  DefaultPort = 8080
  DefaultAddress = "localhost"

  BotSources = [
    ("StillForge", "players" / "still_forge.nim"),
    ("IronWorks", "players" / "iron_works.nim"),
    ("Colm", "players" / "colm.nim"),
    ("Zorori", "players" / "zorori.nim"),
    ("Solenne", "players" / "solenne.nim"),
    ("Rkhenna", "players" / "rkhenna.nim"),
    ("Pipitori", "players" / "pipitori.nim"),
  ]

  ServerReadyTimeoutMs = 5000
  PollIntervalMs = 100

type
  QuickReplayConfig = object
    live: bool
    watch: bool
    ticks: int
    headless: bool
    playerCam: bool
    checkpointInterval: int
    address: string
    port: int
    bots: seq[string]
    seed: int

proc usage(): string =
  """Usage: quick_replay [options]

Modes:
  (default)          Record 1 match then open fullmap viewer
  --live             Live mode: run server+bots and connect fullmap viewer immediately (best for iteration)
  --headless         Run headless simulation only
  --player-cam       Use player-following replay viewer instead of fullmap

Options:
  --ticks:N          Max ticks per match (default: 4000)
  --watch            Auto-restart match when it ends (great with --live)
  --address:ADDR     Server address (default: localhost)
  --port:N           Server port (default: 8080)
  --bots:Bot1,Bot2   Comma-separated bot list (default: all 7)
  --no-bots          Run without any bots
  --seed:N           Random seed for reproducible runs
  --interval:N       Legend/checkpoint interval (default: 5000)
  -h, --help         Show this help"""

proc findBotSource(name: string): string =
  let lower = name.toLowerAscii()
  for (botName, source) in BotSources:
    if botName.toLowerAscii() == lower:
      return source
  for (botName, source) in BotSources:
    if lower.startsWith(botName.toLowerAscii()):
      return source
  raise newException(ValueError, "Unknown bot: " & name & ". Available: " &
    BotSources.mapIt(it[0]).join(", "))

proc nimRunProcess(nimExe, rootDir, label, sourceRelative: string,
                   args: openArray[string] = []): Process =
  echo "Starting ", label, "..."
  var nimArgs = @["r", sourceRelative]
  for a in args:
    nimArgs.add a
  result = startProcess(
    nimExe,
    workingDir = rootDir,
    args = nimArgs,
    options = {poParentStreams}
  )

proc stopManagedProcess(processRef: var Process, label: string) =
  if processRef.isNil:
    return
  try:
    if processRef.peekExitCode() == -1:
      echo "Stopping ", label, "..."
      processRef.terminate()
      for _ in 0 ..< 20:
        if processRef.peekExitCode() != -1:
          break
        sleep(PollIntervalMs)
      if processRef.peekExitCode() == -1:
        processRef.kill()
  except CatchableError:
    discard
  try:
    processRef.close()
  except CatchableError:
    discard
  processRef = nil

proc waitForServerReady(host: string, port: int): bool =
  let
    startedAt = getMonoTime()
    timeout = initDuration(milliseconds = ServerReadyTimeoutMs)
  while getMonoTime() - startedAt < timeout:
    var socket: Socket
    try:
      socket = newSocket()
      socket.connect(host, Port(port))
      socket.close()
      return true
    except CatchableError:
      if not socket.isNil:
        try: socket.close()
        except CatchableError: discard
      sleep(PollIntervalMs)
  echo "Timed out waiting for server on ", host, ":", port, "."
  false

when isMainModule:
  var config = QuickReplayConfig(
    live: false,
    watch: false,
    ticks: DefaultTicks,
    headless: false,
    playerCam: false,
    checkpointInterval: 5000,
    address: DefaultAddress,
    port: DefaultPort,
    bots: @["StillForge", "IronWorks", "Colm", "Zorori", "Solenne", "Rkhenna", "Pipitori"],
    seed: 0
  )

  for kind, key, val in getopt():
    case kind
    of cmdShortOption, cmdLongOption:
      case key
      of "live", "l":
        config.live = true
      of "watch", "w":
        config.watch = true
      of "ticks", "t":
        if val.len > 0: config.ticks = parseInt(val)
      of "headless":
        config.headless = true
      of "player-cam", "p":
        config.playerCam = true
      of "address", "a":
        if val.len > 0: config.address = val
      of "port":
        if val.len > 0: config.port = parseInt(val)
      of "bots", "b":
        if val.len > 0:
          config.bots = val.split(',')
      of "no-bots", "n":
        config.bots = @[]
      of "seed", "s":
        if val.len > 0: config.seed = parseInt(val)
      of "interval", "i":
        if val.len > 0: config.checkpointInterval = parseInt(val)
      of "help", "h":
        echo usage()
        quit(0)
      else:
        echo "Unknown option: " & (if kind == cmdShortOption: "-" else: "--") & key
        echo usage()
        quit(1)
    of cmdArgument:
      discard
    else: discard

  let nimExe = findExe("nim")
  if nimExe.len == 0:
    echo "Unable to find 'nim' on PATH."
    quit(1)

  let rootDir = getCurrentDir()
  # Local paths (src + players) are provided automatically by config.nims at the project root.
  # External deps (including bitworld) are provided by the nim.cfg generated via `nimby sync -g nimby.lock`.
  # No manual --path flags are required for normal development.

  if config.headless:
    echo "Running headless sim..."
    quit(execCmd(&"{nimExe} r {HeadlessSource} --ticks:{config.ticks} --interval:{config.checkpointInterval}"))

  if config.live:
    echo "Live mode: launching server + bots + fullmap viewer (for fast global view iteration)"
    # Bots are spawned as separate client processes (like quick_market) so the
    # economy actually runs. The fullmap viewer connects to /global as a pure spectator.

    let serverArgs = @[
      "--port:" & $config.port,
      "--address:" & config.address,
      "--seed:" & $config.seed
    ]

    echo "Starting live server..."
    var serverProcess: Process
    try:
      # config.nims + nimby-generated nim.cfg supply all required paths.
      var serverNimArgs = @["r", ServerSource]
      for a in serverArgs: serverNimArgs.add a
      serverProcess = startProcess(
        nimExe,
        workingDir = rootDir,
        args = serverNimArgs,
        options = {poParentStreams}
      )
      echo "  Server PID: ", serverProcess.processID
    except CatchableError as e:
      echo "Failed to start server: ", e.msg
      quit(1)

    # Wait for server to accept connections (reliable, not a fixed sleep)
    if not waitForServerReady(config.address, config.port):
      echo "Server did not become ready; aborting live mode."
      if serverProcess != nil and serverProcess.peekExitCode() == -1:
        serverProcess.terminate()
        serverProcess.close()
      quit(1)

    # Spawn bot clients so the simulation has players driving the economy.
    # Without bots the world is empty and the global viewer shows a static map.
    var botProcesses: seq[Process]
    var botNames: seq[string]
    if config.bots.len > 0:
      echo "Starting bots: ", config.bots.join(", ")
      for botName in config.bots:
        let source = findBotSource(botName)
        try:
          let p = nimRunProcess(nimExe, rootDir, botName, source,
            ["--address:" & config.address, "--port:" & $config.port,
             "--name:" & botName])
          botProcesses.add p
          botNames.add botName
        except CatchableError as e:
          echo "Failed to start bot ", botName, ": ", e.msg
          # Fall through to cleanup below
      echo "  Bots spawned: ", botProcesses.len

    echo "Starting fullmap viewer (connects live to /global as spectator)..."
    let viewerAddr = "ws://" & config.address & ":" & $config.port & "/global"
    # config.nims supplies the local paths; nimby nim.cfg supplies deps.
    var viewerNimArgs = @["r", FullmapSource, "--address:" & viewerAddr]

    let viewerRc = execCmd(nimExe & " " & viewerNimArgs.join(" "))

    # Cleanup: stop bots first, then server
    for i in countdown(botProcesses.high, 0):
      stopManagedProcess(botProcesses[i], botNames[i])
    if serverProcess != nil and serverProcess.peekExitCode() == -1:
      echo "Shutting down server..."
      serverProcess.terminate()
      serverProcess.close()
    quit(viewerRc)
  else:
    echo &"Recording 1 match ({config.ticks} ticks)..."
    # config.nims + nimby nim.cfg provide the paths.
    var rc = execCmd(&"{nimExe} r " & BatchSource & " --matches:1 --ticks:" & $config.ticks & " --fixed-lineup")
    if rc != 0:
      echo "Match recording failed."
      quit(rc)

    let replayPath = absolutePath(DefaultReplayDir / "match_0000.mbreplay")
    if not fileExists(replayPath):
      echo "Replay file not found at ", replayPath
      quit(1)

    let activeViewer = if config.playerCam: ViewerSource else: FullmapSource
    echo "Opening replay viewer..."
    # config.nims supplies local paths.
    let viewerNimArgs = @["r", activeViewer, replayPath]
    quit(execCmd(nimExe & " " & viewerNimArgs.join(" ")))
