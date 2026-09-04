import times, random, sets, strutils

import pararules
import data, systems, rules

proc bench(n: int, ticks: int): (float, float, float) =
  var s = newSession()
  s.startRun(Otto)
  s.addWeapon(MagicWand); s.addWeapon(Knife)
  randomize(1)
  for i in 0 ..< n:
    discard s.spawnEnemy(Zombie, rand(1200.0) - 600, rand(800.0) - 400, 10)
  var tRules, tSys, tRules2: float
  for t in 0 ..< ticks:
    s.insert(Global, PressedKeys, toHashSet([KeyD]))
    let a = epochTime()
    s.insert(Global, DeltaTime, 0.016)
    s.insert(Global, TotalTime, float(t) * 0.016)
    s.fireRules()
    let b = epochTime()
    discard s.stepSystems(0.016)
    let c = epochTime()
    s.fireRules()
    let d = epochTime()
    tRules += b - a; tSys += c - b; tRules2 += d - c
  (tRules / float(ticks) * 1000, tSys / float(ticks) * 1000, tRules2 / float(ticks) * 1000)

for n in [50, 100, 200, 300]:
  let (r, sy, r2) = bench(n, 60)
  echo n, " enemies: rules=", r.formatFloat(ffDecimal, 2), "ms systems=", sy.formatFloat(ffDecimal, 2), "ms rules2=", r2.formatFloat(ffDecimal, 2), "ms"
