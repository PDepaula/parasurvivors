## All game state lives in one pararules session. This module owns the schema,
## the rules, and the helper procs that create/destroy entities. No OpenGL here.

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
    Hero, X, Y, Facing, Moving, Hp, MaxHp, Speed, Damage, Size,
    Xp, Level, XpToNext, Gold, Kills, PlayerStats,
    # weapon slots
    Weapon, WeaponLevel, Cooldown,
    # passive slots
    Passive, PassiveLevel,
    # enemies
    Enemy, HitFlash,
    # projectiles
    Proj, VX, VY, Ttl, Pierce, HitIds, Angle,
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
  X: float
  Y: float
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
        (Player, Hero, hero)
        (Player, X, x)
        (Player, Y, y)
        (Player, Facing, facing)
        (Player, Moving, moving)
        (Player, Hp, hp)
        (Player, MaxHp, maxHp)
        (Player, Xp, xp)
        (Player, Level, level)
        (Player, XpToNext, xpToNext)
        (Player, Gold, gold)
        (Player, Kills, kills)
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
        (id, Enemy, kind)
        (id, X, x)
        (id, Y, y)
        (id, Hp, hp)
        (id, Speed, speed)
        (id, Damage, damage)
        (id, Size, size)
        (id, HitFlash, hitFlash)
    rule getProjectiles(Fact):
      what:
        (id, Proj, kind)
        (id, X, x)
        (id, Y, y)
        (id, VX, vx)
        (id, VY, vy)
        (id, Ttl, ttl)
        (id, Pierce, pierce)
        (id, HitIds, hitIds)
        (id, Angle, angle)
        (id, Size, size)
        (id, Damage, damage)
    rule getPickups(Fact):
      what:
        (id, Pickup, kind)
        (id, X, x)
        (id, Y, y)
        (id, Value, value)
        (id, Magnetized, magnetized)

    # ---- per-tick rules (trigger: DeltaTime)
    rule tickGameTime(Fact):
      what:
        (Global, DeltaTime, dt)
        (Global, GameTime, t, then = false)
      then:
        session.insert(Global, GameTime, t + dt * clockScale)

    rule movePlayer(Fact):
      what:
        (Global, DeltaTime, dt)
        (Global, PressedKeys, keys, then = false)
        (Player, X, x, then = false)
        (Player, Y, y, then = false)
        (Player, Speed, speed, then = false)
        (Player, PlayerStats, st, then = false)
        (Player, Facing, facing, then = false)
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
          session.insert(Player, X, x + dx * v)
          session.insert(Player, Y, y + dy * v)
          session.insert(Player, Facing, faceOf(dx, dy, facing))
        session.insert(Player, Moving, moving)

    rule regenPlayer(Fact):
      what:
        (Global, DeltaTime, dt)
        (Player, Hp, hp, then = false)
        (Player, MaxHp, maxHp, then = false)
        (Player, PlayerStats, st, then = false)
      cond:
        st.regen > 0
        hp < maxHp
      then:
        session.insert(Player, Hp, min(maxHp, hp + st.regen * dt))

    rule tickWeapons(Fact):
      what:
        (Global, DeltaTime, dt)
        (Global, HasNearest, hasNearest, then = false)
        (Global, NearestX, nx, then = false)
        (Global, NearestY, ny, then = false)
        (Player, X, px, then = false)
        (Player, Y, py, then = false)
        (Player, Facing, facing, then = false)
        (Player, PlayerStats, st, then = false)
        (id, Weapon, kind, then = false)
        (id, WeaponLevel, level, then = false)
        (id, Cooldown, cd, then = false)
      then:
        let cd2 = cd - dt
        if cd2 > 0:
          session.insert(id, Cooldown, cd2)
        else:
          for spec in attackPlan(kind, level, st, px, py, facing, hasNearest, nx, ny):
            let pid = allocId()
            session.insert(pid, Proj, spec.kind)
            session.insert(pid, X, spec.x)
            session.insert(pid, Y, spec.y)
            session.insert(pid, VX, spec.vx)
            session.insert(pid, VY, spec.vy)
            session.insert(pid, Ttl, spec.ttl)
            session.insert(pid, Pierce, spec.pierce)
            session.insert(pid, HitIds, initHashSet[int]())
            session.insert(pid, Angle, spec.angle)
            session.insert(pid, Size, spec.size)
            session.insert(pid, Damage, spec.damage)
          session.insert(id, Cooldown, weaponAt(kind, level).cooldown * st.cooldownMul)

    rule moveProjectiles(Fact):
      what:
        (Global, DeltaTime, dt)
        (Global, WorldWidth, ww, then = false)
        (Global, WorldHeight, wh, then = false)
        (Player, X, px, then = false)
        (Player, Y, py, then = false)
        (id, Proj, kind, then = false)
        (id, X, x, then = false)
        (id, Y, y, then = false)
        (id, VX, vx, then = false)
        (id, VY, vy, then = false)
        (id, Ttl, ttl, then = false)
        (id, Angle, angle, then = false)
      then:
        session.insert(id, Ttl, ttl - dt)
        case kind
        of Whip:
          discard # stays where it was spawned
        of Garlic:
          session.insert(id, X, px)
          session.insert(id, Y, py)
        of KingBible:
          # vx = angular speed, vy = orbit radius (see systems.attackPlan)
          let a = angle + vx * dt
          session.insert(id, Angle, a)
          session.insert(id, X, px + cos(a) * vy)
          session.insert(id, Y, py + sin(a) * vy)
        of Axe:
          let vy2 = vy + axeGravity * dt
          session.insert(id, VY, vy2)
          session.insert(id, X, x + vx * dt)
          session.insert(id, Y, y + vy2 * dt)
          session.insert(id, Angle, angle + 10 * dt)
        of Runetracer:
          var nx = x + vx * dt
          var ny = y + vy * dt
          var nvx = vx
          var nvy = vy
          let left = px - ww / 2
          let right = px + ww / 2
          let top = py - wh / 2
          let bottom = py + wh / 2
          if nx < left:
            nx = left
            nvx = abs(vx)
          elif nx > right:
            nx = right
            nvx = -abs(vx)
          if ny < top:
            ny = top
            nvy = abs(vy)
          elif ny > bottom:
            ny = bottom
            nvy = -abs(vy)
          session.insert(id, X, nx)
          session.insert(id, Y, ny)
          session.insert(id, VX, nvx)
          session.insert(id, VY, nvy)
        of MagicWand, Knife:
          session.insert(id, X, x + vx * dt)
          session.insert(id, Y, y + vy * dt)

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

# ---------------------------------------------------------------- entity helpers

proc addWeapon*(session: var Session[Fact, FactMatch], kind: WeaponKind, level = 1) =
  let id = allocId()
  session.insert(id, Weapon, kind)
  session.insert(id, WeaponLevel, level)
  session.insert(id, Cooldown, 0.2)

proc addPassive*(session: var Session[Fact, FactMatch], kind: PassiveKind, level = 1) =
  let id = allocId()
  session.insert(id, Passive, kind)
  session.insert(id, PassiveLevel, level)

proc insertProjectile*(session: var Session[Fact, FactMatch], spec: ProjSpec): int =
  result = allocId()
  session.insert(result, Proj, spec.kind)
  session.insert(result, X, spec.x)
  session.insert(result, Y, spec.y)
  session.insert(result, VX, spec.vx)
  session.insert(result, VY, spec.vy)
  session.insert(result, Ttl, spec.ttl)
  session.insert(result, Pierce, spec.pierce)
  session.insert(result, HitIds, initHashSet[int]())
  session.insert(result, Angle, spec.angle)
  session.insert(result, Size, spec.size)
  session.insert(result, Damage, spec.damage)

proc retractProjectile*(session: var Session[Fact, FactMatch], id: int) =
  for a in [Proj, X, Y, VX, VY, Ttl, Pierce, HitIds, Angle, Size, Damage]:
    session.retract(id, a)

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
  session.insert(Player, X, 0.0)
  session.insert(Player, Y, 0.0)
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
  session.addWeapon(c.weapon)
  session.insert(Global, GameTime, 0.0)
  session.insert(Global, SpawnTimer, 0.0)
  session.insert(Global, EnemyCount, 0)
  session.insert(Global, BossesSpawned, initHashSet[int]())
  session.insert(Global, HasNearest, false)
  session.insert(Global, PendingLevelUps, 0)
  session.insert(Global, ResultText, "")
  session.insert(Global, Phase, Running)
