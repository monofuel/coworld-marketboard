import bitworld/pixelfonts
import marketboard/sim
import marketboard/sprite_protocol

const
  ScoreboardLayerId* = 1
  ScoreboardLayerType = 1
  LegendLayerId* = 2
  LegendLayerType = 8
  MapPixelW* = WorldWidthTiles * TileSize
  MapPixelH* = WorldHeightTiles * TileSize
  ScoreboardWidth* = 150
  # Increased from 180 to give headroom for 7+ players (14+ text lines at ~7px each)
  # plus margins. Prevents the last player's entry from being cut off at the bottom
  # of the scoreboard UI layer.
  ScoreboardHeight* = 256
  LegendWidth* = 290
  LegendSlotCount* = 3
  LegendRowHeight = 8
  LegendHeight* = LegendSlotCount * LegendRowHeight + 4

  DebugLayerId* = 3
  DebugLayerType = 4              # bottom-left anchor
  DebugWidth* = 90
  DebugHeight* = 10
  DebugTextSpriteId = 800
  DebugObjectId = 9000

  ProgressSpriteBase = 200
  ScoreboardTextSpriteBase = 300
  PlayerIdentitySpriteBase = 600
  SwatchSpriteBase = 700
  LegendTextSpriteId = 500

  TileObjectBase = 0
  WorldObjectObjBase = 3000
  PlayerObjectBase = 4000
  SignalObjectBase = 4500
  ProgressObjectBase = 4700
  SelectionObjectBase = 5000
  ScoreboardRowObjectBase = 6000
  SwatchObjectBase = 8000
  LegendObjectId = 7000

  ProgressBarWidth = 16
  ProgressBarHeight = 3
  MaxPlayers = 20

  # Distinct identity colors assigned to agents by slot, so a viewer can
  # follow a personality on the map and match it to the scoreboard swatch.
  PlayerColors = [3, 7, 8, 11, 14, 9, 4, 6, 13, 1]

type
  GlobalViewerState* = object
    initialized*: bool

proc roleLabel(role: Role): string =
  case role
  of NoRole: ""
  of Gatherer: "G"
  of Crafter: "C"

proc playerColorIndex(idx: int): int =
  ## Returns the identity-color slot for a player, by their seat index.
  idx mod PlayerColors.len

proc buildGlobalInitPacket*(sim: SimServer, showDebug: bool = true): seq[uint8] =
  var packet: seq[uint8]

  packet.addLayer(MapLayerId, MapLayerKind, ZoomableFlag)
  packet.addViewport(MapLayerId, MapPixelW, MapPixelH)

  packet.addLayer(ScoreboardLayerId, ScoreboardLayerType, UiFlag)
  packet.addViewport(ScoreboardLayerId, ScoreboardWidth, ScoreboardHeight)

  packet.addLayer(LegendLayerId, LegendLayerType, UiFlag)
  packet.addViewport(LegendLayerId, LegendWidth, LegendHeight)

  if showDebug:
    packet.addLayer(DebugLayerId, DebugLayerType, UiFlag)
    packet.addViewport(DebugLayerId, DebugWidth, DebugHeight)

  packet.addCommonSprites()

  # Per-agent identity sprites: a uniquely colored body and a matching
  # scoreboard swatch, so a viewer can follow a personality on the map.
  for i, color in PlayerColors:
    packet.addSprite(PlayerIdentitySpriteBase + i, 7, 7, makeRgbaPlayer(color.uint8), "Agent " & $i)
    packet.addSprite(SwatchSpriteBase + i, TileSize, TileSize, makeRgbaTile(color.uint8), "Swatch " & $i)

  # Static terrain tiles
  for ty in 0 ..< WorldHeightTiles:
    for tx in 0 ..< WorldWidthTiles:
      let tileId = TileObjectBase + ty * WorldWidthTiles + tx
      let spriteId = case sim.tileKinds[tileIndex(tx, ty)]
        of GrassTile: TileGrassSpriteId
        of PathTile: TilePathSpriteId
        of WallTile: TileWallSpriteId
      packet.addObject(tileId, tx * TileSize, ty * TileSize, 0, MapLayerId, spriteId)

  # Static world objects
  for i, obj in sim.objects:
    let objId = WorldObjectObjBase + i
    packet.addObject(objId, obj.tx * TileSize, obj.ty * TileSize, 1, MapLayerId, objectSpriteId(obj))

  packet

proc buildGlobalFramePacket*(sim: SimServer, state: var GlobalViewerState, showDebug: bool = true): seq[uint8] =
  var packet: seq[uint8]

  if not state.initialized:
    packet = buildGlobalInitPacket(sim, showDebug)
    state.initialized = true

  # Update world objects (depletion changes)
  for i, obj in sim.objects:
    let objId = WorldObjectObjBase + i
    packet.addObject(objId, obj.tx * TileSize, obj.ty * TileSize, 1, MapLayerId, objectSpriteId(obj))

  # Players sorted by Y for depth
  var playerOrder = newSeq[int](sim.players.len)
  for i in 0 ..< sim.players.len:
    playerOrder[i] = i
  for i in 1 ..< playerOrder.len:
    var j = i
    while j > 0 and sim.players[playerOrder[j]].y < sim.players[playerOrder[j - 1]].y:
      swap(playerOrder[j], playerOrder[j - 1])
      dec j

  for idx in playerOrder:
    let player = sim.players[idx]
    let z = 2 + player.y
    packet.addObject(PlayerObjectBase + idx, player.x, player.y, z, MapLayerId, PlayerIdentitySpriteBase + playerColorIndex(idx))

    # Signal icon above player, removed when the player stops signaling.
    if player.signalIcon >= 0:
      packet.addObject(SignalObjectBase + idx, player.x + 2, player.y - 4, z + 1, MapLayerId, signalSpriteId(player.signalIcon))
    else:
      packet.addRemoveObject(SignalObjectBase + idx)

    # Gather/craft progress bar, removed when the player goes idle.
    if player.state in {Gathering, Crafting} and player.actionProgress > 0:
      let totalWork = sim.effectiveActionWork(player)
      let fill = clamp(player.actionProgress * ProgressBarWidth div max(1, totalWork), 0, ProgressBarWidth)
      let barSpriteId = ProgressSpriteBase + idx
      packet.addSprite(barSpriteId, ProgressBarWidth, ProgressBarHeight, makeRgbaProgressBar(fill, ProgressBarWidth, ProgressBarHeight))
      packet.addObject(ProgressObjectBase + idx, player.x - (ProgressBarWidth - 7) div 2, player.y - 6, z + 2, MapLayerId, barSpriteId)
    else:
      packet.addRemoveObject(ProgressObjectBase + idx)

    # Selection highlight, removed while gathering/crafting or with no target.
    let target = sim.bestInteractionTile(player)
    if player.state notin {Gathering, Crafting} and inTileBounds(target.tx, target.ty):
      packet.addObject(SelectionObjectBase + idx, target.tx * TileSize, target.ty * TileSize, 2, MapLayerId, SelectionSpriteId)
    else:
      packet.addRemoveObject(SelectionObjectBase + idx)

  # Scoreboard: identity swatch + two lines per player
  var rowSlot = 0
  for i, player in sim.players:
    if i >= MaxPlayers:
      break
    let displayName = if player.name.len > 12: player.name[0 ..< 12] else: player.name
    let roleTag = roleLabel(player.role)
    let line1 = if roleTag.len > 0: displayName & " " & roleTag else: displayName
    let totalMats = player.inv.wood + player.inv.stone +
      player.inv.hardwood + player.inv.copper +
      player.inv.ironwood + player.inv.iron
    var line2 = $player.gold & "g  lvl " & $player.gearLevel()
    if totalMats > 0:
      line2.add "  " & $totalMats & " mat"

    let
      textX = 2 + TileSize + 2
      rowY1 = 2 + rowSlot * (MbFont.height + 1)

    # Identity swatch aligned with the name line.
    packet.addObject(SwatchObjectBase + i, 2, rowY1, 0, ScoreboardLayerId, SwatchSpriteBase + playerColorIndex(i))

    let line1Pixels = renderTextToRgba(line1, 2)
    if line1Pixels.len > 0:
      let spriteId = ScoreboardTextSpriteBase + rowSlot
      packet.addSprite(spriteId, MbFont.textWidth(line1), MbFont.height, line1Pixels)
      packet.addObject(ScoreboardRowObjectBase + rowSlot, textX, rowY1, 0, ScoreboardLayerId, spriteId)
    inc rowSlot

    let line2Pixels = renderTextToRgba(line2, 2)
    if line2Pixels.len > 0:
      let spriteId = ScoreboardTextSpriteBase + rowSlot
      packet.addSprite(spriteId, MbFont.textWidth(line2), MbFont.height, line2Pixels)
      let rowY2 = 2 + rowSlot * (MbFont.height + 1)
      packet.addObject(ScoreboardRowObjectBase + rowSlot, textX + MbFont.glyphAdvance(' ') * 2, rowY2, 0, ScoreboardLayerId, spriteId)
    inc rowSlot

  # Debug tick counter, bottom-left. Uses tiny5 typography.
  if showDebug:
    let tickText = $sim.tickCount
    let tickPixels = renderTextToRgba(tickText, 2)
    if tickPixels.len > 0:
      let w = MbFont.textWidth(tickText)
      packet.addSprite(DebugTextSpriteId, w, MbFont.height, tickPixels)
      packet.addObject(DebugObjectId, 2, 2, 0, DebugLayerId, DebugTextSpriteId)

  packet

proc buildLegendPacket*(sim: SimServer, slots: openArray[string]): seq[uint8] =
  ## Builds the legend overlay layer: one left-aligned caption per slot at a
  ## fixed row, so captions never reorder or shift horizontally. Empty slots
  ## are removed so freed rows clear cleanly. Uses tiny5 for clean typography.
  var packet: seq[uint8]
  for i in 0 ..< LegendSlotCount:
    let text = if i < slots.len: slots[i] else: ""
    if text.len == 0:
      packet.addRemoveObject(LegendObjectId + i)
      continue
    let textPixels = renderTextToRgba(text, 8)
    if textPixels.len == 0:
      packet.addRemoveObject(LegendObjectId + i)
      continue
    let w = MbFont.textWidth(text)
    packet.addSprite(LegendTextSpriteId + i, w, MbFont.height, textPixels)
    packet.addObject(LegendObjectId + i, 2, i * LegendRowHeight, 0, LegendLayerId, LegendTextSpriteId + i)
  packet
