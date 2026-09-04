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
  session.startRun(Otto) # temporary: Task 10 replaces this with the title flow

proc tick*(game: var Game) =
  session.insert(Global, TotalTime, game.totalTime)
  let (phase) = session.query(gameRules.getPhase)
  if phase == Running:
    session.insert(Global, DeltaTime, game.deltaTime)
    session.fireRules()
    discard session.stepSystems(game.deltaTime)
    session.fireRules()
    let m = session.query(gameRules.getMenu)
    if m.pending > 0:
      session.prepareChoices()
      session.insert(Global, Phase, LevelUp)
  session.insert(Global, JustPressed, initHashSet[int]())
  drawFrame(game)
