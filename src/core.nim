import paranim/opengl
import paranim/gl
import pararules
import sets, random
import data, systems, rules, render

type
  Game* = object of RootGame
    deltaTime*: float
    totalTime*: float

proc onKeyPress*(key: int) =
  var (keys) = session.query(gameRules.getKeys)
  keys.incl(key)
  session.insert(Global, PressedKeys, keys)
  var (just) = session.query(gameRules.getJustPressed)
  just.incl(key)
  session.insert(Global, JustPressed, just)

proc onKeyRelease*(key: int) =
  var (keys) = session.query(gameRules.getKeys)
  keys.excl(key)
  session.insert(Global, PressedKeys, keys)

proc onWindowResize*(windowWidth, windowHeight, worldWidth, worldHeight: int) =
  if windowWidth == 0 or windowHeight == 0:
    return
  session.insert(Global, WindowWidth, windowWidth)
  session.insert(Global, WindowHeight, windowHeight)
  session.insert(Global, WorldWidth, float(worldWidth) / zoom)
  session.insert(Global, WorldHeight, float(worldHeight) / zoom)

proc init*(game: var Game) =
  doAssert glInit()
  randomize()
  initRender(game)

proc pressed(just: HashSet[int], keys: varargs[int]): bool =
  for k in keys:
    if just.contains(k):
      return true
  false

proc moveSelection(just: HashSet[int], count: int) =
  let m = session.query(gameRules.getMenu)
  var sel = m.selected
  if just.pressed(KeyUp, KeyW): sel = (sel + count - 1) mod count
  if just.pressed(KeyDown, KeyS): sel = (sel + 1) mod count
  if sel != m.selected:
    session.insert(Global, SelectedIndex, sel)

proc finishChoice(index: int) =
  let m = session.query(gameRules.getMenu)
  if m.choices == nil or index >= m.choices[].len:
    return
  session.applyChoice(m.choices[][index])
  let pending = m.pending - 1
  session.insert(Global, PendingLevelUps, pending)
  if pending > 0:
    session.prepareChoices()
  else:
    session.insert(Global, Phase, Running)

proc tick*(game: var Game) =
  session.insert(Global, TotalTime, game.totalTime)
  let (phase) = session.query(gameRules.getPhase)
  let (just) = session.query(gameRules.getJustPressed)
  case phase
  of Title:
    when defined(autoplay): # test aid: skip the menus (nim c -d:autoplay -d:fastclock ...)
      session.startRun(Otto)
    else:
      if just.pressed(KeyEnter, KeySpace):
        session.insert(Global, SelectedIndex, 0)
        session.insert(Global, Phase, CharSelect)
  of CharSelect:
    moveSelection(just, 4)
    if just.pressed(KeyEnter, KeySpace):
      let m = session.query(gameRules.getMenu)
      session.startRun(CharacterKind(m.selected))
  of Running:
    if just.pressed(KeyEscape, KeyP):
      session.insert(Global, Phase, Paused)
    else:
      session.insert(Global, DeltaTime, game.deltaTime)
      session.fireRules()
      discard session.stepSystems(game.deltaTime)
      session.fireRules()
      let m = session.query(gameRules.getMenu)
      if m.pending > 0:
        session.prepareChoices()
        session.insert(Global, Phase, LevelUp)
  of LevelUp:
    moveSelection(just, 3)
    when defined(autoplay):
      finishChoice(0)
    else:
      if just.pressed(Key1): finishChoice(0)
      elif just.pressed(Key2): finishChoice(1)
      elif just.pressed(Key3): finishChoice(2)
      elif just.pressed(KeyEnter, KeySpace): finishChoice(session.query(gameRules.getMenu).selected)
  of Paused:
    if just.pressed(KeyEscape, KeyP):
      session.insert(Global, Phase, Running)
  of GameOver:
    if just.pressed(KeyR, KeyEnter):
      session = session.resetSession()
      session.insert(Global, Phase, CharSelect)
  session.insert(Global, JustPressed, initHashSet[int]())
  drawFrame(game)
