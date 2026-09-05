## All game state lives in one pararules session. This module owns the schema,
## the rules, and the helper procs that create/destroy entities. No OpenGL here.
##
## Performance note: pararules re-scans every partial match of a join's parent
## when a fact arrives at a non-root join. Each entity therefore keeps ONE
## position fact (`Pos`) and every per-entity rule lists `(id, Pos, pos)` first,
## so the hundreds of position updates per tick hit root joins (O(1) each).
## `DeltaTime`, which is inserted once per tick, goes last.

import pararules
import sets, math, random, sequtils, tables
import data, systems
export sets

type
  Id* = enum
    Global, Player
  Attr* = enum
    # time / window / input
    DeltaTime, TotalTime, GameTime,
    WindowWidth, WindowHeight, WorldWidth, WorldHeight,
    PressedKeys, JustPressed,
    # flow
    Phase, SelectedIndex, ChoiceList, PendingLevelUps, ResultText,
    # spawning / targeting
    SpawnTimer, EnemyCount, BossesSpawned, NearestX, NearestY, HasNearest,
    # shared entity attrs
    Hero, Pos, Facing, Moving, Hp, MaxHp, Speed, Damage, Size,
    Xp, Level, XpToNext, Gold, Kills, PlayerStats, Anim, AnimStart,
    # weapon slots
    Weapon, WeaponLevel, Cooldown,
    # passive slots
    Passive, PassiveLevel,
    # enemies
    Enemy, HitFlash,
    # projectiles
    Proj, VX, VY, Ttl, Pierce, HitIds, Angle, Held, Turned,
    # pickups
    Pickup, Value, Magnetized
  PhaseKind* = enum
    Title, CharSelect, Running, LevelUp, Paused, GameOver
  IntSet* = HashSet[int]
  Choices* = ref seq[Choice]

schema Fact(Id, Attr):
  DeltaTime: float
  TotalTime: float
  GameTime: float
  WindowWidth: int
  WindowHeight: int
  WorldWidth: float
  WorldHeight: float
  PressedKeys: IntSet
  JustPressed: IntSet
  Phase: PhaseKind
  SelectedIndex: int
  ChoiceList: Choices
  PendingLevelUps: int
  ResultText: string
  SpawnTimer: float
  EnemyCount: int
  BossesSpawned: IntSet
  NearestX: float
  NearestY: float
  HasNearest: bool
  Hero: CharacterKind
  Pos: Vec2
  Facing: Dir
  Moving: bool
  Hp: float
  MaxHp: float
  Speed: float
  Damage: float
  Size: float
  Xp: int
  Level: int
  XpToNext: int
  Gold: int
  Kills: int
  PlayerStats: Stats
  Anim: BodyAnim
  AnimStart: float
  Weapon: WeaponKind
  WeaponLevel: int
  Cooldown: float
  Passive: PassiveKind
  PassiveLevel: int
  Enemy: EnemyKind
  HitFlash: float
  Proj: WeaponKind
  VX: float
  VY: float
  Ttl: float
  Pierce: int
  HitIds: IntSet
  Angle: float
  Held: bool
  Turned: bool
  Pickup: PickupKind
  Value: int
  Magnetized: bool

# ---------------------------------------------------------------- ids

var nextId = Id.high.ord + 1

proc allocId*(): int =
  result = nextId
  inc nextId

proc resetIds*() =
  nextId = Id.high.ord + 1

proc faceOf(dx, dy: float, current: Dir): Dir =
  if dx < 0: Left
  elif dx > 0: Right
  elif dy < 0: Up
  elif dy > 0: Down
  else: current

# ---------------------------------------------------------------- entity helpers (used by rules)
# Generic over the session type: FactMatch does not exist until staticRuleset runs.

proc spawnEnemy*[S](session: var S, kind: EnemyKind, x, y: float, minute: int): int =
  let d = enemyDefs[kind]
  result = allocId()
  session.insert(result, Pos, (x, y))
  session.insert(result, Enemy, kind)
  session.insert(result, Hp, if d.boss: d.hp else: d.hp * hpScale(minute))
  session.insert(result, Speed, d.speed)
  session.insert(result, Damage, d.damage)
  session.insert(result, Size, d.size)
  session.insert(result, HitFlash, 0.0)

proc retractEnemy*[S](session: var S, id: int) =
  for a in [Enemy, Pos, Hp, Speed, Damage, Size, HitFlash]:
    session.retract(id, a)

proc spawnPickup*[S](session: var S, kind: PickupKind, x, y: float, value: int): int =
  result = allocId()
  session.insert(result, Pos, (x, y))
  session.insert(result, Pickup, kind)
  session.insert(result, Value, value)
  session.insert(result, Magnetized, false)

proc retractPickup*[S](session: var S, id: int) =
  for a in [Pickup, Pos, Value, Magnetized]:
    session.retract(id, a)

proc insertProjectile*[S](session: var S, spec: ProjSpec): int =
  result = allocId()
  session.insert(result, Pos, (spec.x, spec.y))
  session.insert(result, Proj, spec.kind)
  session.insert(result, VX, spec.vx)
  session.insert(result, VY, spec.vy)
  session.insert(result, Ttl, spec.ttl)
  session.insert(result, Pierce, spec.pierce)
  session.insert(result, HitIds, initHashSet[int]())
  session.insert(result, Angle, spec.angle)
  session.insert(result, Size, spec.size)
  session.insert(result, Damage, spec.damage)
  session.insert(result, Held, spec.held)
  session.insert(result, Turned, false)

proc retractProjectile*[S](session: var S, id: int) =
  for a in [Proj, Pos, VX, VY, Ttl, Pierce, HitIds, Angle, Size, Damage, Held, Turned]:
    session.retract(id, a)

# ---------------------------------------------------------------- rules

let (initSession, rulesInternal) =
  staticRuleset(Fact, FactMatch):
    # ---- getters
    rule getWindow(Fact):
      what:
        (Global, WindowWidth, windowWidth)
        (Global, WindowHeight, windowHeight)
    rule getWorld(Fact):
      what:
        (Global, WorldWidth, worldWidth)
        (Global, WorldHeight, worldHeight)
    rule getKeys(Fact):
      what:
        (Global, PressedKeys, keys)
    rule getJustPressed(Fact):
      what:
        (Global, JustPressed, keys)
    rule getPhase(Fact):
      what:
        (Global, Phase, phase)
    rule getTime(Fact):
      what:
        (Global, TotalTime, totalTime)
        (Global, GameTime, gameTime)
    rule getMenu(Fact):
      what:
        (Global, SelectedIndex, selected)
        (Global, ChoiceList, choices)
        (Global, PendingLevelUps, pending)
        (Global, ResultText, resultText)
    rule getTargeting(Fact):
      what:
        (Global, HasNearest, hasNearest)
        (Global, NearestX, nearestX)
        (Global, NearestY, nearestY)
        (Global, EnemyCount, enemyCount)
    rule getPlayer(Fact):
      what:
        (Player, Pos, pos)
        (Player, Hero, hero)
        (Player, Facing, facing)
        (Player, Moving, moving)
        (Player, Hp, hp)
        (Player, MaxHp, maxHp)
        (Player, Xp, xp)
        (Player, Level, level)
        (Player, XpToNext, xpToNext)
        (Player, Gold, gold)
        (Player, Kills, kills)
        (Player, Anim, anim)
        (Player, AnimStart, animStart)
    rule getStats(Fact):
      what:
        (Player, PlayerStats, stats)
    rule getWeapons(Fact):
      what:
        (id, Weapon, kind)
        (id, WeaponLevel, level)
        (id, Cooldown, cooldown)
    rule getPassives(Fact):
      what:
        (id, Passive, kind)
        (id, PassiveLevel, level)
    rule getEnemies(Fact):
      what:
        (id, Pos, pos)
        (id, Enemy, kind)
        (id, Hp, hp)
        (id, Speed, speed)
        (id, Damage, damage)
        (id, Size, size)
        (id, HitFlash, hitFlash)
    rule getProjectiles(Fact):
      what:
        (id, Pos, pos)
        (id, Proj, kind)
        (id, VX, vx)
        (id, VY, vy)
        (id, Ttl, ttl)
        (id, Pierce, pierce)
        (id, HitIds, hitIds)
        (id, Angle, angle)
        (id, Size, size)
        (id, Damage, damage)
        (id, Held, held)
    rule getPickups(Fact):
      what:
        (id, Pos, pos)
        (id, Pickup, kind)
        (id, Value, value)
        (id, Magnetized, magnetized)

    # ---- per-tick rules (trigger: DeltaTime, always the last condition)
    rule tickGameTime(Fact):
      what:
        (Global, GameTime, t, then = false)
        (Global, DeltaTime, dt)
      then:
        session.insert(Global, GameTime, t + dt * clockScale)

    rule movePlayer(Fact):
      what:
        (Player, Pos, pos, then = false)
        (Player, Speed, speed, then = false)
        (Player, PlayerStats, st, then = false)
        (Player, Facing, facing, then = false)
        (Global, PressedKeys, keys, then = false)
        (Global, DeltaTime, dt)
      then:
        var dx = 0.0
        var dy = 0.0
        if keys.contains(KeyLeft) or keys.contains(KeyA): dx -= 1
        if keys.contains(KeyRight) or keys.contains(KeyD): dx += 1
        if keys.contains(KeyUp) or keys.contains(KeyW): dy -= 1
        if keys.contains(KeyDown) or keys.contains(KeyS): dy += 1
        let moving = dx != 0 or dy != 0
        if moving:
          let len = sqrt(dx * dx + dy * dy)
          let v = speed * st.speedMul * dt / len
          session.insert(Player, Pos, (pos.x + dx * v, pos.y + dy * v))
          session.insert(Player, Facing, faceOf(dx, dy, facing))
        session.insert(Player, Moving, moving)

    rule regenPlayer(Fact):
      what:
        (Player, Hp, hp, then = false)
        (Player, MaxHp, maxHp, then = false)
        (Player, PlayerStats, st, then = false)
        (Global, DeltaTime, dt)
      cond:
        st.regen > 0
        hp < maxHp
      then:
        session.insert(Player, Hp, min(maxHp, hp + st.regen * dt))

    rule tickWeapons(Fact):
      what:
        (id, Weapon, kind, then = false)
        (id, WeaponLevel, level, then = false)
        (id, Cooldown, cd, then = false)
        (Global, HasNearest, hasNearest, then = false)
        (Global, NearestX, nx, then = false)
        (Global, NearestY, ny, then = false)
        (Global, TotalTime, tt, then = false)
        (Player, Pos, ppos, then = false)
        (Player, Facing, facing, then = false)
        (Player, Hero, hero, then = false)
        (Player, PlayerStats, st, then = false)
        (Global, DeltaTime, dt)
      then:
        let cd2 = cd - dt
        if cd2 > 0:
          session.insert(id, Cooldown, cd2)
        else:
          let starter = kind == characterDefs[hero].weapon
          for spec in attackPlan(kind, level, st, ppos.x, ppos.y, facing, hasNearest, nx, ny, starter):
            discard session.insertProjectile(spec)
          if starter and weaponDefs[kind].anim != NoAnim:
            session.insert(Player, Anim, weaponDefs[kind].anim)
            session.insert(Player, AnimStart, tt)
          session.insert(id, Cooldown, weaponAt(kind, level).cooldown * st.cooldownMul)

    rule moveProjectiles(Fact):
      what:
        (id, Pos, pos, then = false)
        (id, Proj, kind, then = false)
        (id, VX, vx, then = false)
        (id, VY, vy, then = false)
        (id, Ttl, ttl, then = false)
        (id, Angle, angle, then = false)
        (id, Turned, turned, then = false)
        (Player, Pos, ppos, then = false)
        (Global, DeltaTime, dt)
      then:
        session.insert(id, Ttl, ttl - dt)
        case weaponDefs[kind].motion
        of Lunge:
          discard # stays where it was spawned
        of Aura:
          session.insert(id, Pos, ppos)
        of Orbit:
          # vx = angular speed, vy = orbit radius (see systems.attackPlan)
          let a = angle + vx * dt
          session.insert(id, Angle, a)
          session.insert(id, Pos, (ppos.x + cos(a) * vy, ppos.y + sin(a) * vy))
        of Arc:
          let vy2 = vy + axeGravity * dt
          session.insert(id, VY, vy2)
          session.insert(id, Pos, (pos.x + vx * dt, pos.y + vy2 * dt))
        of Return:
          # constant pull toward the player: flies out, slows, comes back even if the player moved
          let tx = ppos.x - pos.x
          let ty = ppos.y - pos.y
          let d = max(1e-6, sqrt(tx * tx + ty * ty))
          let nvx = vx + tx / d * boomerangAccel * dt
          let nvy = vy + ty / d * boomerangAccel * dt
          session.insert(id, VX, nvx)
          session.insert(id, VY, nvy)
          session.insert(id, Pos, (pos.x + nvx * dt, pos.y + nvy * dt))
          let homing = nvx * tx + nvy * ty > 0
          if not turned and homing:
            session.insert(id, Turned, true)
            session.insert(id, HitIds, initHashSet[int]()) # may hit the same enemies on the way back
          elif turned and d < boomerangCatchRadius:
            session.insert(id, Ttl, 0.0) # caught; stepSystems retracts expired projectiles
        of Homing, Straight:
          session.insert(id, Pos, (pos.x + vx * dt, pos.y + vy * dt))

    rule moveEnemies(Fact):
      what:
        (id, Pos, pos, then = false)
        (id, Enemy, kind, then = false)
        (id, Speed, speed, then = false)
        (Player, Pos, ppos, then = false)
        (Global, DeltaTime, dt)
      then:
        let ddx = ppos.x - pos.x
        let ddy = ppos.y - pos.y
        let d = sqrt(ddx * ddx + ddy * ddy)
        if d > 1.0:
          let v = speed * dt / d
          session.insert(id, Pos, (pos.x + ddx * v, pos.y + ddy * v))

    rule decayHitFlash(Fact):
      what:
        (id, HitFlash, f, then = false)
        (Global, DeltaTime, dt)
      cond:
        f > 0
      then:
        session.insert(id, HitFlash, max(0.0, f - dt))

    rule spawnWave(Fact):
      what:
        (Global, GameTime, t, then = false)
        (Global, SpawnTimer, timer, then = false)
        (Global, EnemyCount, count, then = false)
        (Global, WorldWidth, ww, then = false)
        (Global, WorldHeight, wh, then = false)
        (Player, Pos, ppos, then = false)
        (Global, DeltaTime, dt)
      then:
        let minute = int(t / 60)
        let wave = waveFor(minute)
        var timer2 = timer + dt
        var toSpawn = 0
        if count < wave.minCount:
          toSpawn = min(wave.minCount - count, 10)
        elif timer2 >= wave.interval:
          toSpawn = 1
        if toSpawn > 0:
          timer2 = 0
        var spawned = 0
        for i in 0 ..< toSpawn:
          if count + spawned >= maxEnemies:
            break
          let kind = wave.kinds[rand(wave.kinds.high)]
          let (sx, sy) = offscreenPoint(ppos.x, ppos.y, ww, wh)
          discard session.spawnEnemy(kind, sx, sy, minute)
          inc spawned
        session.insert(Global, SpawnTimer, timer2)
        session.insert(Global, EnemyCount, count + spawned)

    rule spawnBosses(Fact):
      what:
        (Global, BossesSpawned, done, then = false)
        (Global, WorldWidth, ww, then = false)
        (Global, WorldHeight, wh, then = false)
        (Player, Pos, ppos, then = false)
        (Global, GameTime, t)
      then:
        var done2 = done
        var changed = false
        for b in bosses:
          let key = b.minute * 100 + b.kind.ord
          if t >= float(b.minute * 60) and not done2.contains(key):
            for i in 0 ..< b.count:
              let (sx, sy) = offscreenPoint(ppos.x, ppos.y, ww, wh)
              discard session.spawnEnemy(b.kind, sx, sy, b.minute)
            done2.incl(key)
            changed = true
        if changed:
          session.insert(Global, BossesSpawned, done2)

    rule movePickups(Fact):
      what:
        (id, Pos, pos, then = false)
        (id, Pickup, kind, then = false)
        (id, Magnetized, magnetized, then = false)
        (Player, Pos, ppos, then = false)
        (Global, DeltaTime, dt)
      cond:
        magnetized
      then:
        let ddx = ppos.x - pos.x
        let ddy = ppos.y - pos.y
        let d = max(1e-6, sqrt(ddx * ddx + ddy * ddy))
        let v = min(d, gemFlySpeed * dt) / d
        session.insert(id, Pos, (pos.x + ddx * v, pos.y + ddy * v))

    # ---- reactive rules
    rule levelUp(Fact):
      what:
        (Player, Xp, xp)
        (Player, XpToNext, need, then = false)
        (Player, Level, level, then = false)
        (Global, PendingLevelUps, pending, then = false)
      cond:
        xp >= need
      then:
        session.insert(Player, Level, level + 1)
        session.insert(Player, XpToNext, xpForLevel(level + 1))
        session.insert(Global, PendingLevelUps, pending + 1)
        session.insert(Player, Xp, xp - need)

    rule playerDied(Fact):
      what:
        (Player, Hp, hp)
        (Global, GameTime, t, then = false)
        (Global, Phase, phase, then = false)
      cond:
        hp <= 0
        phase == Running
      then:
        session.insert(Global, Phase, GameOver)
        session.insert(Global, ResultText,
          if t >= float(runLengthSecs): "You survived until dawn!" else: "Slain at " & clockText(t))

let gameRules* = rulesInternal

# ---------------------------------------------------------------- session

proc newSession*(): Session[Fact, FactMatch] =
  resetIds()
  result = initSession(autoFire = false)
  for r in rulesInternal.fields:
    result.add(r)
  result.insert(Global, Phase, Title)
  result.insert(Global, PressedKeys, initHashSet[int]())
  result.insert(Global, JustPressed, initHashSet[int]())
  result.insert(Global, WindowWidth, 1024)
  result.insert(Global, WindowHeight, 768)
  result.insert(Global, WorldWidth, 1024.0 / zoom)
  result.insert(Global, WorldHeight, 768.0 / zoom)
  result.insert(Global, TotalTime, 0.0)
  result.insert(Global, GameTime, 0.0)
  result.insert(Global, SelectedIndex, 0)
  result.insert(Global, ChoiceList, Choices(nil))
  result.insert(Global, PendingLevelUps, 0)
  result.insert(Global, ResultText, "")
  result.insert(Global, SpawnTimer, 0.0)
  result.insert(Global, EnemyCount, 0)
  result.insert(Global, BossesSpawned, initHashSet[int]())
  result.insert(Global, NearestX, 0.0)
  result.insert(Global, NearestY, 0.0)
  result.insert(Global, HasNearest, false)

proc resetSession*(old: Session[Fact, FactMatch]): Session[Fact, FactMatch] =
  ## Brand-new session (drops every entity) that keeps the window facts.
  let (windowWidth, windowHeight) = old.query(gameRules.getWindow)
  let (worldWidth, worldHeight) = old.query(gameRules.getWorld)
  result = newSession()
  result.insert(Global, WindowWidth, windowWidth)
  result.insert(Global, WindowHeight, windowHeight)
  result.insert(Global, WorldWidth, worldWidth)
  result.insert(Global, WorldHeight, worldHeight)

var session* = newSession()

# ---------------------------------------------------------------- player helpers

proc addWeapon*(session: var Session[Fact, FactMatch], kind: WeaponKind, level = 1) =
  let id = allocId()
  session.insert(id, Weapon, kind)
  session.insert(id, WeaponLevel, level)
  session.insert(id, Cooldown, 0.2)

proc addPassive*(session: var Session[Fact, FactMatch], kind: PassiveKind, level = 1) =
  let id = allocId()
  session.insert(id, Passive, kind)
  session.insert(id, PassiveLevel, level)

proc recomputeStats*(session: var Session[Fact, FactMatch]) =
  let p = session.query(gameRules.getPlayer)
  let passives = session.queryAll(gameRules.getPassives).mapIt((it.kind, it.level))
  session.insert(Player, PlayerStats, computeStats(p.hero, passives))
  let newMax = maxHpFor(p.hero, passives)
  if newMax != p.maxHp:
    session.insert(Player, MaxHp, newMax)
    session.insert(Player, Hp, min(newMax, p.hp + max(0.0, newMax - p.maxHp)))

proc startRun*(session: var Session[Fact, FactMatch], hero: CharacterKind) =
  let c = characterDefs[hero]
  session.insert(Player, Hero, hero)
  session.insert(Player, Pos, (0.0, 0.0))
  session.insert(Player, Facing, Down)
  session.insert(Player, Moving, false)
  session.insert(Player, MaxHp, c.maxHp)
  session.insert(Player, Hp, c.maxHp)
  session.insert(Player, Speed, playerBaseSpeed)
  session.insert(Player, Xp, 0)
  session.insert(Player, Level, 1)
  session.insert(Player, XpToNext, xpForLevel(1))
  session.insert(Player, Gold, 0)
  session.insert(Player, Kills, 0)
  session.insert(Player, PlayerStats, c.base)
  session.insert(Player, Anim, NoAnim)
  session.insert(Player, AnimStart, 0.0)
  session.addWeapon(c.weapon)
  session.insert(Global, GameTime, 0.0)
  session.insert(Global, SpawnTimer, 0.0)
  session.insert(Global, EnemyCount, 0)
  session.insert(Global, BossesSpawned, initHashSet[int]())
  session.insert(Global, HasNearest, false)
  session.insert(Global, PendingLevelUps, 0)
  session.insert(Global, ResultText, "")
  session.insert(Global, Phase, Running)

# ---------------------------------------------------------------- per-tick systems

type
  StepEvents* = object
    hits*, kills*, gems*: int
    hurt*, chest*, chicken*, coin*, bossKilled*: bool

proc stepSystems*(session: var Session[Fact, FactMatch], dt: float): StepEvents =
  ## Runs after fireRules: N×M work on plain seqs, then writes results back.
  let player = session.query(gameRules.getPlayer)
  let (st) = session.query(gameRules.getStats)
  let (ww, wh) = session.query(gameRules.getWorld)
  let enemies = session.queryAll(gameRules.getEnemies)
  let projs = session.queryAll(gameRules.getProjectiles)
  let pickups = session.queryAll(gameRules.getPickups)
  let px = player.pos.x
  let py = player.pos.y

  # 1. projectile hits
  var hpDelta = initTable[int, float]()
  var newHitIds = initTable[int, IntSet]()
  var projIndex = initTable[int, int]()
  for i, p in projs:
    projIndex[p.id] = i
  for h in collide(projs, enemies):
    hpDelta[h.enemyId] = hpDelta.getOrDefault(h.enemyId) + h.damage
    if not newHitIds.hasKey(h.projId):
      newHitIds[h.projId] = projs[projIndex[h.projId]].hitIds
    newHitIds[h.projId].incl(h.enemyId)
    inc result.hits
  for p in projs:
    if p.ttl <= 0:
      session.retractProjectile(p.id)
    elif newHitIds.hasKey(p.id):
      let ids = newHitIds[p.id]
      if ids.len > p.pierce:
        session.retractProjectile(p.id)
      else:
        session.insert(p.id, HitIds, ids)

  # 2. damage, deaths, drops, despawn
  var xpGain = 0
  var goldGain = 0
  var heal = 0.0
  var alive = 0
  var gemCount = pickups.countIt(it.kind.isGem)
  var dead = initHashSet[int]()
  for e in enemies:
    var hp = e.hp
    if hpDelta.hasKey(e.id):
      hp -= hpDelta[e.id]
      if hp > 0:
        session.insert(e.id, Hp, hp)
        session.insert(e.id, HitFlash, hitFlashSecs)
    if hp <= 0:
      session.retractEnemy(e.id)
      dead.incl(e.id)
      inc result.kills
      let d = enemyDefs[e.kind]
      if d.boss:
        discard session.spawnPickup(Chest, e.pos.x, e.pos.y, 1)
        result.bossKilled = true
      else:
        let r = rand(1.0)
        if r < chickenChance:
          discard session.spawnPickup(Chicken, e.pos.x, e.pos.y, 0)
        elif r < chickenChance + coinChance:
          discard session.spawnPickup(Coin, e.pos.x, e.pos.y, coinValue)
        elif r < chickenChance + coinChance + vacuumChance:
          discard session.spawnPickup(Vacuum, e.pos.x, e.pos.y, 0)
        if gemCount < maxPickups:
          discard session.spawnPickup(d.gem, e.pos.x, e.pos.y, gemValue(d.gem))
          inc gemCount
        else:
          xpGain += gemValue(d.gem)
    elif tooFar(e.pos.x, e.pos.y, px, py, ww, wh):
      session.retractEnemy(e.id)
      dead.incl(e.id)
    else:
      inc alive
  session.insert(Global, EnemyCount, alive)

  # 2b. keep enemies from stacking
  var posOf = initTable[int, Vec2]()
  for e in enemies:
    posOf[e.id] = e.pos
  for (id, dx, dy) in separate(enemies):
    if id notin dead:
      let p = posOf[id]
      session.insert(id, Pos, (p.x + dx, p.y + dy))

  # 3. contact damage
  let dmg = contactDamage(enemies, px, py, st.armor, dt)
  if dmg > 0:
    result.hurt = true

  # 4. pickups
  let pr = scanPickups(pickups, px, py, baseMagnet * st.magnet)
  for i in pr.magnetize:
    session.insert(pickups[i].id, Magnetized, true)
  for i in pr.collected:
    let p = pickups[i]
    case p.kind
    of GemBlue, GemGreen, GemRed:
      xpGain += p.value
      inc result.gems
    of Chicken:
      heal += chickenHeal
      result.chicken = true
    of Coin:
      goldGain += p.value
      result.coin = true
    of Chest:
      result.chest = true
      let upgradable = session.queryAll(gameRules.getWeapons).filterIt(it.level < maxWeaponLevel)
      if upgradable.len > 0:
        let w = upgradable[rand(upgradable.high)]
        session.insert(w.id, WeaponLevel, w.level + 1)
      else:
        goldGain += chestGoldFallback
    of Vacuum:
      for g in pickups:
        if g.kind.isGem:
          session.insert(g.id, Magnetized, true)
    session.retractPickup(p.id)

  # 5. write player deltas
  if xpGain > 0:
    session.insert(Player, Xp, player.xp + xpGain)
  if goldGain > 0:
    session.insert(Player, Gold, player.gold + goldGain)
  if result.kills > 0:
    session.insert(Player, Kills, player.kills + result.kills)
  if dmg > 0 or heal > 0:
    session.insert(Player, Hp, min(player.maxHp, player.hp - dmg + heal))

  # 6. targeting for the arcane staff
  let near = nearestEnemy(enemies, px, py)
  session.insert(Global, HasNearest, near.found)
  session.insert(Global, NearestX, near.x)
  session.insert(Global, NearestY, near.y)

# ---------------------------------------------------------------- level-up flow

proc prepareChoices*(session: var Session[Fact, FactMatch]) =
  let owned = session.queryAll(gameRules.getWeapons).mapIt((it.kind, it.level))
  let ownedPassives = session.queryAll(gameRules.getPassives).mapIt((it.kind, it.level))
  var choices: Choices
  new(choices)
  choices[] = generateChoices(owned, ownedPassives)
  session.insert(Global, ChoiceList, choices)
  session.insert(Global, SelectedIndex, 0)

proc applyChoice*(session: var Session[Fact, FactMatch], c: Choice) =
  case c.kind
  of NewWeapon:
    session.addWeapon(c.weapon)
  of UpgradeWeapon:
    for w in session.queryAll(gameRules.getWeapons):
      if w.kind == c.weapon:
        session.insert(w.id, WeaponLevel, c.level)
  of NewPassive:
    session.addPassive(c.passive)
  of UpgradePassive:
    for p in session.queryAll(gameRules.getPassives):
      if p.kind == c.passive:
        session.insert(p.id, PassiveLevel, c.level)
  of BonusGold:
    session.insert(Player, Gold, session.query(gameRules.getPlayer).gold + 25)
  of BonusHeal:
    let p = session.query(gameRules.getPlayer)
    session.insert(Player, Hp, min(p.maxHp, p.hp + chickenHeal))
  session.recomputeStats()
