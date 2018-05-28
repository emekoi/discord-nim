## 
##  Copyright (c) 2018 emekoi
##
##  This library is free software; you can redistribute it and/or modify it
##  under the terms of the MIT license. See LICENSE for details.
##

import private/shared, user

type WebHook* = object
  id*: SnowFlake
  guild_id*: Option[SnowFlake]
  channel_id*: SnowFlake
  user*: Option[User]
