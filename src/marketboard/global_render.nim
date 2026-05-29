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
  LegendRowHeight = BlockyCharHeight + 4
  LegendHeight* = LegendSlotCount * LegendRowHeight + 4

  DebugLayerId* = 3
  DebugLayerType = 4              # bottom-left anchor
  DebugWidth* = 90
  DebugHeight* = BlockyCharHeight + 4
  DebugTextSpriteId = 800
  DebugObjectId = 9000

  # Demo mode (global spectator only) — new anchored panel + map spotlight
  # for the currently "featured" agent derived from high-excitement legends.
  DemoPanelLayerId* = 4
  DemoPanelLayerType = 2            # top-right (see global_client.nim layer positioning for kind=2)
  DemoPanelWidth* = 120             # extra room for cargo breakdown + 5-slot gear shorthand while staying compact on screen
  DemoPanelHeight* = 220            # plenty of vertical headroom for detailed inventory + gear lines
  DemoSpotlightSpriteId = 850
  DemoPanelTextBase = 900

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
  DemoPanelObjectBase = 9500   # for demo panel content objects

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

proc addDemoFeaturedPanel(packet: var seq[uint8], sim: SimServer, featured: int) =
  ## Renders the featured agent details panel (top-right UI layer) using the exact same
  ## renderTextToRgba + MbFont + swatch pattern as the left scoreboard so text is always visible.
  ## Shows inventory, gold, and equipment with one spelled-out line per slot.
  if featured < 0 or featured >= sim.players.len:
    return

  var lastFeatured {.global.} = -2
  if featured != lastFeatured:
    echo "[demo panel] building for featured=", featured
    lastFeatured = featured

  # Remove prior frame objects in our range. Dynamic sprites are re-added each frame.
  for i in 0 ..< 25:
    packet.addRemoveObject(DemoPanelObjectBase + 200 + i)

  let p = sim.players[featured]

  # Line 1: name + role (with swatch, exactly like a scoreboard row).
  let displayName = if p.name.len > 12: p.name[0 ..< 12] else: p.name
  let roleTag = roleLabel(p.role)
  let nameLine = if roleTag.len > 0: displayName & " " & roleTag else: displayName

  # Gold on its own line so the amount is instantly readable.
  let goldLine = $p.gold & "g"

  # Inventory: only non-zero raw materials, short 1-2 char codes. Vertical space is abundant.
  let w = p.inv.wood
  let st = p.inv.stone
  let h = p.inv.hardwood
  let c = p.inv.copper
  let iw = p.inv.ironwood
  let i = p.inv.iron
  var cargoLine = ""
  if w > 0: cargoLine.add "w" & $w & " "
  if st > 0: cargoLine.add "s" & $st & " "
  if h > 0: cargoLine.add "h" & $h & " "
  if c > 0: cargoLine.add "c" & $c & " "
  if iw > 0: cargoLine.add "iw" & $iw & " "
  if i > 0: cargoLine.add "i" & $i & " "
  if cargoLine.len > 0:
    cargoLine.setLen(cargoLine.len - 1)  # trim trailing space
  else:
    cargoLine = "no mats"

  # Equipment for the active role, one full line per slot as requested.
  let gear = p.activeGear()
  let hatLine    = "Hat: lvl "   & $gearTier(gear[0])
  let shirtLine  = "Shirt: lvl " & $gearTier(gear[1])
  let glovesLine = "Gloves: lvl " & $gearTier(gear[2])
  let pantsLine  = "Pants: lvl " & $gearTier(gear[3])
  let shoesLine  = "Shoes: lvl " & $gearTier(gear[4])

  # Swatch + name, gold, cargo, then five equipment lines. No background rect.
  let textX = 2 + TileSize + 2
  var rowY = 2

  packet.addObject(DemoPanelObjectBase + 201, 2, rowY, 1, DemoPanelLayerId, SwatchSpriteBase + playerColorIndex(featured))

  let lineColor = 8'u8  # yellow for featured consistency
  let namePixels = renderTextToRgba(nameLine, lineColor)
  if namePixels.len > 0:
    let sid = DemoPanelTextBase + 0
    packet.addSprite(sid, MbFont.textWidth(nameLine), MbFont.height, namePixels)
    packet.addObject(DemoPanelObjectBase + 210, textX, rowY, 2, DemoPanelLayerId, sid)
  rowY += MbFont.height + 1

  # Gold line, slightly brighter for money feel.
  let goldPixels = renderTextToRgba(goldLine, 11'u8)
  if goldPixels.len > 0:
    let sid = DemoPanelTextBase + 1
    packet.addSprite(sid, MbFont.textWidth(goldLine), MbFont.height, goldPixels)
    packet.addObject(DemoPanelObjectBase + 211, textX, rowY, 2, DemoPanelLayerId, sid)
  rowY += MbFont.height + 1

  let cargoPixels = renderTextToRgba(cargoLine, 2'u8)
  if cargoPixels.len > 0:
    let sid = DemoPanelTextBase + 2
    packet.addSprite(sid, MbFont.textWidth(cargoLine), MbFont.height, cargoPixels)
    packet.addObject(DemoPanelObjectBase + 212, textX, rowY, 2, DemoPanelLayerId, sid)
  rowY += MbFont.height + 1

  # Five separate equipment lines (one per slot) using full names.
  let hatPixels = renderTextToRgba(hatLine, 2'u8)
  if hatPixels.len > 0:
    let sid = DemoPanelTextBase + 4
    packet.addSprite(sid, MbFont.textWidth(hatLine), MbFont.height, hatPixels)
    packet.addObject(DemoPanelObjectBase + 214, textX, rowY, 2, DemoPanelLayerId, sid)
  rowY += MbFont.height + 1

  let shirtPixels = renderTextToRgba(shirtLine, 2'u8)
  if shirtPixels.len > 0:
    let sid = DemoPanelTextBase + 5
    packet.addSprite(sid, MbFont.textWidth(shirtLine), MbFont.height, shirtPixels)
    packet.addObject(DemoPanelObjectBase + 215, textX, rowY, 2, DemoPanelLayerId, sid)
  rowY += MbFont.height + 1

  let glovesPixels = renderTextToRgba(glovesLine, 2'u8)
  if glovesPixels.len > 0:
    let sid = DemoPanelTextBase + 6
    packet.addSprite(sid, MbFont.textWidth(glovesLine), MbFont.height, glovesPixels)
    packet.addObject(DemoPanelObjectBase + 216, textX, rowY, 2, DemoPanelLayerId, sid)
  rowY += MbFont.height + 1

  let pantsPixels = renderTextToRgba(pantsLine, 2'u8)
  if pantsPixels.len > 0:
    let sid = DemoPanelTextBase + 7
    packet.addSprite(sid, MbFont.textWidth(pantsLine), MbFont.height, pantsPixels)
    packet.addObject(DemoPanelObjectBase + 217, textX, rowY, 2, DemoPanelLayerId, sid)
  rowY += MbFont.height + 1

  let shoesPixels = renderTextToRgba(shoesLine, 2'u8)
  if shoesPixels.len > 0:
    let sid = DemoPanelTextBase + 8
    packet.addSprite(sid, MbFont.textWidth(shoesLine), MbFont.height, shoesPixels)
    packet.addObject(DemoPanelObjectBase + 218, textX, rowY, 2, DemoPanelLayerId, sid)

  # Only log on actual featured change (the guarded message above). No per-frame spam.

proc buildGlobalInitPacket*(sim: SimServer, showDebug: bool = true, demoFeatured: int = -1): seq[uint8] =
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

  # Demo featured panel layer (populated when demoFeatured >= 0).
  # Compact top-right (kind=2) so it fits nicely without spilling into the center.
  packet.addLayer(DemoPanelLayerId, DemoPanelLayerType, UiFlag)
  packet.addViewport(DemoPanelLayerId, DemoPanelWidth, DemoPanelHeight)

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

proc buildGlobalFramePacket*(sim: SimServer, state: var GlobalViewerState, showDebug: bool = true, demoFeatured: int = -1): seq[uint8] =
  var packet: seq[uint8]

  if not state.initialized:
    packet = buildGlobalInitPacket(sim, showDebug, demoFeatured)
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

    # Demo mode spotlight (only for the currently featured agent from legends)
    if demoFeatured == idx:
      # Center the 9x9 ring on the 7x7 player sprite
      packet.addObject(9990 + idx, player.x - 1, player.y - 1, z + 3, MapLayerId, 850)

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

    let line1Color = if demoFeatured == i: 8'u8 else: 2'u8  # brighter yellow when featured
    let line1Pixels = renderTextToRgba(line1, line1Color)
    if line1Pixels.len > 0:
      let spriteId = ScoreboardTextSpriteBase + rowSlot
      packet.addSprite(spriteId, MbFont.textWidth(line1), MbFont.height, line1Pixels)
      packet.addObject(ScoreboardRowObjectBase + rowSlot, textX, rowY1, 0, ScoreboardLayerId, spriteId)
    inc rowSlot

    let line2Pixels = renderTextToRgba(line2, line1Color)
    if line2Pixels.len > 0:
      let spriteId = ScoreboardTextSpriteBase + rowSlot
      packet.addSprite(spriteId, MbFont.textWidth(line2), MbFont.height, line2Pixels)
      let rowY2 = 2 + rowSlot * (MbFont.height + 1)
      packet.addObject(ScoreboardRowObjectBase + rowSlot, textX + MbFont.glyphAdvance(' ') * 2, rowY2, 0, ScoreboardLayerId, spriteId)
    inc rowSlot

  # Debug tick counter, bottom-left.
  if showDebug and sim.letterSprites.len > 0:
    let tickText = $sim.tickCount
    let tickPixels = renderBlockyTextToRgba(sim.letterSprites, sim.digitSprites, tickText, 2)
    if tickPixels.len > 0:
      packet.addSprite(DebugTextSpriteId, tickText.len * BlockyCharWidth + 2, BlockyCharHeight + 2, tickPixels)
      packet.addObject(DebugObjectId, 2, 2, 0, DebugLayerId, DebugTextSpriteId)

  # Right-side demo panel (following metrics)
  if demoFeatured >= 0:
    addDemoFeaturedPanel(packet, sim, demoFeatured)

  packet

proc buildLegendPacket*(sim: SimServer, slots: openArray[string]): seq[uint8] =
  ## Builds the legend overlay layer: one left-aligned caption per slot at a
  ## fixed row, so captions never reorder or shift horizontally. Empty slots
  ## are removed so freed rows clear cleanly.
  var packet: seq[uint8]
  let maxChars = (LegendWidth - 4) div BlockyCharWidth
  for i in 0 ..< LegendSlotCount:
    let raw = if i < slots.len: slots[i] else: ""
    if raw.len == 0 or sim.letterSprites.len == 0:
      packet.addRemoveObject(LegendObjectId + i)
      continue
    let text = if raw.len > maxChars: raw[0 ..< maxChars] else: raw
    let textPixels = renderBlockyTextToRgba(sim.letterSprites, sim.digitSprites, text, 14)
    if textPixels.len == 0:
      packet.addRemoveObject(LegendObjectId + i)
      continue
    packet.addSprite(LegendTextSpriteId + i, text.len * BlockyCharWidth + 2, BlockyCharHeight + 2, textPixels)
    packet.addObject(LegendObjectId + i, 2, i * LegendRowHeight, 0, LegendLayerId, LegendTextSpriteId + i)
  packet


