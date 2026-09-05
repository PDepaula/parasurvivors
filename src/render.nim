## Everything that touches OpenGL. Reads state from the pararules session.

import paranim/opengl
import paranim/gl, paranim/gl/entities
import paranim/glm
import paranim/math as pmath
from paranim/primitives import nil
import paratext, paratext/gl/text
import stb_image/read as stbi
import pararules
import math, strutils, sequtils
import data, systems, rules

const
  frameSecs = 0.1
  fontPx = 24
  tileSize = 32.0
  groundCols = 130 # covers a 4K view with margin
  groundRows = 70
  white = vec4(1f, 1f, 1f, 1f)
  yellow = vec4(1f, 0.9f, 0.3f, 1f)
  sheetPng = block:
    var a: array[SheetId, string]
    for id in SheetId:
      a[id] = staticRead("assets/" & sheetDefs[id].file)
    a
  grassPng = staticRead("assets/grass.png")
  ttf = staticRead("assets/Roboto-Regular.ttf")

type
  Sheet = object
    frameW, frameH: int
    base: UncompiledImageEntity
    batch: InstancedImageEntity

var
  sheets: array[SheetId, Sheet]
  shapeBase: UncompiledTwoDEntity
  shapes: InstancedTwoDEntity
  ground: InstancedImageEntity
  textBase: UncompiledTextEntity
  textBatch: InstancedTextEntity

let font = initFont(ttf = ttf, fontHeight = fontPx, firstChar = 32, bitmapWidth = 512, bitmapHeight = 512, charCount = 96)

# ---------------------------------------------------------------- loading

proc loadImage(png: string): UncompiledImageEntity =
  var width, height, channels: int
  let data = stbi.loadFromMemory(cast[seq[uint8]](png), width, height, channels, stbi.RGBA)
  initImageEntity(data, width, height)

proc initRender*[G](game: var G) =
  glEnable(GL_BLEND)
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
  glDisable(GL_CULL_FACE)
  glDisable(GL_DEPTH_TEST)
  for id in SheetId:
    let base = loadImage(sheetPng[id])
    sheets[id] = Sheet(frameW: sheetDefs[id].cellW, frameH: sheetDefs[id].cellH, base: base,
                       batch: compile(game, initInstancedEntity(base)))
  shapeBase = initTwoDEntity(primitives.rectangle[GLfloat]())
  shapes = compile(game, initInstancedEntity(shapeBase))
  block:
    let grass = loadImage(grassPng)
    var inst = initInstancedEntity(grass)
    for i in 0 ..< groundCols:
      for j in 0 ..< groundRows:
        var e = grass
        e.crop(tileSize, tileSize * 3, tileSize, tileSize) # plain interior tile of the big grass block
        e.translate(float(i) * tileSize, float(j) * tileSize)
        e.scale(tileSize, tileSize)
        inst.add(e)
    ground = compile(game, inst)
  textBase = initTextEntity(font)
  textBatch = compile(game, initInstancedEntity(textBase))

# ---------------------------------------------------------------- batches

proc clear(b: var InstancedImageEntity) =
  b.attributes.a_matrix.data[].setLen(0)
  b.attributes.a_texture_matrix.data[].setLen(0)
  b.instanceCount = 0

proc clear(b: var InstancedTwoDEntity) =
  b.attributes.a_matrix.data[].setLen(0)
  b.attributes.a_color.data[].setLen(0)
  b.instanceCount = 0

proc clear(b: var InstancedTextEntity) =
  b.attributes.a_translate_matrix.data[].setLen(0)
  b.attributes.a_scale_matrix.data[].setLen(0)
  b.attributes.a_texture_matrix.data[].setLen(0)
  b.attributes.a_color.data[].setLen(0)
  b.instanceCount = 0

proc addSprite(id: SheetId, col, row: int, cx, cy, w, h: float, flip = false) =
  var e = sheets[id].base
  let fw = float(sheets[id].frameW)
  let fh = float(sheets[id].frameH)
  e.crop(float(col) * fw, float(row) * fh, fw, fh)
  if flip:
    e.translate(cx + w / 2, cy - h / 2)
    e.scale(-w, h)
  else:
    e.translate(cx - w / 2, cy - h / 2)
    e.scale(w, h)
  sheets[id].batch.add(e)

proc flushSprites[G](game: G, ww, wh: float, camera: Mat3x3[GLfloat]) =
  for id in SheetId:
    if sheets[id].batch.attributes.a_matrix.data[].len == 0:
      continue
    var b = sheets[id].batch
    b.project(ww, wh)
    b.invert(camera)
    render(game, b)
    sheets[id].batch.clear()

proc addRect*(cx, cy, w, h, angle: float, color: Vec4[GLfloat]) =
  var e = shapeBase
  e.translate(cx, cy)
  e.rotate(angle)
  e.translate(-w / 2, -h / 2)
  e.scale(w, h)
  e.color(color)
  shapes.add(e)

proc flushShapes[G](game: G, ww, wh: float, camera: Mat3x3[GLfloat], useCamera: bool) =
  if shapes.attributes.a_matrix.data[].len == 0:
    return
  var s = shapes
  s.project(ww, wh)
  if useCamera:
    s.invert(camera)
  render(game, s)
  shapes.clear()

proc textWidth*(s: string, scale = 1.0): float =
  for ch in s:
    let idx = int(ch) - font.firstChar
    if idx >= 0 and idx < 96:
      result += font.chars[idx].xadvance * scale

proc drawText*[G](game: G, s: string, x, y, ww, wh: float, color = white, scale = 1.0) =
  textBatch.clear()
  var cx = 0f
  for ch in s:
    let idx = int(ch) - font.firstChar
    if idx < 0 or idx >= 96:
      continue
    let bc = font.chars[idx]
    var e = textBase
    e.crop(bc, cx, font.baseline)
    e.color(color)
    textBatch.add(e)
    cx += bc.xadvance
  if cx == 0:
    return
  var t = textBatch
  t.project(ww, wh)
  t.translate(x, y)
  t.scale(scale, scale)
  render(game, t)

proc drawTextCentered*[G](game: G, s: string, cy, ww, wh: float, color = white, scale = 1.0) =
  drawText(game, s, ww / 2 - textWidth(s, scale) / 2, cy, ww, wh, color, scale)

# ---------------------------------------------------------------- world

proc dirRow(dx, dy: float): int =
  if abs(dx) > abs(dy):
    (if dx < 0: Left.ord else: Right.ord)
  else:
    (if dy < 0: Up.ord else: Down.ord)

proc drawGround[G](game: G, ww, wh: float, camera: Mat3x3[GLfloat], px, py: float) =
  var g = ground
  g.project(ww, wh)
  g.invert(camera)
  g.translate(floor((px - ww / 2) / tileSize) * tileSize - tileSize,
              floor((py - wh / 2) / tileSize) * tileSize - tileSize)
  render(game, g)

proc pickupColor(kind: PickupKind): Vec4[GLfloat] =
  case kind
  of GemBlue: vec4(0.3f, 0.6f, 1f, 1f)
  of GemGreen: vec4(0.3f, 1f, 0.4f, 1f)
  of GemRed: vec4(1f, 0.3f, 0.3f, 1f)
  of Chicken: vec4(1f, 0.75f, 0.4f, 1f)
  of Coin: vec4(1f, 0.85f, 0.1f, 1f)
  of Chest: vec4(0.6f, 0.35f, 0.1f, 1f)
  of Vacuum: vec4(0.8f, 0.3f, 1f, 1f)

proc projColor(kind: WeaponKind): Vec4[GLfloat] =
  case kind
  of DragonSpear: vec4(1f, 1f, 1f, 0.7f)
  of ArcaneStaff: vec4(0.5f, 0.7f, 1f, 1f)
  of Longbow: vec4(0.85f, 0.85f, 0.9f, 1f)
  of WarAxe: vec4(0.7f, 0.5f, 0.3f, 1f)
  of Boomerang: vec4(0.4f, 1f, 0.6f, 1f)
  of Garlic: vec4(1f, 1f, 0.8f, 0.25f)
  of RoundShield: vec4(0.9f, 0.8f, 0.5f, 1f)

proc drawWorld[G](game: G, ww, wh, tt: float) =
  let player = session.query(gameRules.getPlayer)
  var camera = mat3f(1)
  camera.translate(player.pos.x - ww / 2, player.pos.y - wh / 2)
  let minX = player.pos.x - ww / 2 - 100
  let maxX = player.pos.x + ww / 2 + 100
  let minY = player.pos.y - wh / 2 - 100
  let maxY = player.pos.y + wh / 2 + 100

  drawGround(game, ww, wh, camera, player.pos.x, player.pos.y)

  # pickups
  for p in session.queryAll(gameRules.getPickups):
    if p.pos.x < minX or p.pos.x > maxX or p.pos.y < minY or p.pos.y > maxY:
      continue
    case p.kind
    of GemBlue, GemGreen, GemRed:
      addRect(p.pos.x, p.pos.y, 10, 10, PI / 4, pickupColor(p.kind))
    of Chest:
      addRect(p.pos.x, p.pos.y, 28, 20, 0, pickupColor(p.kind))
    else:
      addRect(p.pos.x, p.pos.y, 16, 16, 0, pickupColor(p.kind))
  # garlic aura (drawn as two rotated squares)
  for w in session.queryAll(gameRules.getWeapons):
    if w.kind == Garlic:
      let r = weaponAt(Garlic, w.level).size * session.query(gameRules.getStats).stats.area
      addRect(player.pos.x, player.pos.y, r * 2, r * 2, 0, projColor(Garlic))
      addRect(player.pos.x, player.pos.y, r * 2, r * 2, PI / 4, projColor(Garlic))
  flushShapes(game, ww, wh, camera, true)

  # enemies
  let enemies = session.queryAll(gameRules.getEnemies)
  for e in enemies:
    if e.pos.x < minX or e.pos.x > maxX or e.pos.y < minY or e.pos.y > maxY:
      continue
    let d = enemyDefs[e.kind]
    let sh = sheets[d.sheet]
    let h = d.size
    let w = h * float(sh.frameW) / float(sh.frameH)
    let dx = player.pos.x - e.pos.x
    let dy = player.pos.y - e.pos.y
    let phase = int(tt / frameSecs) + e.id
    case e.kind
    of Bat:
      addSprite(d.sheet, phase mod 3, 0, e.pos.x, e.pos.y, w, h)
    of Koalio:
      addSprite(d.sheet, 2 + phase mod 3, 0, e.pos.x, e.pos.y, w, h, flip = dx < 0)
    of Parakeet:
      addSprite(d.sheet, phase mod 3, 0, e.pos.x, e.pos.y, w, h, flip = dx < 0)
    else:
      addSprite(d.sheet, 1 + phase mod 8, dirRow(dx, dy), e.pos.x, e.pos.y, w, h)
  # player
  block:
    let sheet = characterDefs[player.hero].sheet
    let col = if player.moving: 1 + int(tt / frameSecs) mod 8 else: 0
    addSprite(sheet, col, player.facing.ord, player.pos.x, player.pos.y, 64, 64)
  flushSprites(game, ww, wh, camera)

  # projectiles and hit flashes
  for p in session.queryAll(gameRules.getProjectiles):
    case p.kind
    of DragonSpear:
      addRect(p.pos.x, p.pos.y, p.size, 12, 0, projColor(DragonSpear))
    of Longbow:
      addRect(p.pos.x, p.pos.y, 22, 6, p.angle, projColor(Longbow))
    of WarAxe:
      addRect(p.pos.x, p.pos.y, p.size * 1.4, p.size * 1.4, p.angle, projColor(WarAxe))
    of Garlic:
      discard
    else:
      addRect(p.pos.x, p.pos.y, p.size * 1.6, p.size * 1.6, p.angle, projColor(p.kind))
  for e in enemies:
    if e.hitFlash > 0 and e.pos.x >= minX and e.pos.x <= maxX and e.pos.y >= minY and e.pos.y <= maxY:
      addRect(e.pos.x, e.pos.y, e.size * 0.6, e.size * 0.6, 0, vec4(1f, 1f, 1f, 0.6f))
  # hp bar under the player
  addRect(player.pos.x, player.pos.y + 38, 40, 6, 0, vec4(0.3f, 0f, 0f, 0.9f))
  let hpFrac = max(0.0, player.hp / player.maxHp)
  addRect(player.pos.x - 20 + 20 * hpFrac, player.pos.y + 38, 40 * hpFrac, 6, 0, vec4(0.2f, 0.9f, 0.2f, 0.9f))
  flushShapes(game, ww, wh, camera, true)

proc drawHud[G](game: G, ww, wh, gameTime: float) =
  let player = session.query(gameRules.getPlayer)
  let noCam = mat3f(1)
  addRect(ww / 2, 10, ww, 20, 0, vec4(0.05f, 0.05f, 0.1f, 0.9f))
  let frac = min(1.0, float(player.xp) / float(max(1, player.xpToNext)))
  addRect(ww * frac / 2, 10, ww * frac, 20, 0, vec4(0.3f, 0.5f, 1f, 1f))
  flushShapes(game, ww, wh, noCam, false)
  drawText(game, "LV " & $player.level, ww - 90, 0, ww, wh)
  drawTextCentered(game, clockText(gameTime), 24, ww, wh, scale = 1.3)
  drawText(game, "Kills " & $player.kills & "   Gold " & $player.gold, 10, 24, ww, wh, yellow)
  var y = wh - 30
  for w in session.queryAll(gameRules.getWeapons):
    drawText(game, weaponDefs[w.kind].name & " " & $w.level, 10, y, ww, wh, white, 0.8)
    y -= 22
  y = wh - 30
  for p in session.queryAll(gameRules.getPassives):
    drawText(game, passiveDefs[p.kind].name & " " & $p.level, 200, y, ww, wh, white, 0.8)
    y -= 22

proc drawOverlay[G](game: G, ww, wh: float, alpha = 0.7f) =
  addRect(ww / 2, wh / 2, ww, wh, 0, vec4(0f, 0f, 0f, alpha))
  flushShapes(game, ww, wh, mat3f(1), false)

proc drawLevelUp[G](game: G, ww, wh: float) =
  drawOverlay(game, ww, wh)
  drawTextCentered(game, "LEVEL UP!", wh / 2 - 150, ww, wh, yellow, 1.5)
  let m = session.query(gameRules.getMenu)
  if m.choices == nil:
    return
  for i, c in m.choices[]:
    let y = wh / 2 - 70 + float(i) * 70
    let marker = if i == m.selected: "> " else: "  "
    drawText(game, marker & c.title, ww / 2 - 200, y, ww, wh, if i == m.selected: yellow else: white)
    drawText(game, c.desc, ww / 2 - 170, y + 26, ww, wh, white, 0.8)
  drawTextCentered(game, "Up/Down + Enter, or 1/2/3", wh - 60, ww, wh, white, 0.8)

proc drawPaused[G](game: G, ww, wh: float) =
  drawOverlay(game, ww, wh, 0.5f)
  drawTextCentered(game, "PAUSED", wh / 2 - 20, ww, wh, yellow, 2.0)

proc drawGameOver[G](game: G, ww, wh: float) =
  drawOverlay(game, ww, wh)
  let m = session.query(gameRules.getMenu)
  let p = session.query(gameRules.getPlayer)
  drawTextCentered(game, m.resultText, wh / 2 - 80, ww, wh, yellow, 1.5)
  drawTextCentered(game, "Level " & $p.level & "   Kills " & $p.kills & "   Gold " & $p.gold, wh / 2, ww, wh)
  drawTextCentered(game, "Press R to retry", wh / 2 + 60, ww, wh)

proc drawTitle[G](game: G, ww, wh: float) =
  drawTextCentered(game, "PARASURVIVORS", wh / 2 - 120, ww, wh, yellow, 2.5)
  drawTextCentered(game, "Press Enter", wh / 2, ww, wh)
  drawTextCentered(game, "Art: Liberated Pixel Cup contributors (CC-BY-SA 3.0), see CREDITS.md", wh - 40, ww, wh, white, 0.7)

proc drawCharSelect[G](game: G, ww, wh: float) =
  drawTextCentered(game, "Choose your survivor", 80, ww, wh, yellow, 1.5)
  let m = session.query(gameRules.getMenu)
  for i, hero in [Otto, Imma, Lina, Gino]:
    let c = characterDefs[hero]
    let y = 180 + float(i) * 90
    let marker = if i == m.selected: "> " else: "  "
    drawText(game, marker & c.name & "  -  " & weaponDefs[c.weapon].name & "  -  " & c.perk, ww / 2 - 260, y, ww, wh,
             if i == m.selected: yellow else: white)
    addSprite(c.sheet, 0, Down.ord, ww / 2 - 300, y + 12, 64, 64)
  flushSprites(game, ww, wh, mat3f(1))
  drawTextCentered(game, "Up/Down + Enter", wh - 60, ww, wh, white, 0.8)

# ---------------------------------------------------------------- frame

proc drawFrame*[G](game: G) =
  let (windowWidth, windowHeight) = session.query(gameRules.getWindow)
  let (ww, wh) = session.query(gameRules.getWorld)
  let (phase) = session.query(gameRules.getPhase)
  let (tt, gameTime) = session.query(gameRules.getTime)
  glClearColor(0.16, 0.22, 0.12, 1f)
  glClear(GL_COLOR_BUFFER_BIT)
  glViewport(0, 0, int32(windowWidth), int32(windowHeight))
  case phase
  of Title:
    drawTitle(game, ww, wh)
  of CharSelect:
    drawCharSelect(game, ww, wh)
  of Running:
    drawWorld(game, ww, wh, tt)
    drawHud(game, ww, wh, gameTime)
  of LevelUp:
    drawWorld(game, ww, wh, tt)
    drawHud(game, ww, wh, gameTime)
    drawLevelUp(game, ww, wh)
  of Paused:
    drawWorld(game, ww, wh, tt)
    drawHud(game, ww, wh, gameTime)
    drawPaused(game, ww, wh)
  of GameOver:
    drawWorld(game, ww, wh, tt)
    drawGameOver(game, ww, wh)
