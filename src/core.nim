import paranim/opengl
import paranim/gl

type
  Game* = object of RootGame
    deltaTime*: float
    totalTime*: float

var
  windowW = 1024
  windowH = 768

proc onKeyPress*(key: int) = discard
proc onKeyRelease*(key: int) = discard

proc onWindowResize*(windowWidth, windowHeight, worldWidth, worldHeight: int) =
  if windowWidth == 0 or windowHeight == 0:
    return
  windowW = windowWidth
  windowH = windowHeight

proc init*(game: var Game) =
  doAssert glInit()
  glEnable(GL_BLEND)
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)

proc tick*(game: var Game) =
  glClearColor(0.16, 0.22, 0.12, 1f)
  glClear(GL_COLOR_BUFFER_BIT)
  glViewport(0, 0, int32(windowW), int32(windowH))
