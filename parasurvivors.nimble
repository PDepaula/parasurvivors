# Package

version       = "0.1.0"
author        = "Patrick"
description   = "A Vampire Survivors demo clone on the paranim stack"
license       = "MIT"
srcDir        = "src"
bin           = @["parasurvivors"]

# Dependencies

requires "nim >= 2.0.0"
requires "paranim >= 0.12.0"
requires "pararules >= 1.4.0"
requires "stb_image >= 2.5"
requires "paratext >= 0.13.0"
requires "parasound >= 1.0.0"
requires "paramidi >= 0.7.0"
requires "paramidi_soundfonts >= 0.2.0"

task test, "Run headless tests":
  for t in ["test_data", "test_systems", "test_rules"]:
    exec "nim c -r --hints:off --outdir:tmp tests/" & t & ".nim"

task assets, "Download and compose art assets":
  exec "bash tools/fetch_assets.sh"
