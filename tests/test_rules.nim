import unittest, sets, math
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
