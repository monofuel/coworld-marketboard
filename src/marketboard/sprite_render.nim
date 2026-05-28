from bitworld/protocol import ScreenWidth, ScreenHeight
import marketboard/sim
import marketboard/sprite_protocol

const
  HudTopLeftLayerId = 1
  HudTopLeftLayerType = 1
  HudBottomLayerId = 2
  HudBottomLayerType = 8

  TileObjectBase = 0
  WorldObjectObjBase = 3000
  PlayerObjectBase = 4000
  SignalObjectBase = 4500
  SelectionObjectId = 5000

type
  PlayerViewerState* = object
    initialized*: bool

proc buildInitPacket*(sim: SimServer): seq[uint8] =
  var packet: seq[uint8]

  packet.addLayer(MapLayerId, MapLayerKind, ZoomableFlag)
  packet.addViewport(MapLayerId, ScreenWidth, ScreenHeight)

  packet.addLayer(HudTopLeftLayerId, HudTopLeftLayerType, UiFlag)
  packet.addViewport(HudTopLeftLayerId, 128, 40)

  packet.addLayer(HudBottomLayerId, HudBottomLayerType, UiFlag)
  packet.addViewport(HudBottomLayerId, 128, 20)

  packet.addCommonSprites()

  packet

proc buildFramePacket*(sim: SimServer, playerIndex: int, state: var PlayerViewerState): seq[uint8] =
  var packet: seq[uint8]

  if not state.initialized:
    packet = buildInitPacket(sim)
    state.initialized = true

  packet.addClearObjects()

  if playerIndex < 0 or playerIndex >= sim.players.len:
    return packet

  let player = sim.players[playerIndex]
  let
    cameraX = clamp(
      player.x + 3 - ScreenWidth div 2,
      0, WorldWidthPixels - ScreenWidth
    )
    cameraY = clamp(
      player.y + 3 - ScreenHeight div 2,
      0, WorldHeightPixels - ScreenHeight
    )

  # Visible terrain tiles
  let
    startTx = max(0, cameraX div TileSize)
    startTy = max(0, cameraY div TileSize)
    endTx = min(WorldWidthTiles - 1, (cameraX + ScreenWidth - 1) div TileSize)
    endTy = min(WorldHeightTiles - 1, (cameraY + ScreenHeight - 1) div TileSize)

  for ty in startTy .. endTy:
    for tx in startTx .. endTx:
      let tileId = TileObjectBase + (ty - startTy) * (endTx - startTx + 1) + (tx - startTx)
      let spriteId = case sim.tileKinds[tileIndex(tx, ty)]
        of GrassTile: TileGrassSpriteId
        of PathTile: TilePathSpriteId
        of WallTile: TileWallSpriteId
      packet.addObject(tileId, tx * TileSize - cameraX, ty * TileSize - cameraY, 0, MapLayerId, spriteId)

  # World objects (visible ones)
  var objCount = 0
  for i, obj in sim.objects:
    let screenX = obj.tx * TileSize - cameraX
    let screenY = obj.ty * TileSize - cameraY
    if screenX >= -TileSize and screenX < ScreenWidth and
       screenY >= -TileSize and screenY < ScreenHeight:
      packet.addObject(WorldObjectObjBase + objCount, screenX, screenY, 1, MapLayerId, objectSpriteId(obj))
      inc objCount

  # Selection highlight
  if player.state notin {Gathering, Crafting}:
    let target = sim.bestInteractionTile(player)
    if inTileBounds(target.tx, target.ty):
      let screenX = target.tx * TileSize - cameraX
      let screenY = target.ty * TileSize - cameraY
      if screenX >= 0 and screenX < ScreenWidth and screenY >= 0 and screenY < ScreenHeight:
        packet.addObject(SelectionObjectId, screenX, screenY, 2, MapLayerId, SelectionSpriteId)

  # Players
  var signalCount = 0
  for i, p in sim.players:
    let screenX = p.x - cameraX
    let screenY = p.y - cameraY
    if screenX >= -7 and screenX < ScreenWidth and
       screenY >= -7 and screenY < ScreenHeight:
      packet.addObject(PlayerObjectBase + i, screenX, screenY, 3 + screenY, MapLayerId, playerSpriteId(p.role))
      if p.signalIcon >= 0:
        let sigX = screenX + 2
        let sigY = screenY - 4
        packet.addObject(SignalObjectBase + signalCount, sigX, sigY, 4 + screenY, MapLayerId, signalSpriteId(p.signalIcon))
        inc signalCount

  packet
