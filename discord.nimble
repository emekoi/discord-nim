# Package

version       = "0.0.1"
author        = "emekoi"
description   = "discord library for nim"
license       = "MIT"
srcDir        = "src"
skipDirs      = @["examples", "docs"]

# Dependencies

requires "nim >= 0.18.0"
requires "websocket >= 0.3.1"
requires "zip >= 0.1.1"