# Discordnim

A Discord library for Nim. 

# Installing

This assumes that you have your Nim environment (including [Nimble](https://github.com/nim-lang/nimble)) already set up, and that your Nim version is `0.18.0` or greater.
You can check your version with `nim --version`

```
Nim Compiler Version 0.18.1 [Windows: amd64]
Compiled at 2018-08-17
Copyright (c) 2006-2018 by Andreas Rumpf

active boot switches: -d:release
```

`nimble install discordnim`

# Usage

There are some examples in the `examples` folder.


Initialising a `Shard`:

```nim
import discordnim, asyncdispatch

proc someMessageCreateProc(s: Shard, m: MessageCreate) {.cdecl.} =
  if m.content == "ping":
    asyncCheck s.channelMessageSend(m.channel_id, "pong!")

let client = newDiscordClient("Bot <your token>")
## Add your gateway event methods
client.addHandler(EventType.message_create, someMessageCreateProc)

let shard = client.addShard()
shard.compress = true

## Lastly you connect
waitFor shard.startSession()
# Alternatively you can do 
# `client.startSession()`, but only useful if you have more than one shard.
```

All programs have to be compiled with the `--d:ssl` flag.

When compression is enabled you need a `zlib1.dll` present. Somewhere. I don't know where it should be placed.

[Documentation](https://krognol.github.io/discordnim/)

# Disclaimer

This package hasn't been tested on any Mac systems and are thus not guaranteed to work on them. Although, I have a hard time believeing they wouldn't work.

# Contributing

1. Fork it ( https://github.com/emekoi/discordnim/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request
