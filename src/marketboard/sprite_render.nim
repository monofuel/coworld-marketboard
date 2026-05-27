import supersnappy
from bitworld/protocol import Palette, ScreenWidth, ScreenHeight, loadPalette
import marketboard/sim

const
  MapLayerId* = 0
  MapLayerKind = 0
  ZoomableFlag = 1
  UiFlag = 2
  TileSize = MbTileSize

  HudTopLeftLayerId* = 1
  HudTopLeftLayerType = 1
  HudBottomLayerId* = 2
  HudBottomLayerType = 8

  TileGrassSpriteId = 1
  TilePathSpriteId = 2
  TileWallSpriteId = 3
  ObjectSpriteBase = 10
  PlayerSpriteBase = 100
  SelectionSpriteId = 120
  SignalSpriteBase = 130
  HudTextSpriteBase* = 200

  TileObjectBase = 0
  WorldObjectObjBase = 3000
  PlayerObjectBase = 4000
  SignalObjectBase = 4500
  SelectionObjectId = 5000
  HudObjectBase* = 6000

  SpriteInputPacket* = 0x84'u8

type
  PlayerViewerState* = object
    initialized*: bool

proc addU8*(packet: var seq[uint8], value: uint8) =
  packet.add(value)

proc addU16*(packet: var seq[uint8], value: int) =
  let v = uint16(value)
  packet.add(uint8(v and 0xff'u16))
  packet.add(uint8(v shr 8))

proc addU32*(packet: var seq[uint8], value: int) =
  let v = uint32(value)
  for shift in countup(0, 24, 8):
    packet.add(uint8((v shr shift) and 0xff'u32))

proc addI16*(packet: var seq[uint8], value: int) =
  let v = cast[uint16](int16(value))
  packet.add(uint8(v and 0xff'u16))
  packet.add(uint8(v shr 8))

proc addViewport(packet: var seq[uint8], layer, width, height: int) =
  packet.addU8(0x05)
  packet.addU8(uint8(layer))
  packet.addU16(width)
  packet.addU16(height)

proc addLayer(packet: var seq[uint8], layer, layerType, flags: int) =
  packet.addU8(0x06)
  packet.addU8(uint8(layer))
  packet.addU8(uint8(layerType))
  packet.addU8(uint8(flags))

proc addSprite(
  packet: var seq[uint8],
  spriteId, width, height: int,
  pixels: openArray[uint8],
  label: string = ""
) =
  packet.addU8(0x01)
  packet.addU16(spriteId)
  packet.addU16(width)
  packet.addU16(height)
  var raw = newSeq[uint8](pixels.len)
  for i in 0 ..< pixels.len:
    raw[i] = pixels[i]
  let compressed = supersnappy.compress(raw)
  packet.addU32(compressed.len)
  for b in compressed:
    packet.addU8(b)
  packet.addU16(label.len)
  for ch in label:
    packet.addU8(uint8(ord(ch)))

proc addObject(
  packet: var seq[uint8],
  objectId, x, y, z, layer, spriteId: int
) =
  packet.addU8(0x02)
  packet.addU16(objectId)
  packet.addI16(x)
  packet.addI16(y)
  packet.addI16(z)
  packet.addU8(uint8(layer))
  packet.addU16(spriteId)

proc addClearObjects(packet: var seq[uint8]) =
  packet.addU8(0x04)

proc makeRgbaTile(paletteColor: uint8): seq[uint8] =
  let rgba = Palette[paletteColor and 0x0f]
  result = newSeq[uint8](TileSize * TileSize * 4)
  for i in 0 ..< TileSize * TileSize:
    let offset = i * 4
    result[offset] = rgba.r
    result[offset + 1] = rgba.g
    result[offset + 2] = rgba.b
    result[offset + 3] = rgba.a

proc makeRgbaOutlined(fill, outline: uint8, size: int): seq[uint8] =
  let fillRgba = Palette[fill and 0x0f]
  let outRgba = Palette[outline and 0x0f]
  result = newSeq[uint8](size * size * 4)
  for y in 0 ..< size:
    for x in 0 ..< size:
      let offset = (y * size + x) * 4
      let isEdge = x == 0 or y == 0 or x == size - 1 or y == size - 1
      let c = if isEdge: outRgba else: fillRgba
      result[offset] = c.r
      result[offset + 1] = c.g
      result[offset + 2] = c.b
      result[offset + 3] = c.a

proc makeRgbaPlayer(paletteColor: uint8): seq[uint8] =
  let rgba = Palette[paletteColor and 0x0f]
  let bg = [0'u8, 0, 0, 0]
  result = newSeq[uint8](7 * 7 * 4)
  for y in 0 ..< 7:
    for x in 0 ..< 7:
      let offset = (y * 7 + x) * 4
      let visible =
        (y == 0 and x >= 2 and x <= 4) or
        (y >= 1 and y <= 2 and x >= 1 and x <= 5) or
        (y >= 3 and y <= 4 and x >= 2 and x <= 4) or
        (y >= 5 and y <= 6 and (x == 1 or x == 2 or x == 4 or x == 5))
      if visible:
        result[offset] = rgba.r
        result[offset + 1] = rgba.g
        result[offset + 2] = rgba.b
        result[offset + 3] = rgba.a
      else:
        result[offset] = bg[0]
        result[offset + 1] = bg[1]
        result[offset + 2] = bg[2]
        result[offset + 3] = bg[3]

proc makeRgbaSelection(size: int): seq[uint8] =
  let rgba = Palette[10 and 0x0f]
  result = newSeq[uint8](size * size * 4)
  for y in 0 ..< size:
    for x in 0 ..< size:
      let offset = (y * size + x) * 4
      let isBorder = x == 0 or y == 0 or x == size - 1 or y == size - 1
      if isBorder:
        result[offset] = rgba.r
        result[offset + 1] = rgba.g
        result[offset + 2] = rgba.b
        result[offset + 3] = rgba.a

proc makeRgbaSignal(paletteColor: uint8): seq[uint8] =
  let rgba = Palette[paletteColor and 0x0f]
  result = newSeq[uint8](3 * 3 * 4)
  for i in 0 ..< 9:
    let offset = i * 4
    result[offset] = rgba.r
    result[offset + 1] = rgba.g
    result[offset + 2] = rgba.b
    result[offset + 3] = rgba.a

proc objectSpriteId(obj: WorldObject): int =
  case obj.kind
  of GatherNodeObj:
    if obj.depleted: ObjectSpriteBase + 10
    else:
      case obj.material
      of WoodItem: ObjectSpriteBase
      of StoneItem: ObjectSpriteBase + 1
      of HardwoodItem: ObjectSpriteBase + 2
      of CopperItem: ObjectSpriteBase + 3
      of IronwoodItem: ObjectSpriteBase + 4
      of IronItem: ObjectSpriteBase + 5
      else: ObjectSpriteBase + 6
  of CraftStationObj:
    case obj.craftTier
    of 2: ObjectSpriteBase + 8
    of 3: ObjectSpriteBase + 9
    else: ObjectSpriteBase + 7
  of SellStallObj: ObjectSpriteBase + 11
  of BuyStallObj: ObjectSpriteBase + 12
  of GathererStallObj: ObjectSpriteBase + 13
  of CrafterStallObj: ObjectSpriteBase + 14
  of CancelStallObj: ObjectSpriteBase + 15

proc playerSpriteId(role: Role): int =
  case role
  of NoRole: PlayerSpriteBase
  of Gatherer: PlayerSpriteBase + 1
  of Crafter: PlayerSpriteBase + 2

proc signalSpriteId(icon: int): int =
  SignalSpriteBase + (icon and 3)

proc buildInitPacket*(sim: SimServer): seq[uint8] =
  var packet: seq[uint8]

  packet.addLayer(MapLayerId, MapLayerKind, ZoomableFlag)
  packet.addViewport(MapLayerId, ScreenWidth, ScreenHeight)

  packet.addLayer(HudTopLeftLayerId, HudTopLeftLayerType, UiFlag)
  packet.addViewport(HudTopLeftLayerId, 128, 40)

  packet.addLayer(HudBottomLayerId, HudBottomLayerType, UiFlag)
  packet.addViewport(HudBottomLayerId, 128, 20)

  # Tile sprites
  packet.addSprite(TileGrassSpriteId, TileSize, TileSize, makeRgbaTile(3), "Grass")
  packet.addSprite(TilePathSpriteId, TileSize, TileSize, makeRgbaTile(5), "Path")
  packet.addSprite(TileWallSpriteId, TileSize, TileSize, makeRgbaTile(1), "Wall")

  # Object sprites
  packet.addSprite(ObjectSpriteBase, TileSize, TileSize, makeRgbaOutlined(11, 4, TileSize), "Wood")
  packet.addSprite(ObjectSpriteBase + 1, TileSize, TileSize, makeRgbaOutlined(6, 5, TileSize), "Stone")
  packet.addSprite(ObjectSpriteBase + 2, TileSize, TileSize, makeRgbaOutlined(3, 4, TileSize), "Hardwood")
  packet.addSprite(ObjectSpriteBase + 3, TileSize, TileSize, makeRgbaOutlined(9, 5, TileSize), "Copper")
  packet.addSprite(ObjectSpriteBase + 4, TileSize, TileSize, makeRgbaOutlined(2, 1, TileSize), "Ironwood")
  packet.addSprite(ObjectSpriteBase + 5, TileSize, TileSize, makeRgbaOutlined(14, 1, TileSize), "Iron")
  packet.addSprite(ObjectSpriteBase + 6, TileSize, TileSize, makeRgbaOutlined(7, 1, TileSize), "Unknown")
  packet.addSprite(ObjectSpriteBase + 7, TileSize, TileSize, makeRgbaOutlined(6, 0, TileSize), "Craft T1")
  packet.addSprite(ObjectSpriteBase + 8, TileSize, TileSize, makeRgbaOutlined(8, 0, TileSize), "Craft T2")
  packet.addSprite(ObjectSpriteBase + 9, TileSize, TileSize, makeRgbaOutlined(14, 0, TileSize), "Craft T3")
  packet.addSprite(ObjectSpriteBase + 10, TileSize, TileSize, makeRgbaOutlined(5, 1, TileSize), "Depleted")
  packet.addSprite(ObjectSpriteBase + 11, TileSize, TileSize, makeRgbaOutlined(9, 4, TileSize), "Sell")
  packet.addSprite(ObjectSpriteBase + 12, TileSize, TileSize, makeRgbaOutlined(12, 4, TileSize), "Buy")
  packet.addSprite(ObjectSpriteBase + 13, TileSize, TileSize, makeRgbaOutlined(11, 3, TileSize), "Gatherer Stall")
  packet.addSprite(ObjectSpriteBase + 14, TileSize, TileSize, makeRgbaOutlined(8, 2, TileSize), "Crafter Stall")
  packet.addSprite(ObjectSpriteBase + 15, TileSize, TileSize, makeRgbaOutlined(4, 1, TileSize), "Cancel")

  # Player sprites per role
  packet.addSprite(PlayerSpriteBase, 7, 7, makeRgbaPlayer(6), "Player")
  packet.addSprite(PlayerSpriteBase + 1, 7, 7, makeRgbaPlayer(11), "Gatherer")
  packet.addSprite(PlayerSpriteBase + 2, 7, 7, makeRgbaPlayer(12), "Crafter")

  # Selection highlight
  packet.addSprite(SelectionSpriteId, TileSize, TileSize, makeRgbaSelection(TileSize), "Selection")

  # Signal icons (4 colors)
  packet.addSprite(SignalSpriteBase, 3, 3, makeRgbaSignal(4), "Signal 0")
  packet.addSprite(SignalSpriteBase + 1, 3, 3, makeRgbaSignal(6), "Signal 1")
  packet.addSprite(SignalSpriteBase + 2, 3, 3, makeRgbaSignal(9), "Signal 2")
  packet.addSprite(SignalSpriteBase + 3, 3, 3, makeRgbaSignal(14), "Signal 3")

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

proc isSpriteInputPacket*(data: string): bool =
  data.len == 2 and data[0].uint8 == SpriteInputPacket

proc spriteInputMask*(data: string): uint8 =
  data[1].uint8
