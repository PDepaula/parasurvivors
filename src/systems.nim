## Pure procs on plain seqs. Generic over tuple/object types so both the
## pararules query results and hand-built test tuples work.

import math, tables, sets, random, algorithm, sequtils
import data

const
  gridCell* = 64.0
  whipHalfHeight = 30.0

type
  Hit* = object
    projId*, enemyId*: int
    damage*: float
  ProjSpec* = object
    kind*: WeaponKind
    x*, y*, vx*, vy*, size*, damage*, ttl*, angle*: float
    pierce*: int
  ChoiceKind* = enum
    NewWeapon, UpgradeWeapon, NewPassive, UpgradePassive, BonusGold, BonusHeal
  Choice* = object
    kind*: ChoiceKind
    weapon*: WeaponKind
    passive*: PassiveKind
    level*: int ## resulting level
    title*, desc*: string
  PickupResult* = object
    collected*: seq[int] ## indices into the pickups array
    magnetize*: seq[int]

proc dist*(x1, y1, x2, y2: float): float =
  sqrt((x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2))

proc enemyRadius*(size: float): float =
  size * 0.35

proc cellOf(x, y: float): (int, int) =
  (int(floor(x / gridCell)), int(floor(y / gridCell)))

proc buildGrid*[E](enemies: openArray[E]): Table[(int, int), seq[int]] =
  for i, e in enemies:
    result.mgetOrPut(cellOf(e.x, e.y), @[]).add(i)

proc hitsEnemy[P, E](p: P, e: E): bool =
  if p.kind == Whip:
    abs(e.x - p.x) < p.size / 2 + enemyRadius(e.size) and
      abs(e.y - p.y) < whipHalfHeight + enemyRadius(e.size)
  else:
    dist(p.x, p.y, e.x, e.y) < p.size + enemyRadius(e.size)

proc collide*[P, E](projs: openArray[P], enemies: openArray[E]): seq[Hit] =
  ## Every (projectile, enemy) overlap this tick, honouring pierce and hitIds.
  if enemies.len == 0:
    return
  let grid = buildGrid(enemies)
  for p in projs:
    if p.ttl <= 0:
      continue
    var allowed = p.pierce + 1 - p.hitIds.len
    if allowed <= 0:
      continue
    let reach = p.size + 40.0
    let (c0x, c0y) = cellOf(p.x - reach, p.y - reach)
    let (c1x, c1y) = cellOf(p.x + reach, p.y + reach)
    block scan:
      for cx in c0x .. c1x:
        for cy in c0y .. c1y:
          if not grid.hasKey((cx, cy)):
            continue
          for idx in grid[(cx, cy)]:
            let e = enemies[idx]
            if p.hitIds.contains(e.id):
              continue
            if hitsEnemy(p, e):
              result.add Hit(projId: p.id, enemyId: e.id, damage: p.damage)
              dec allowed
              if allowed <= 0:
                break scan

proc contactDamage*[E](enemies: openArray[E], px, py, armor, dt: float): float =
  ## Damage per tick from every enemy touching the player.
  for e in enemies:
    if dist(e.x, e.y, px, py) < enemyRadius(e.size) + playerRadius:
      result += max(1.0, e.damage - armor) * dt

proc scanPickups*[P](pickups: openArray[P], px, py, magnet: float): PickupResult =
  for i, p in pickups:
    let d = dist(p.x, p.y, px, py)
    if d < pickupRadius:
      result.collected.add i
    elif p.kind.isGem and not p.magnetized and d < magnet:
      result.magnetize.add i

proc nearestEnemy*[E](enemies: openArray[E], px, py: float): tuple[found: bool, x, y: float] =
  var best = Inf
  for e in enemies:
    let d = dist(e.x, e.y, px, py)
    if d < best:
      best = d
      result = (true, e.x, e.y)

proc offscreenPoint*(px, py, ww, wh: float): (float, float) =
  ## Random point just outside the view rectangle centred on the player.
  let hw = ww / 2 + spawnMargin
  let hh = wh / 2 + spawnMargin
  case rand(3)
  of 0: (px - hw, py + rand(hh * 2) - hh)
  of 1: (px + hw, py + rand(hh * 2) - hh)
  of 2: (px + rand(hw * 2) - hw, py - hh)
  else: (px + rand(hw * 2) - hw, py + hh)

proc tooFar*(ex, ey, px, py, ww, wh: float): bool =
  abs(ex - px) > ww / 2 + despawnMargin or abs(ey - py) > wh / 2 + despawnMargin

proc facingVec*(d: Dir): (float, float) =
  case d
  of Up: (0.0, -1.0)
  of Down: (0.0, 1.0)
  of Left: (-1.0, 0.0)
  of Right: (1.0, 0.0)

proc attackPlan*(kind: WeaponKind, level: int, st: Stats, px, py: float, facing: Dir,
                 hasNearest: bool, nx, ny: float): seq[ProjSpec] =
  ## The projectiles one weapon activation creates.
  let w = weaponAt(kind, level)
  let n = max(1, w.amount + st.amount)
  let dmg = w.damage * st.might
  let size = w.size * st.area
  let ttl = w.ttl * st.duration
  let speed = w.speed * st.projSpeed
  let (fx, fy) = facingVec(facing)
  case kind
  of Whip:
    for i in 0 ..< n:
      let side = if i mod 2 == 0: 1.0 else: -1.0
      let dirx = (if facing == Left: -1.0 else: 1.0) * side
      result.add ProjSpec(kind: Whip, x: px + dirx * size / 2, y: py - float(i div 2) * 20,
                          size: size, damage: dmg, ttl: ttl, pierce: w.pierce)
  of MagicWand:
    var dx = fx
    var dy = fy
    if hasNearest:
      dx = nx - px
      dy = ny - py
    let len = max(1e-6, sqrt(dx * dx + dy * dy))
    let base = arctan2(dy / len, dx / len)
    for i in 0 ..< n:
      let a = base + (float(i) - float(n - 1) / 2) * 0.15
      result.add ProjSpec(kind: MagicWand, x: px, y: py, vx: cos(a) * speed, vy: sin(a) * speed,
                          size: size, damage: dmg, ttl: ttl, angle: a, pierce: w.pierce)
  of Knife:
    for i in 0 ..< n:
      let off = (float(i) - float(n - 1) / 2) * 10
      result.add ProjSpec(kind: Knife, x: px - fy * off, y: py + fx * off, vx: fx * speed, vy: fy * speed,
                          size: size, damage: dmg, ttl: ttl, angle: arctan2(fy, fx), pierce: w.pierce)
  of Axe:
    for i in 0 ..< n:
      let dirx = if fx != 0: fx else: (if i mod 2 == 0: 1.0 else: -1.0)
      result.add ProjSpec(kind: Axe, x: px, y: py, vx: dirx * (60 + float(i) * 30), vy: -speed * 1.5,
                          size: size, damage: dmg, ttl: ttl, pierce: w.pierce)
  of Runetracer:
    for i in 0 ..< n:
      let a = rand(2 * PI)
      result.add ProjSpec(kind: Runetracer, x: px, y: py, vx: cos(a) * speed, vy: sin(a) * speed,
                          size: size, damage: dmg, ttl: ttl, angle: a, pierce: w.pierce)
  of Garlic:
    result.add ProjSpec(kind: Garlic, x: px, y: py, size: size, damage: dmg, ttl: w.ttl, pierce: w.pierce)
  of KingBible:
    let r = bibleOrbitRadius * st.area
    for i in 0 ..< n:
      let a = float(i) * 2 * PI / float(n)
      # vx = angular speed (rad/s), vy = orbit radius; moveProjectiles reads them that way
      result.add ProjSpec(kind: KingBible, x: px + cos(a) * r, y: py + sin(a) * r, vx: speed, vy: r,
                          size: size, damage: dmg, ttl: ttl, angle: a, pierce: w.pierce)

proc generateChoices*(owned: openArray[(WeaponKind, int)],
                      ownedPassives: openArray[(PassiveKind, int)]): seq[Choice] =
  ## Up to 3 level-up options; a gold/heal fallback when everything is maxed.
  var pool: seq[Choice]
  for (k, lvl) in owned:
    if lvl < maxWeaponLevel:
      pool.add Choice(kind: UpgradeWeapon, weapon: k, level: lvl + 1,
                      title: weaponDefs[k].name & " Lv" & $(lvl + 1), desc: weaponUpgrades[k][lvl + 1].text)
  if owned.len < maxWeaponSlots:
    for k in WeaponKind:
      if not owned.anyIt(it[0] == k):
        pool.add Choice(kind: NewWeapon, weapon: k, level: 1,
                        title: "New: " & weaponDefs[k].name, desc: weaponDefs[k].desc)
  for (k, lvl) in ownedPassives:
    if lvl < maxPassiveLevel:
      pool.add Choice(kind: UpgradePassive, passive: k, level: lvl + 1,
                      title: passiveDefs[k].name & " Lv" & $(lvl + 1), desc: passiveDefs[k].desc)
  if ownedPassives.len < maxPassiveSlots:
    for k in PassiveKind:
      if not ownedPassives.anyIt(it[0] == k):
        pool.add Choice(kind: NewPassive, passive: k, level: 1,
                        title: "New: " & passiveDefs[k].name, desc: passiveDefs[k].desc)
  shuffle(pool)
  result = pool[0 ..< min(3, pool.len)]
  if result.len == 0:
    result = @[Choice(kind: BonusGold, title: "Gold +25", desc: "Nothing left to learn"),
               Choice(kind: BonusHeal, title: "Floor Chicken", desc: "Recover 30 HP")]

proc separate*[E](enemies: openArray[E]): seq[(int, float, float)] =
  ## Soft push-apart for overlapping enemies: (id, dx, dy) to add to position.
  let grid = buildGrid(enemies)
  var push = initTable[int, (float, float)]()
  for i, a in enemies:
    let (cx, cy) = cellOf(a.x, a.y)
    for ox in -1 .. 1:
      for oy in -1 .. 1:
        if not grid.hasKey((cx + ox, cy + oy)):
          continue
        for j in grid[(cx + ox, cy + oy)]:
          if j <= i:
            continue
          let b = enemies[j]
          let minD = enemyRadius(a.size) + enemyRadius(b.size)
          let d = dist(a.x, a.y, b.x, b.y)
          if d < minD and d > 1e-6:
            let overlap = (minD - d) / 2
            let nx = (a.x - b.x) / d
            let ny = (a.y - b.y) / d
            var pa = push.getOrDefault(a.id)
            pa[0] += nx * overlap
            pa[1] += ny * overlap
            push[a.id] = pa
            var pb = push.getOrDefault(b.id)
            pb[0] -= nx * overlap
            pb[1] -= ny * overlap
            push[b.id] = pb
  for id, (dx, dy) in push.pairs:
    result.add (id, dx, dy)
  result.sort(proc (a, b: (int, float, float)): int = cmp(a[0], b[0]))
