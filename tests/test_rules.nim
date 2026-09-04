import unittest, sets, math, sequtils
import pararules
import data, systems, rules

proc step(s: var Session[Fact, FactMatch], dt: float) =
  s.insert(Global, DeltaTime, dt)
  s.insert(Global, TotalTime, dt)
  s.fireRules()

suite "rules: session and player":
  test "fresh session starts on the title screen":
    var s = newSession()
    let (phase) = s.query(gameRules.getPhase)
    check phase == Title

  test "startRun creates the player with the character's weapon":
    var s = newSession()
    s.startRun(Otto)
    let p = s.query(gameRules.getPlayer)
    check p.hero == Otto
    check p.hp == 120.0
    check p.level == 1
    check p.xpToNext == 5
    let ws = s.queryAll(gameRules.getWeapons)
    check ws.len == 1
    check ws[0].kind == Whip
    check ws[0].level == 1
    let (phase) = s.query(gameRules.getPhase)
    check phase == Running

  test "game time advances only with DeltaTime":
    var s = newSession()
    s.startRun(Otto)
    s.step(0.5)
    s.step(0.25)
    let (tt, gt) = s.query(gameRules.getTime)
    check abs(gt - 0.75 * clockScale) < 1e-9

  test "player moves with WASD and arrows and faces the direction":
    var s = newSession()
    s.startRun(Otto)
    s.insert(Global, PressedKeys, toHashSet([KeyD]))
    s.step(0.5)
    var p = s.query(gameRules.getPlayer)
    check abs(p.x - playerBaseSpeed * 0.5) < 1e-6
    check p.facing == Right
    check p.moving
    s.insert(Global, PressedKeys, toHashSet([KeyUp]))
    s.step(0.5)
    p = s.query(gameRules.getPlayer)
    check p.y < 0
    check p.facing == Up
    s.insert(Global, PressedKeys, initHashSet[int]())
    s.step(0.5)
    p = s.query(gameRules.getPlayer)
    check not p.moving

  test "diagonal movement is normalised":
    var s = newSession()
    s.startRun(Otto)
    s.insert(Global, PressedKeys, toHashSet([KeyD, KeyS]))
    s.step(1.0)
    let p = s.query(gameRules.getPlayer)
    check abs(sqrt(p.x * p.x + p.y * p.y) - playerBaseSpeed) < 1e-6

  test "regen heals up to max hp":
    var s = newSession()
    s.startRun(Otto)
    s.insert(Player, Hp, 50.0)
    var st = defaultStats
    st.regen = 10.0
    s.insert(Player, PlayerStats, st)
    s.step(1.0)
    check abs(s.query(gameRules.getPlayer).hp - 60.0) < 1e-6
    s.insert(Player, Hp, 119.5)
    s.step(1.0)
    check s.query(gameRules.getPlayer).hp == 120.0

  test "resetSession keeps the window size":
    var s = newSession()
    s.insert(Global, WindowWidth, 640)
    s.insert(Global, WindowHeight, 480)
    s.insert(Global, WorldWidth, 640.0)
    s.insert(Global, WorldHeight, 480.0)
    s.startRun(Gino)
    s = s.resetSession()
    let (ww, wh) = s.query(gameRules.getWorld)
    check ww == 640.0
    let (phase) = s.query(gameRules.getPhase)
    check phase == Title
    check s.queryAll(gameRules.getWeapons).len == 0

suite "rules: weapons and projectiles":
  test "weapon fires when its cooldown expires and resets it":
    var s = newSession()
    s.startRun(Gino) # Knife, +1 amount
    check s.queryAll(gameRules.getProjectiles).len == 0
    s.step(0.25) # initial cooldown is 0.2
    let ps = s.queryAll(gameRules.getProjectiles)
    check ps.len == 2
    check ps[0].kind == Knife
    let w = s.queryAll(gameRules.getWeapons)[0]
    check abs(w.cooldown - weaponDefs[Knife].cooldown) < 1e-6

  test "projectiles move and age":
    var s = newSession()
    s.startRun(Gino)
    s.insert(Player, Facing, Right)
    s.step(0.25)
    let before = s.queryAll(gameRules.getProjectiles)[0]
    s.step(0.1)
    let after = s.query(gameRules.getProjectiles, id = before.id)
    check after.x > before.x
    check abs(after.ttl - (before.ttl - 0.1)) < 1e-9

  test "king bible orbits the player":
    var s = newSession()
    s.startRun(Otto)
    s.addWeapon(KingBible)
    s.step(0.25)
    let bibles = s.queryAll(gameRules.getProjectiles).filterIt(it.kind == KingBible)
    check bibles.len == 1
    s.insert(Player, X, 500.0)
    s.step(0.1)
    let b = s.query(gameRules.getProjectiles, id = bibles[0].id)
    check abs(dist(b.x, b.y, 500.0, 0.0) - bibleOrbitRadius) < 1e-6

  test "runetracer bounces inside the view":
    var s = newSession()
    s.startRun(Lina)
    s.step(0.25)
    let r = s.queryAll(gameRules.getProjectiles)[0]
    s.insert(r.id, X, 0.0)
    s.insert(r.id, Y, 0.0)
    s.insert(r.id, VX, -1000.0)
    s.insert(r.id, VY, 0.0)
    s.step(1.0)
    let after = s.query(gameRules.getProjectiles, id = r.id)
    check after.vx > 0
    check after.x >= -1024.0 / 2 / zoom

  test "insert/retract projectile round trip":
    var s = newSession()
    s.startRun(Otto)
    let id = s.insertProjectile(ProjSpec(kind: Axe, x: 1, y: 2, vx: 3, vy: 4, size: 5, damage: 6, ttl: 7, angle: 0, pierce: 8))
    check s.queryAll(gameRules.getProjectiles).len == 1
    s.retractProjectile(id)
    check s.queryAll(gameRules.getProjectiles).len == 0

suite "rules: enemies, waves, pickups":
  test "enemies walk toward the player":
    var s = newSession()
    s.startRun(Otto)
    let id = s.spawnEnemy(Zombie, 100.0, 0.0, 0)
    s.step(0.5)
    let e = s.query(gameRules.getEnemies, id = id)
    check e.x < 100.0
    check abs(e.x - (100.0 - enemyDefs[Zombie].speed * 0.5)) < 1e-6
    check e.hp == enemyDefs[Zombie].hp

  test "enemy hp scales with the minute":
    var s = newSession()
    s.startRun(Otto)
    let id = s.spawnEnemy(Zombie, 100.0, 0.0, 10)
    check abs(s.query(gameRules.getEnemies, id = id).hp - enemyDefs[Zombie].hp * hpScale(10)) < 1e-9
    let boss = s.spawnEnemy(Koalio, 100.0, 0.0, 10)
    check s.query(gameRules.getEnemies, id = boss).hp == enemyDefs[Koalio].hp

  test "hit flash decays":
    var s = newSession()
    s.startRun(Otto)
    let id = s.spawnEnemy(Bat, 100.0, 0.0, 0)
    s.insert(id, HitFlash, 0.1)
    s.step(0.05)
    check abs(s.query(gameRules.getEnemies, id = id).hitFlash - 0.05) < 1e-9
    s.step(0.5)
    check s.query(gameRules.getEnemies, id = id).hitFlash == 0.0

  test "waves keep the minimum count and spawn offscreen":
    var s = newSession()
    s.startRun(Otto)
    for i in 0 ..< 3:
      s.step(0.016)
    let es = s.queryAll(gameRules.getEnemies)
    check es.len >= waveFor(0).minCount
    for e in es:
      check e.kind == Bat
      check abs(e.x) >= 1024.0 / 2 or abs(e.y) >= 768.0 / 2

  test "bosses spawn once at their minute":
    var s = newSession()
    s.startRun(Otto)
    s.insert(Global, GameTime, 3 * 60.0 - 0.1)
    s.step(0.2 / clockScale)
    check s.queryAll(gameRules.getEnemies).filterIt(it.kind == Parakeet).len == 1
    s.step(0.2 / clockScale)
    check s.queryAll(gameRules.getEnemies).filterIt(it.kind == Parakeet).len == 1

  test "magnetized gems fly to the player":
    var s = newSession()
    s.startRun(Otto)
    let id = s.spawnPickup(GemBlue, 200.0, 0.0, 1)
    s.step(0.1)
    check s.query(gameRules.getPickups, id = id).x == 200.0
    s.insert(id, Magnetized, true)
    s.step(0.1)
    check s.query(gameRules.getPickups, id = id).x < 200.0

  test "retract helpers remove every attribute":
    var s = newSession()
    s.startRun(Otto)
    let e = s.spawnEnemy(Bat, 0, 0, 0)
    let p = s.spawnPickup(Coin, 0, 0, 10)
    s.retractEnemy(e)
    s.retractPickup(p)
    check s.queryAll(gameRules.getEnemies).len == 0
    check s.queryAll(gameRules.getPickups).len == 0
    check not s.contains(e, X)
    check not s.contains(p, X)
