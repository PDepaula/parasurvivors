import unittest, sets, math, random
import data, systems

type
  E = tuple[id: int, kind: EnemyKind, pos: Vec2, hp, damage, size: float]
  P = tuple[id: int, kind: WeaponKind, pos: Vec2, size, damage: float, pierce: int, hitIds: HashSet[int], ttl, angle: float]
  K = tuple[id: int, kind: PickupKind, pos: Vec2, magnetized: bool]

proc enemy(id: int, x, y: float, kind = Bat): E =
  (id, kind, (x, y), enemyDefs[kind].hp, enemyDefs[kind].damage, enemyDefs[kind].size)

proc proj(id: int, x, y: float, kind = ArcaneStaff, pierce = 0, size = 10.0, angle = 0.0): P =
  (id, kind, (x, y), size, 10.0, pierce, initHashSet[int](), 1.0, angle)

suite "systems":
  test "collide hits overlapping enemy only":
    let hits = collide([proj(1, 0, 0)], [enemy(10, 5, 5), enemy(11, 500, 500)])
    check hits.len == 1
    check hits[0].enemyId == 10
    check hits[0].projId == 1
    check hits[0].damage == 10.0

  test "pierce limits hits per tick and hitIds are respected":
    let es = [enemy(10, 0, 0), enemy(11, 4, 0), enemy(12, -4, 0)]
    check collide([proj(1, 0, 0, pierce = 0)], es).len == 1
    check collide([proj(1, 0, 0, pierce = 1)], es).len == 2
    var p = proj(1, 0, 0, pierce = 1)
    p.hitIds.incl 10
    let hits = collide([p], es)
    check hits.len == 1
    check hits[0].enemyId != 10

  test "lunge hits a rotated box along its direction":
    # spear pointing right, centred at (50,0), length 100, half-width lungeHalfWidth
    let right = proj(1, 50, 0, kind = DragonSpear, pierce = 999, size = 100, angle = 0.0)
    var hits = collide([right], [enemy(10, 90, 0), enemy(11, 50, 60), enemy(12, -20, 0)])
    check hits.len == 1
    check hits[0].enemyId == 10
    # same spear pointing up, centred at (0,-50)
    let up = proj(2, 0, -50, kind = DragonSpear, pierce = 999, size = 100, angle = -PI / 2)
    hits = collide([up], [enemy(10, 0, -90), enemy(11, 60, -50), enemy(12, 0, 20)])
    check hits.len == 1
    check hits[0].enemyId == 10

  test "lunge volleys: facing, opposite, then perpendiculars":
    check lungeDir(Right, 0) == (1.0, 0.0)
    check lungeDir(Right, 1) == (-1.0, 0.0)
    check lungeDir(Up, 0) == (0.0, -1.0)
    check lungeDir(Up, 1) == (0.0, 1.0)
    let (px, py) = lungeDir(Up, 2)
    check abs(px) == 1.0 and py == 0.0
    let (qx, qy) = lungeDir(Up, 3)
    check qx == -px and qy == 0.0

  test "expired projectiles never hit":
    var p = proj(1, 0, 0)
    p.ttl = 0
    check collide([p], [enemy(10, 0, 0)]).len == 0

  test "contact damage respects armor with a floor of 1":
    let es = [enemy(10, 0, 0, Zombie)] # damage 4
    check abs(contactDamage(es, 0, 0, 0.0, 1.0) - 4.0) < 1e-9
    check abs(contactDamage(es, 0, 0, 3.0, 1.0) - 1.0) < 1e-9
    check abs(contactDamage(es, 0, 0, 10.0, 1.0) - 1.0) < 1e-9
    check contactDamage(es, 500, 500, 0.0, 1.0) == 0.0

  test "pickups: collect within radius, magnetize gems within magnet":
    let ks: seq[K] = @[(1, GemBlue, (5.0, 0.0), false), (2, GemBlue, (40.0, 0.0), false), (3, Chicken, (40.0, 0.0), false), (4, GemRed, (900.0, 0.0), false)]
    let r = scanPickups(ks, 0, 0, 60.0)
    check r.collected == @[0]
    check r.magnetize == @[1]

  test "nearest enemy":
    let n = nearestEnemy([enemy(10, 100, 0), enemy(11, 30, 40)], 0, 0)
    check n.found
    check n.x == 30.0
    check nearestEnemy(newSeq[E](), 0, 0).found == false

  test "offscreen points are outside the view":
    randomize(1)
    for i in 0 ..< 200:
      let (x, y) = offscreenPoint(0, 0, 1000, 600)
      check abs(x) >= 500 or abs(y) >= 300
      check tooFar(x, y, 0, 0, 1000, 600) == false

  test "attack plans":
    let st = defaultStats
    let spear = attackPlan(DragonSpear, 1, st, 0, 0, Up, false, 0, 0)
    check spear.len == 1
    check spear[0].y < 0                       # in front of an Up-facing player
    check abs(spear[0].angle + PI / 2) < 1e-9
    check not spear[0].held
    let held = attackPlan(DragonSpear, 2, st, 0, 0, Up, false, 0, 0, starter = true)
    check held.len == 2
    check held[0].held and not held[1].held
    check held[1].y > 0                        # volley 1 goes the other way
    let notLunge = attackPlan(Longbow, 1, st, 0, 0, Up, false, 0, 0, starter = true)
    check not notLunge[0].held                 # only lunges can be "held"
    let wand = attackPlan(ArcaneStaff, 1, st, 0, 0, Down, true, 100, 0)
    check wand.len == 1
    check wand[0].vx > 0 and abs(wand[0].vy) < 1e-6
    let arrow = attackPlan(Longbow, 1, st, 0, 0, Up, false, 0, 0)
    check arrow[0].vy < 0
    let shield = attackPlan(RoundShield, 2, st, 0, 0, Up, false, 0, 0)
    check shield.len == 2
    check abs(shield[1].angle - PI) < 1e-9
    let boom = attackPlan(Boomerang, 1, st, 0, 0, Up, false, 0, 0)
    check abs(sqrt(boom[0].vx * boom[0].vx + boom[0].vy * boom[0].vy) - weaponDefs[Boomerang].speed) < 1e-6
    var strong = defaultStats
    strong.might = 2.0
    strong.amount = 1
    let plan = attackPlan(Longbow, 1, strong, 0, 0, Right, false, 0, 0)
    check plan.len == 2
    check plan[0].damage == 13.0

  test "choices respect slots and max levels":
    randomize(2)
    let c1 = generateChoices([(DragonSpear, 1)], [])
    check c1.len == 3
    let maxed = generateChoices([(DragonSpear, maxWeaponLevel), (Longbow, maxWeaponLevel), (WarAxe, maxWeaponLevel), (Garlic, maxWeaponLevel), (ArcaneStaff, maxWeaponLevel), (Boomerang, maxWeaponLevel)],
                                [(Spinach, maxPassiveLevel), (Armor, maxPassiveLevel), (HollowHeart, maxPassiveLevel), (Pummarola, maxPassiveLevel), (EmptyTome, maxPassiveLevel), (Wings, maxPassiveLevel)])
    check maxed.len == 2
    check maxed[0].kind == BonusGold
    for i in 0 ..< 50:
      for c in generateChoices([(DragonSpear, 3)], [(Spinach, 1)]):
        if c.kind == UpgradeWeapon: check c.level == 4
        if c.kind == UpgradePassive: check c.level == 2
        check c.title.len > 0

  test "separate pushes overlapping enemies apart":
    let moves = separate([enemy(10, 0, 0, Zombie), enemy(11, 5, 0, Zombie), enemy(12, 400, 0, Zombie)])
    check moves.len == 2
    for (id, dx, dy) in moves:
      if id == 10: check dx < 0
      if id == 11: check dx > 0

  test "the biggest enemy is hit anywhere inside the overlap radius":
    # a Reaper's radius is far larger than the old hardcoded 40 px scan pad
    let r = enemyRadius(enemyDefs[Reaper].size)
    for kind in [ArcaneStaff, Longbow, WarAxe, Boomerang, RoundShield, Garlic]:
      let size = weaponDefs[kind].size
      var offsets: seq[float]
      var d = size + 41.0
      while d < size + r:
        offsets.add d
        d += 4.0
      for dx in offsets:
        let hits = collide([proj(1, 0, 0, kind = kind, pierce = 999, size = size)],
                           [enemy(10, dx, 0, Reaper)])
        check hits.len == 1
