import supersnappy
import bitworld/protocol except TileSize
import bitworld/server
import marketboard/sim

const
  MapLayerId* = 0
  MapLayerKind = 0
  ZoomableFlag = 1
  ScoreboardLayerId* = 1
  ScoreboardLayerType = 1
  UiFlag = 2
  TileSize = MbTileSize
  MapPixelW* = WorldWidthTiles * TileSize
  MapPixelH* = WorldHeightTiles * TileSize
  ScoreboardWidth* = 160
  ScoreboardHeight* = 100

  TileGrassSpriteId = 1
  TilePathSpriteId = 2
  TileWallSpriteId = 3
  ObjectSpriteBase = 10
  PlayerSpriteBase = 100
  SelectionSpriteId = 120
  SignalSpriteBase = 130
  ProgressSpriteBase = 200
  ScoreboardTextSpriteBase = 300
  NameLabelSpriteBase = 400

  TileObjectBase = 0
  WorldObjectObjBase = 3000
  PlayerObjectBase = 4000
  SignalObjectBase = 4500
  NameLabelObjectBase = 4600
  ProgressObjectBase = 4700
  SelectionObjectId = 5000
  ScoreboardRowObjectBase = 6000

  ProgressBarWidth = 16
  ProgressBarHeight = 3
  MaxPlayers = 20
  CharWidth = 6
  CharHeight = 6

type
  GlobalViewerState* = object
    initialized*: bool

proc addU8(packet: var seq[uint8], value: uint8) =
  packet.add(value)

proc addU16(packet: var seq[uint8], value: int) =
  let v = uint16(value)
  packet.add(uint8(v and 0xff'u16))
  packet.add(uint8(v shr 8))

proc addU32(packet: var seq[uint8], value: int) =
  let v = uint32(value)
  for shift in countup(0, 24, 8):
    packet.add(uint8((v shr shift) and 0xff'u32))

proc addI16(packet: var seq[uint8], value: int) =
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

proc makeRgbaProgressBar(fill: int, maxWidth: int): seq[uint8] =
  let fillRgba = Palette[11]
  let bgRgba = Palette[1]
  result = newSeq[uint8](maxWidth * ProgressBarHeight * 4)
  for y in 0 ..< ProgressBarHeight:
    for x in 0 ..< maxWidth:
      let offset = (y * maxWidth + x) * 4
      let c = if x < fill: fillRgba else: bgRgba
      result[offset] = c.r
      result[offset + 1] = c.g
      result[offset + 2] = c.b
      result[offset + 3] = c.a

proc renderTextToRgba(letterSprites: seq[Sprite], text: string, color: uint8): seq[uint8] =
  let innerWidth = text.len * CharWidth
  let innerHeight = CharHeight
  if innerWidth == 0:
    return @[]
  let width = innerWidth + 2
  let height = innerHeight + 2
  let rgba = Palette[color and 0x0f]
  result = newSeq[uint8](width * height * 4)
  # Outline pass: draw dark pixels in 8 neighbors of each lit pixel
  var offsetX = 1
  for ch in text:
    if ch == ' ':
      offsetX += CharWidth
      continue
    var idx = -1
    if ch >= '0' and ch <= '9':
      idx = 26 + 4 + (ord(ch) - ord('0'))
    else:
      idx = letterIndex(ch)
    if idx >= 0 and idx < letterSprites.len:
      let sprite = letterSprites[idx]
      for sy in 0 ..< min(sprite.height, CharHeight):
        for sx in 0 ..< min(sprite.width, CharWidth):
          let pixelIdx = sprite.pixels[sy * sprite.width + sx]
          if pixelIdx != TransparentColorIndex and pixelIdx != 0:
            for oy in -1 .. 1:
              for ox in -1 .. 1:
                let dx = offsetX + sx + ox
                let dy = 1 + sy + oy
                if dx >= 0 and dx < width and dy >= 0 and dy < height:
                  let destOffset = (dy * width + dx) * 4
                  if result[destOffset + 3] == 0:
                    result[destOffset] = 0
                    result[destOffset + 1] = 0
                    result[destOffset + 2] = 0
                    result[destOffset + 3] = 255
    offsetX += CharWidth
  # Foreground pass: overwrite with colored text
  offsetX = 1
  for ch in text:
    if ch == ' ':
      offsetX += CharWidth
      continue
    var idx = -1
    if ch >= '0' and ch <= '9':
      idx = 26 + 4 + (ord(ch) - ord('0'))
    else:
      idx = letterIndex(ch)
    if idx >= 0 and idx < letterSprites.len:
      let sprite = letterSprites[idx]
      for sy in 0 ..< min(sprite.height, CharHeight):
        for sx in 0 ..< min(sprite.width, CharWidth):
          let pixelIdx = sprite.pixels[sy * sprite.width + sx]
          if pixelIdx != TransparentColorIndex and pixelIdx != 0:
            let dx = offsetX + sx
            let dy = 1 + sy
            if dx < width:
              let destOffset = (dy * width + dx) * 4
              result[destOffset] = rgba.r
              result[destOffset + 1] = rgba.g
              result[destOffset + 2] = rgba.b
              result[destOffset + 3] = rgba.a
    offsetX += CharWidth

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

proc activityLabel(state: PlayerState): string =
  case state
  of Idle: ""
  of Gathering: "GATH"
  of Crafting: "CRFT"
  of AtSellStall: "SELL"
  of AtBuyStall: "BUY"

proc buildGlobalInitPacket*(sim: SimServer): seq[uint8] =
  var packet: seq[uint8]

  packet.addLayer(MapLayerId, MapLayerKind, ZoomableFlag)
  packet.addViewport(MapLayerId, MapPixelW, MapPixelH)

  packet.addLayer(ScoreboardLayerId, ScoreboardLayerType, UiFlag)
  packet.addViewport(ScoreboardLayerId, ScoreboardWidth, ScoreboardHeight)

  # Tile sprites
  packet.addSprite(TileGrassSpriteId, TileSize, TileSize, makeRgbaTile(3), "Grass")
  packet.addSprite(TilePathSpriteId, TileSize, TileSize, makeRgbaTile(13), "Path")
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

  # Signal icons
  packet.addSprite(SignalSpriteBase, 3, 3, makeRgbaSignal(4), "Signal 0")
  packet.addSprite(SignalSpriteBase + 1, 3, 3, makeRgbaSignal(6), "Signal 1")
  packet.addSprite(SignalSpriteBase + 2, 3, 3, makeRgbaSignal(9), "Signal 2")
  packet.addSprite(SignalSpriteBase + 3, 3, 3, makeRgbaSignal(14), "Signal 3")

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

proc buildGlobalFramePacket*(sim: SimServer, state: var GlobalViewerState): seq[uint8] =
  var packet: seq[uint8]

  if not state.initialized:
    packet = buildGlobalInitPacket(sim)
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

  var signalCount = 0
  for idx in playerOrder:
    let player = sim.players[idx]
    let z = 2 + player.y
    packet.addObject(PlayerObjectBase + idx, player.x, player.y, z, MapLayerId, playerSpriteId(player.role))

    # Signal icon above player
    if player.signalIcon >= 0:
      let sigX = player.x + 2
      let sigY = player.y - 4
      packet.addObject(SignalObjectBase + signalCount, sigX, sigY, z + 1, MapLayerId, signalSpriteId(player.signalIcon))
      inc signalCount

    # Progress bar for active players
    if player.state in {Gathering, Crafting} and player.actionProgress > 0:
      let fill = clamp(player.actionProgress * ProgressBarWidth div 100, 0, ProgressBarWidth)
      let barSpriteId = ProgressSpriteBase + idx
      let barPixels = makeRgbaProgressBar(fill, ProgressBarWidth)
      packet.addSprite(barSpriteId, ProgressBarWidth, ProgressBarHeight, barPixels)
      let barX = player.x - (ProgressBarWidth - 7) div 2
      let barY = player.y - 6
      packet.addObject(ProgressObjectBase + idx, barX, barY, z + 2, MapLayerId, barSpriteId)

    # Player name label
    if sim.letterSprites.len > 0:
      let label = player.name
      if label.len > 0:
        let labelPixels = renderTextToRgba(sim.letterSprites, label, 15)
        if labelPixels.len > 0:
          let labelWidth = label.len * CharWidth + 2
          let labelHeight = CharHeight + 2
          let labelSpriteId = NameLabelSpriteBase + idx
          packet.addSprite(labelSpriteId, labelWidth, labelHeight, labelPixels)
          let labelX = player.x + 3 - labelWidth div 2
          let labelY = player.y + 8
          packet.addObject(NameLabelObjectBase + idx, labelX, labelY, z + 1, MapLayerId, labelSpriteId)

  # Scoreboard
  if sim.letterSprites.len > 0:
    for i, player in sim.players:
      if i >= MaxPlayers:
        break
      let roleTag = case player.role
        of NoRole: "?"
        of Gatherer: "G"
        of Crafter: "C"
      let activity = activityLabel(player.state)
      let row = roleTag & " " & player.name & " " & $player.gold & "g"
      let fullRow = if activity.len > 0: row & " " & activity else: row
      let rowPixels = renderTextToRgba(sim.letterSprites, fullRow, 15)
      if rowPixels.len > 0:
        let rowWidth = fullRow.len * CharWidth + 2
        let rowHeight = CharHeight + 2
        let rowSpriteId = ScoreboardTextSpriteBase + i
        packet.addSprite(rowSpriteId, rowWidth, rowHeight, rowPixels)
        let rowY = 2 + i * (CharHeight + 2)
        packet.addObject(ScoreboardRowObjectBase + i, 2, rowY, 0, ScoreboardLayerId, rowSpriteId)

  packet
