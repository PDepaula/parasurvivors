## Pure data: enums, definition tables, curves, constants. No engine imports.

import strutils

type
  CharacterKind* = enum
    Otto, Imma, Lina, Gino
  WeaponKind* = enum
    Whip, MagicWand, Knife, Axe, Runetracer, Garlic, KingBible
  PassiveKind* = enum
    Spinach, Armor, HollowHeart, Pummarola, EmptyTome, Wings, Attractorb
  EnemyKind* = enum
    Bat, Zombie, Skeleton, Mudman, Ghost, Parakeet, Koalio, Reaper
  PickupKind* = enum
    GemBlue, GemGreen, GemRed, Chicken, Coin, Chest, Vacuum
  Dir* = enum
    Up, Left, Down, Right ## LPC sheet row order

  Stats* = object
    might*, armor*, regen*, cooldownMul*, speedMul*, magnet*, area*, projSpeed*, duration*: float
    amount*: int

  CharacterDef* = object
    name*, perk*, sheet*: string
    weapon*: WeaponKind
    maxHp*: float
    base*: Stats

  WeaponDef* = object
    name*, desc*: string
    cooldown*, damage*, speed*, ttl*, size*: float
    amount*, pierce*: int

  WeaponUpgrade* = object ## additive deltas applied when reaching that level
    damage*, cooldown*, size*, speed*, ttl*: float
    amount*, pierce*: int
    text*: string

  PassiveDef* = object
    name*, desc*: string

  EnemyDef* = object
    hp*, speed*, damage*, size*: float
    gem*: PickupKind
    sheet*: string
    boss*: bool

  Wave* = object
    minute*: int
    kinds*: seq[EnemyKind]
    interval*: float
    minCount*: int

  BossSpawn* = object
    minute*: int
    kind*: EnemyKind
    count*: int

const
  maxWeaponLevel* = 8
  maxPassiveLevel* = 5
  maxWeaponSlots* = 6
  maxPassiveSlots* = 6
  maxEnemies* = 300
  maxPickups* = 400
  runLengthSecs* = 30 * 60
  zoom* = 1.0 ## world units per screen pixel
  playerBaseSpeed* = 160.0
  playerRadius* = 14.0
  pickupRadius* = 24.0
  baseMagnet* = 48.0
  gemFlySpeed* = 420.0
  axeGravity* = 900.0
  bibleOrbitRadius* = 90.0
  chickenHeal* = 30.0
  coinValue* = 10
  chestGoldFallback* = 50
  chickenChance* = 0.015
  coinChance* = 0.025
  vacuumChance* = 0.005
  hitFlashSecs* = 0.12
  despawnMargin* = 400.0
  spawnMargin* = 80.0
  clockScale* = when defined(fastclock): 10.0 else: 1.0

  # GLFW key codes (kept here so rules.nim stays free of glfw)
  KeyLeft* = 263
  KeyRight* = 262
  KeyDown* = 264
  KeyUp* = 265
  KeyEnter* = 257
  KeyEscape* = 256
  KeySpace* = 32
  KeyA* = 65
  KeyD* = 68
  KeyP* = 80
  KeyR* = 82
  KeyS* = 83
  KeyW* = 87
  Key1* = 49
  Key2* = 50
  Key3* = 51

  defaultStats* = Stats(might: 1.0, armor: 0.0, regen: 0.0, cooldownMul: 1.0, speedMul: 1.0,
                        magnet: 1.0, area: 1.0, projSpeed: 1.0, duration: 1.0, amount: 0)

  characterDefs*: array[CharacterKind, CharacterDef] = [
    Otto: CharacterDef(name: "Otto", perk: "+10% Might", sheet: "otto", weapon: Whip, maxHp: 120,
      base: Stats(might: 1.1, armor: 0, regen: 0, cooldownMul: 1.0, speedMul: 1.0, magnet: 1.0, area: 1.0, projSpeed: 1.0, duration: 1.0, amount: 0)),
    Imma: CharacterDef(name: "Imma", perk: "-10% Cooldown", sheet: "imma", weapon: MagicWand, maxHp: 100,
      base: Stats(might: 1.0, armor: 0, regen: 0, cooldownMul: 0.9, speedMul: 1.0, magnet: 1.0, area: 1.0, projSpeed: 1.0, duration: 1.0, amount: 0)),
    Lina: CharacterDef(name: "Lina", perk: "+20% Projectile speed", sheet: "lina", weapon: Runetracer, maxHp: 90,
      base: Stats(might: 1.0, armor: 0, regen: 0, cooldownMul: 1.0, speedMul: 1.0, magnet: 1.0, area: 1.0, projSpeed: 1.2, duration: 1.0, amount: 0)),
    Gino: CharacterDef(name: "Gino", perk: "+1 Projectile", sheet: "gino", weapon: Knife, maxHp: 100,
      base: Stats(might: 1.0, armor: 0, regen: 0, cooldownMul: 1.0, speedMul: 1.0, magnet: 1.0, area: 1.0, projSpeed: 1.0, duration: 1.0, amount: 1)),
  ]

  weaponDefs*: array[WeaponKind, WeaponDef] = [
    Whip: WeaponDef(name: "Whip", desc: "Attacks horizontally, passes through enemies",
      cooldown: 1.35, damage: 10, speed: 0, ttl: 0.15, size: 120, amount: 1, pierce: 999),
    MagicWand: WeaponDef(name: "Magic Wand", desc: "Fires at the nearest enemy",
      cooldown: 1.2, damage: 10, speed: 300, ttl: 2.5, size: 10, amount: 1, pierce: 0),
    Knife: WeaponDef(name: "Knife", desc: "Flies quickly in the faced direction",
      cooldown: 1.0, damage: 6.5, speed: 450, ttl: 1.5, size: 8, amount: 1, pierce: 1),
    Axe: WeaponDef(name: "Axe", desc: "High damage, arcs overhead",
      cooldown: 4.0, damage: 20, speed: 300, ttl: 2.5, size: 20, amount: 1, pierce: 3),
    Runetracer: WeaponDef(name: "Runetracer", desc: "Bounces around, passes through enemies",
      cooldown: 3.0, damage: 10, speed: 250, ttl: 4.0, size: 10, amount: 1, pierce: 999),
    Garlic: WeaponDef(name: "Garlic", desc: "Damages nearby enemies",
      cooldown: 1.3, damage: 5, speed: 0, ttl: 0.05, size: 80, amount: 1, pierce: 999),
    KingBible: WeaponDef(name: "King Bible", desc: "Orbits around the character",
      cooldown: 3.0, damage: 10, speed: 2.5, ttl: 3.0, size: 14, amount: 1, pierce: 999),
  ]

  weaponUpgrades*: array[WeaponKind, array[2 .. maxWeaponLevel, WeaponUpgrade]] = [
    Whip: [
      2: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      3: WeaponUpgrade(damage: 5, text: "Base damage up by 5"),
      4: WeaponUpgrade(damage: 5, size: 10, text: "Damage +5, area +10%"),
      5: WeaponUpgrade(damage: 5, text: "Base damage up by 5"),
      6: WeaponUpgrade(damage: 5, size: 10, text: "Damage +5, area +10%"),
      7: WeaponUpgrade(damage: 5, text: "Base damage up by 5"),
      8: WeaponUpgrade(damage: 5, text: "Base damage up by 5")],
    MagicWand: [
      2: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      3: WeaponUpgrade(cooldown: -0.2, text: "Cooldown reduced by 0.2s"),
      4: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      5: WeaponUpgrade(damage: 10, text: "Base damage up by 10"),
      6: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      7: WeaponUpgrade(pierce: 1, text: "Passes through 1 more enemy"),
      8: WeaponUpgrade(damage: 10, text: "Base damage up by 10")],
    Knife: [
      2: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      3: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      4: WeaponUpgrade(damage: 5, text: "Base damage up by 5"),
      5: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      6: WeaponUpgrade(pierce: 1, text: "Passes through 1 more enemy"),
      7: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      8: WeaponUpgrade(damage: 5, text: "Base damage up by 5")],
    Axe: [
      2: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      3: WeaponUpgrade(damage: 20, text: "Base damage up by 20"),
      4: WeaponUpgrade(pierce: 2, text: "Passes through 2 more enemies"),
      5: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      6: WeaponUpgrade(damage: 20, text: "Base damage up by 20"),
      7: WeaponUpgrade(pierce: 2, text: "Passes through 2 more enemies"),
      8: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile")],
    Runetracer: [
      2: WeaponUpgrade(speed: 50, damage: 5, text: "Speed +50, damage +5"),
      3: WeaponUpgrade(ttl: 0.3, text: "Lasts 0.3s longer"),
      4: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      5: WeaponUpgrade(speed: 50, damage: 5, text: "Speed +50, damage +5"),
      6: WeaponUpgrade(ttl: 0.3, text: "Lasts 0.3s longer"),
      7: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      8: WeaponUpgrade(damage: 5, ttl: 0.5, text: "Damage +5, lasts 0.5s longer")],
    Garlic: [
      2: WeaponUpgrade(size: 20, damage: 2, text: "Area +20, damage +2"),
      3: WeaponUpgrade(cooldown: -0.1, damage: 1, text: "Faster pulse, damage +1"),
      4: WeaponUpgrade(size: 20, damage: 1, text: "Area +20, damage +1"),
      5: WeaponUpgrade(cooldown: -0.1, damage: 2, text: "Faster pulse, damage +2"),
      6: WeaponUpgrade(size: 20, damage: 1, text: "Area +20, damage +1"),
      7: WeaponUpgrade(cooldown: -0.1, damage: 1, text: "Faster pulse, damage +1"),
      8: WeaponUpgrade(size: 20, damage: 1, text: "Area +20, damage +1")],
    KingBible: [
      2: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      3: WeaponUpgrade(speed: 0.3, size: 3, text: "Spins faster, bigger"),
      4: WeaponUpgrade(ttl: 0.5, text: "Lasts 0.5s longer"),
      5: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      6: WeaponUpgrade(speed: 0.3, size: 3, text: "Spins faster, bigger"),
      7: WeaponUpgrade(ttl: 0.5, text: "Lasts 0.5s longer"),
      8: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile")],
  ]

  passiveDefs*: array[PassiveKind, PassiveDef] = [
    Spinach: PassiveDef(name: "Spinach", desc: "+10% damage per level"),
    Armor: PassiveDef(name: "Armor", desc: "-1 incoming damage per level"),
    HollowHeart: PassiveDef(name: "Hollow Heart", desc: "+20% max health per level"),
    Pummarola: PassiveDef(name: "Pummarola", desc: "+0.2 HP/s regen per level"),
    EmptyTome: PassiveDef(name: "Empty Tome", desc: "-8% cooldown per level"),
    Wings: PassiveDef(name: "Wings", desc: "+10% move speed per level"),
    Attractorb: PassiveDef(name: "Attractorb", desc: "+50% pickup range per level"),
  ]

  enemyDefs*: array[EnemyKind, EnemyDef] = [
    Bat: EnemyDef(hp: 1, speed: 90, damage: 3, size: 32, gem: GemBlue, sheet: "bat", boss: false),
    Zombie: EnemyDef(hp: 3, speed: 55, damage: 4, size: 64, gem: GemBlue, sheet: "zombie", boss: false),
    Skeleton: EnemyDef(hp: 8, speed: 70, damage: 5, size: 64, gem: GemGreen, sheet: "skeleton", boss: false),
    Mudman: EnemyDef(hp: 15, speed: 45, damage: 6, size: 64, gem: GemGreen, sheet: "mudman", boss: false),
    Ghost: EnemyDef(hp: 20, speed: 80, damage: 6, size: 64, gem: GemGreen, sheet: "ghost", boss: false),
    Parakeet: EnemyDef(hp: 150, speed: 100, damage: 12, size: 150, gem: GemRed, sheet: "parakeet", boss: true),
    Koalio: EnemyDef(hp: 400, speed: 60, damage: 15, size: 104, gem: GemRed, sheet: "koalio", boss: true),
    Reaper: EnemyDef(hp: 65535, speed: 200, damage: 999, size: 192, gem: GemRed, sheet: "reaper", boss: true),
  ]

  waves*: seq[Wave] = @[
    Wave(minute: 0, kinds: @[Bat], interval: 1.0, minCount: 10),
    Wave(minute: 1, kinds: @[Bat, Zombie], interval: 0.8, minCount: 20),
    Wave(minute: 3, kinds: @[Skeleton, Bat], interval: 0.6, minCount: 30),
    Wave(minute: 5, kinds: @[Zombie, Mudman], interval: 0.5, minCount: 40),
    Wave(minute: 8, kinds: @[Bat, Skeleton], interval: 0.4, minCount: 60),
    Wave(minute: 12, kinds: @[Ghost, Mudman], interval: 0.35, minCount: 80),
    Wave(minute: 16, kinds: @[Skeleton, Ghost, Bat], interval: 0.3, minCount: 100),
    Wave(minute: 20, kinds: @[Zombie, Skeleton, Mudman, Ghost], interval: 0.25, minCount: 140),
    Wave(minute: 25, kinds: @[Mudman, Ghost, Skeleton, Bat], interval: 0.2, minCount: 200),
    Wave(minute: 30, kinds: @[Ghost, Bat], interval: 0.2, minCount: 200),
  ]

  bosses*: seq[BossSpawn] = @[
    BossSpawn(minute: 3, kind: Parakeet, count: 1),
    BossSpawn(minute: 8, kind: Koalio, count: 1),
    BossSpawn(minute: 12, kind: Parakeet, count: 2),
    BossSpawn(minute: 15, kind: Koalio, count: 1),
    BossSpawn(minute: 20, kind: Parakeet, count: 2),
    BossSpawn(minute: 25, kind: Koalio, count: 2),
    BossSpawn(minute: 30, kind: Reaper, count: 1),
  ]

proc weaponAt*(kind: WeaponKind, level: int): WeaponDef =
  ## Base definition plus every upgrade from level 2 up to `level`.
  result = weaponDefs[kind]
  for lvl in 2 .. min(level, maxWeaponLevel):
    let u = weaponUpgrades[kind][lvl]
    result.damage += u.damage
    result.cooldown += u.cooldown
    result.size += u.size
    result.speed += u.speed
    result.ttl += u.ttl
    result.amount += u.amount
    result.pierce += u.pierce

proc computeStats*(hero: CharacterKind, passives: openArray[(PassiveKind, int)]): Stats =
  result = characterDefs[hero].base
  for (kind, level) in passives:
    let l = float(level)
    case kind
    of Spinach: result.might += 0.1 * l
    of Armor: result.armor += 1.0 * l
    of HollowHeart: discard # handled by maxHpFor
    of Pummarola: result.regen += 0.2 * l
    of EmptyTome: result.cooldownMul *= (1.0 - 0.08 * l)
    of Wings: result.speedMul += 0.1 * l
    of Attractorb: result.magnet += 0.5 * l

proc maxHpFor*(hero: CharacterKind, passives: openArray[(PassiveKind, int)]): float =
  result = characterDefs[hero].maxHp
  for (kind, level) in passives:
    if kind == HollowHeart:
      result *= 1.0 + 0.2 * float(level)

proc hpScale*(minute: int): float =
  1.0 + 0.12 * float(minute)

proc waveFor*(minute: int): Wave =
  result = waves[0]
  for w in waves:
    if w.minute <= minute:
      result = w

proc xpForLevel*(level: int): int =
  ## XP needed to go from `level` to `level + 1` (Vampire Survivors curve).
  if level < 20:
    5 + 10 * (level - 1)
  elif level < 40:
    5 + 10 * 19 + 13 * (level - 20)
  else:
    5 + 10 * 19 + 13 * 20 + 16 * (level - 40)

proc gemValue*(kind: PickupKind): int =
  case kind
  of GemBlue: 1
  of GemGreen: 3
  of GemRed: 5
  else: 0

proc isGem*(kind: PickupKind): bool =
  kind in {GemBlue, GemGreen, GemRed}

proc clockText*(secs: float): string =
  let total = int(secs)
  align($(total div 60), 2, '0') & ":" & align($(total mod 60), 2, '0')
