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
    check ws[0].kind == DragonSpear
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
    check abs(p.pos.x - playerBaseSpeed * 0.5) < 1e-6
    check p.facing == Right
    check p.moving
    s.insert(Global, PressedKeys, toHashSet([KeyUp]))
    s.step(0.5)
    p = s.query(gameRules.getPlayer)
    check p.pos.y < 0
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
    check abs(sqrt(p.pos.x * p.pos.x + p.pos.y * p.pos.y) - playerBaseSpeed) < 1e-6

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
    s.startRun(Gino) # Longbow, +1 amount
    check s.queryAll(gameRules.getProjectiles).len == 0
    s.step(0.25) # initial cooldown is 0.2
    let ps = s.queryAll(gameRules.getProjectiles)
    check ps.len == 2
    check ps[0].kind == Longbow
    let w = s.queryAll(gameRules.getWeapons)[0]
    check abs(w.cooldown - weaponDefs[Longbow].cooldown) < 1e-6

  test "projectiles move and age":
    var s = newSession()
    s.startRun(Gino)
    s.insert(Player, Facing, Right)
    s.step(0.25)
    let before = s.queryAll(gameRules.getProjectiles)[0]
    s.step(0.1)
    let after = s.query(gameRules.getProjectiles, id = before.id)
    check after.pos.x > before.pos.x
    check abs(after.ttl - (before.ttl - 0.1)) < 1e-9

  test "round shield orbits the player":
    var s = newSession()
    s.startRun(Otto)
    s.addWeapon(RoundShield)
    s.step(0.25)
    let shields = s.queryAll(gameRules.getProjectiles).filterIt(it.kind == RoundShield)
    check shields.len == 1
    s.insert(Player, Pos, (500.0, 0.0))
    s.step(0.1)
    let b = s.query(gameRules.getProjectiles, id = shields[0].id)
    check abs(dist(b.pos.x, b.pos.y, 500.0, 0.0) - orbitRadius) < 1e-6

  test "boomerang turns around, forgets its hits and is caught":
    var s = newSession()
    s.startRun(Otto)
    s.addWeapon(Boomerang)
    s.step(0.25)
    let b = s.queryAll(gameRules.getProjectiles).filterIt(it.kind == Boomerang)[0]
    s.insert(b.id, Pos, (10.0, 0.0))   # already 10 px out (at the player the pull is zero)
    s.insert(b.id, VX, 100.0)
    s.insert(b.id, VY, 0.0)
    s.insert(b.id, HitIds, toHashSet([42]))
    s.step(0.1)
    var p = s.query(gameRules.getProjectiles, id = b.id)
    check p.pos.x > 10.0
    check p.vx < 100.0                 # pulled back toward the player
    check p.hitIds.contains(42)        # still outbound: hits kept
    s.insert(b.id, VX, -100.0)         # now heading home
    s.step(0.1)
    p = s.query(gameRules.getProjectiles, id = b.id)
    check p.hitIds.len == 0            # turned: can hit the same enemies again
    s.insert(b.id, Pos, (5.0, 0.0))
    s.step(0.1)
    check s.query(gameRules.getProjectiles, id = b.id).ttl <= 0   # caught → expires

  test "the starter weapon plays the body animation and holds its first lunge":
    var s = newSession()
    s.startRun(Otto)                 # Dragon Spear → AnimThrust
    s.addWeapon(ArcaneStaff)
    var p = s.query(gameRules.getPlayer)
    check p.anim == NoAnim
    s.step(0.25)
    p = s.query(gameRules.getPlayer)
    check p.anim == AnimThrust
    check abs(p.animStart - 0.25) < 1e-9
    let projs = s.queryAll(gameRules.getProjectiles)
    check projs.filterIt(it.kind == DragonSpear and it.held).len == 1
    check projs.filterIt(it.kind == ArcaneStaff and it.held).len == 0
    check animActive(p.anim, p.animStart, 0.5)
    check not animActive(p.anim, p.animStart, 0.25 + animDefs[AnimThrust].secs)

  test "a non-starter weapon never animates the body":
    var s = newSession()
    s.startRun(Imma)                 # Arcane Staff → AnimCast
    s.addWeapon(DragonSpear)
    s.step(0.25)
    let p = s.query(gameRules.getPlayer)
    check p.anim == AnimCast
    check s.queryAll(gameRules.getProjectiles).filterIt(it.kind == DragonSpear and it.held).len == 0

  test "war axe keeps its angle fact still; render spins it":
    var s = newSession()
    s.startRun(Lina)
    s.step(0.25)
    let a = s.queryAll(gameRules.getProjectiles)[0]
    s.step(0.1)
    check s.query(gameRules.getProjectiles, id = a.id).angle == a.angle

  test "insert/retract projectile round trip":
    var s = newSession()
    s.startRun(Otto)
    let id = s.insertProjectile(ProjSpec(kind: WarAxe, x: 1, y: 2, vx: 3, vy: 4, size: 5, damage: 6, ttl: 7, angle: 0, pierce: 8))
    check s.queryAll(gameRules.getProjectiles).len == 1
    s.retractProjectile(id)
    check s.queryAll(gameRules.getProjectiles).len == 0
    check not s.contains(id, Held)

suite "rules: enemies, waves, pickups":
  test "enemies walk toward the player":
    var s = newSession()
    s.startRun(Otto)
    let id = s.spawnEnemy(Zombie, 100.0, 0.0, 0)
    s.step(0.5)
    let e = s.query(gameRules.getEnemies, id = id)
    check e.pos.x < 100.0
    check abs(e.pos.x - (100.0 - enemyDefs[Zombie].speed * 0.5)) < 1e-6
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
      check abs(e.pos.x) >= 1024.0 / 2 or abs(e.pos.y) >= 768.0 / 2

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
    check s.query(gameRules.getPickups, id = id).pos.x == 200.0
    s.insert(id, Magnetized, true)
    s.step(0.1)
    check s.query(gameRules.getPickups, id = id).pos.x < 200.0

  test "retract helpers remove every attribute":
    var s = newSession()
    s.startRun(Otto)
    let e = s.spawnEnemy(Bat, 0, 0, 0)
    let p = s.spawnPickup(Coin, 0, 0, 10)
    s.retractEnemy(e)
    s.retractPickup(p)
    check s.queryAll(gameRules.getEnemies).len == 0
    check s.queryAll(gameRules.getPickups).len == 0
    check not s.contains(e, Pos)
    check not s.contains(p, Pos)

proc runTick(s: var Session[Fact, FactMatch], dt: float): StepEvents =
  s.insert(Global, DeltaTime, dt)
  s.insert(Global, TotalTime, dt)
  s.fireRules()
  result = s.stepSystems(dt)
  s.fireRules()

suite "rules: systems step, level up, death":
  test "projectile kills enemy, drops a gem, counts the kill":
    var s = newSession()
    s.startRun(Otto)
    let e = s.spawnEnemy(Bat, 50.0, 0.0, 0)
    discard s.insertProjectile(ProjSpec(kind: ArcaneStaff, x: 50, y: 0, size: 10, damage: 5, ttl: 1, pierce: 0))
    let ev = s.runTick(0.001)
    check ev.hits == 1
    check ev.kills == 1
    check not s.contains(e, Pos)
    check s.queryAll(gameRules.getProjectiles).len == 0 # pierce 0 → consumed
    let gems = s.queryAll(gameRules.getPickups)
    check gems.len >= 1
    check gems.anyIt(it.kind == GemBlue)
    check s.query(gameRules.getPlayer).kills == 1

  test "surviving enemy takes damage and flashes; piercing projectile survives":
    var s = newSession()
    s.startRun(Otto)
    let e = s.spawnEnemy(Koalio, 0.0, 0.0, 0)
    let p = s.insertProjectile(ProjSpec(kind: Longbow, x: 0, y: 0, size: 10, damage: 5, ttl: 1, pierce: 3))
    discard s.runTick(0.001)
    let en = s.query(gameRules.getEnemies, id = e)
    check abs(en.hp - (enemyDefs[Koalio].hp - 5)) < 1e-6
    check en.hitFlash > 0
    let pr = s.query(gameRules.getProjectiles, id = p)
    check pr.hitIds.contains(e)
    discard s.runTick(0.001)
    check abs(s.query(gameRules.getEnemies, id = e).hp - (enemyDefs[Koalio].hp - 5)) < 1e-6 # hit only once

  test "boss drops a chest which upgrades a weapon":
    var s = newSession()
    s.startRun(Otto)
    let e = s.spawnEnemy(Koalio, 0.0, 0.0, 0)
    s.insert(e, Hp, 1.0)
    discard s.insertProjectile(ProjSpec(kind: Longbow, x: 0, y: 0, size: 10, damage: 5, ttl: 1, pierce: 3))
    let ev = s.runTick(0.001)
    check ev.bossKilled
    check s.queryAll(gameRules.getPickups).anyIt(it.kind == Chest)
    let ev2 = s.runTick(0.001) # chest sits on the player → collected
    check ev2.chest
    check s.queryAll(gameRules.getWeapons)[0].level == 2

  test "touching enemies hurts the player":
    var s = newSession()
    s.startRun(Otto)
    discard s.spawnEnemy(Zombie, 5.0, 0.0, 0)
    let ev = s.runTick(0.5)
    check ev.hurt
    check s.query(gameRules.getPlayer).hp < 120.0

  test "gems give xp and trigger a pending level up":
    var s = newSession()
    s.startRun(Otto)
    discard s.spawnPickup(GemRed, 0.0, 0.0, 5)
    let ev = s.runTick(0.001)
    check ev.gems == 1
    let p = s.query(gameRules.getPlayer)
    check p.level == 2
    check p.xp == 0
    check p.xpToNext == xpForLevel(2)
    let m = s.query(gameRules.getMenu)
    check m.pending == 1

  test "prepareChoices and applyChoice":
    var s = newSession()
    s.startRun(Otto)
    s.prepareChoices()
    let m = s.query(gameRules.getMenu)
    check m.choices != nil
    check m.choices[].len == 3
    s.applyChoice(Choice(kind: NewPassive, passive: Spinach, level: 1))
    check s.queryAll(gameRules.getPassives).len == 1
    check abs(s.query(gameRules.getStats).stats.might - 1.2) < 1e-9
    s.applyChoice(Choice(kind: UpgradeWeapon, weapon: DragonSpear, level: 2))
    check s.queryAll(gameRules.getWeapons)[0].level == 2
    s.applyChoice(Choice(kind: NewPassive, passive: HollowHeart, level: 1))
    check s.query(gameRules.getPlayer).maxHp == 144.0

  test "player death ends the run with a result":
    var s = newSession()
    s.startRun(Otto)
    s.insert(Player, Hp, 0.0)
    s.fireRules()
    let (phase) = s.query(gameRules.getPhase)
    check phase == GameOver
    check s.query(gameRules.getMenu).resultText.len > 0

  test "far enemies despawn and the count is refreshed":
    var s = newSession()
    s.startRun(Otto)
    discard s.spawnEnemy(Bat, 5000.0, 0.0, 0)
    discard s.runTick(0.001)
    check s.queryAll(gameRules.getEnemies).allIt(it.pos.x < 5000.0)
