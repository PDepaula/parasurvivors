## Everything that touches OpenGL. Reads state from the pararules session.

import paranim/opengl
import paranim/gl, paranim/gl/entities
import paranim/glm
import paranim/math as pmath
from paranim/primitives import nil
import paratext, paratext/gl/text
import stb_image/read as stbi
import pararules
import math, sequtils
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
  itemsPng = staticRead("assets/items.png")
  grassPng = staticRead("assets/grass.png")
  ttf = staticRead("assets/Roboto-Regular.ttf")

type
  Sheet = object
    frameW, frameH: int
    base: UncompiledImageEntity
    batch: InstancedImageEntity

var
  sheets: array[SheetId, Sheet]
  items: Sheet
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
  block:
    let base = loadImage(itemsPng)
    items = Sheet(frameW: 1, frameH: 1, base: base, batch: compile(game, initInstancedEntity(base)))
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

proc addIcon*(spr: Sprite, cx, cy, w: float, angle = 0.0) =
  ## Atlas icon centred at (cx, cy), `w` wide, height from the icon's own aspect.
  let r = atlas[spr]
  let h = w * float(r.h) / float(r.w)
  var e = items.base
  e.crop(float(r.x), float(r.y), float(r.w), float(r.h))
  e.translate(cx, cy)
  e.rotate(angle)
  e.translate(-w / 2, -h / 2)
  e.scale(w, h)
  items.batch.add(e)

proc addIconFit*(spr: Sprite, cx, cy, box: float) =
  ## UI icon fitted inside a box×box square. Long thin icons (spear, arrow) lie on a
  ## diagonal like an inventory slot instead of shrinking to a dash.
  let r = atlas[spr]
  if r.w > 2 * r.h:
    addIcon(spr, cx, cy, box * 1.25, -PI / 4)
  elif r.w >= r.h:
    addIcon(spr, cx, cy, box)
  else:
    addIcon(spr, cx, cy, box * float(r.w) / float(r.h))

proc flushItems[G](game: G, ww, wh: float, camera: Mat3x3[GLfloat], useCamera: bool) =
  if items.batch.attributes.a_matrix.data[].len == 0:
    return
  var b = items.batch
  b.project(ww, wh)
  if useCamera:
    b.invert(camera)
  render(game, b)
  items.batch.clear()

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

proc drawWorld[G](game: G, ww, wh, tt: float) =
  let player = session.query(gameRules.getPlayer)
  var camera = mat3f(1)
  camera.translate(player.pos.x - ww / 2, player.pos.y - wh / 2)
  let minX = player.pos.x - ww / 2 - 100
  let maxX = player.pos.x + ww / 2 + 100
  let minY = player.pos.y - wh / 2 - 100
  let maxY = player.pos.y + wh / 2 + 100

  drawGround(game, ww, wh, camera, player.pos.x, player.pos.y)

  # pickups (icons), then the garlic aura ring: both under the sprites
  for p in session.queryAll(gameRules.getPickups):
    if p.pos.x < minX or p.pos.x > maxX or p.pos.y < minY or p.pos.y > maxY:
      continue
    case p.kind
    of GemBlue, GemGreen, GemRed:
      addIcon(pickupSprite(p.kind), p.pos.x, p.pos.y + 3 * sin(tt * 4 + float(p.id)), 16)
    of Coin: addIcon(SprCoin, p.pos.x, p.pos.y, 18)
    of Chicken: addIcon(SprChicken, p.pos.x, p.pos.y, 22)
    of Chest: addIcon(SprChest, p.pos.x, p.pos.y, 28)
    of Vacuum: addIcon(SprVacuum, p.pos.x, p.pos.y, 20, tt * 3)
  let stats = session.query(gameRules.getStats).stats
  var hasGarlic = false
  for w in session.queryAll(gameRules.getWeapons):
    if weaponDefs[w.kind].motion == Aura:
      hasGarlic = true
      let r = weaponAt(w.kind, w.level).size * stats.area
      addIcon(weaponDefs[w.kind].sprite, player.pos.x, player.pos.y, r * weaponDefs[w.kind].drawScale)
  flushItems(game, ww, wh, camera, true)

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
  # player: attack sheet while the starter weapon's animation runs, else the walk sheet
  block:
    let c = characterDefs[player.hero]
    if animActive(player.anim, player.animStart, tt):
      let cell = float(sheetDefs[c.attackSheet].cellW)
      addSprite(c.attackSheet, animFrame(player.anim, player.animStart, tt), player.facing.ord,
                player.pos.x, player.pos.y, cell, cell)
    else:
      let col = if player.moving: 1 + int(tt / frameSecs) mod 8 else: 0
      let cell = float(sheetDefs[c.sheet].cellW)
      addSprite(c.sheet, col, player.facing.ord, player.pos.x, player.pos.y, cell, cell)
  flushSprites(game, ww, wh, camera)

  # projectiles, garlic bulb, hit sparks: icons over the sprites
  for p in session.queryAll(gameRules.getProjectiles):
    let d = weaponDefs[p.kind]
    if d.motion == Aura or (p.held and animActive(player.anim, player.animStart, tt)):
      continue
    addIcon(d.sprite, p.pos.x, p.pos.y, p.size * d.drawScale, p.angle + tt * d.spin)
  if hasGarlic:
    addIcon(SprGarlic, player.pos.x, player.pos.y - 44, 20)
  for e in enemies:
    if e.hitFlash > 0 and e.pos.x >= minX and e.pos.x <= maxX and e.pos.y >= minY and e.pos.y <= maxY:
      # instanced images have no per-instance alpha, so the spark shrinks instead of fading
      addIcon(SprSpark, e.pos.x, e.pos.y, 24 * e.hitFlash / hitFlashSecs)
  flushItems(game, ww, wh, camera, true)

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
    addIconFit(weaponDefs[w.kind].uiSprite, 22, y + 12, 24)
    drawText(game, $w.level, 40, y, ww, wh, white, 0.8)
    y -= 30
  y = wh - 30
  for p in session.queryAll(gameRules.getPassives):
    addIconFit(passiveDefs[p.kind].sprite, 212, y + 12, 24)
    drawText(game, $p.level, 230, y, ww, wh, white, 0.8)
    y -= 30
  flushItems(game, ww, wh, noCam, false)

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
    case c.kind
    of NewWeapon, UpgradeWeapon: addIconFit(weaponDefs[c.weapon].uiSprite, ww / 2 - 240, y + 20, 48)
    of NewPassive, UpgradePassive: addIconFit(passiveDefs[c.passive].sprite, ww / 2 - 240, y + 20, 48)
    of BonusGold: addIconFit(SprCoin, ww / 2 - 240, y + 20, 48)
    of BonusHeal: addIconFit(SprChicken, ww / 2 - 240, y + 20, 48)
    drawText(game, marker & c.title, ww / 2 - 200, y, ww, wh, if i == m.selected: yellow else: white)
    drawText(game, c.desc, ww / 2 - 170, y + 26, ww, wh, white, 0.8)
  flushItems(game, ww, wh, mat3f(1), false)
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
    let cell = float(sheetDefs[c.sheet].cellW)
    addSprite(c.sheet, 0, Down.ord, ww / 2 - 300, y + 12, cell, cell)
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
