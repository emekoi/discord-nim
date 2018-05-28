## 
##  Copyright (c) 2018 emekoi
##
##  This library is free software; you can redistribute it and/or modify it
##  under the terms of the MIT license. See LICENSE for details.
##

import private/shared

type
  User* = object
    id*: SnowFlake
    ## the user's id
    username*: string
    ## the user's username, not unique across the platform
    discriminator*: string
    ## the user's 4-digit discord-tag
    avatar*: Option[string]
    ## the user's avatar hash
    bot*: Option[bool]
    ## whether the user belongs to an OAuth2 application
    mfa_enabled*: Option[bool]
    ## whether the user has two factor enabled on their account
    verified*: Option[bool]
    ## whether the email on this account has been verified
    email*: Option[string]
    ## 	the user's email
  
  # kind -> type
  Connection* = object
    id*: string
    ## id of the connection account
    name*: string
    ## the username of the connection account
    kind*: string
    ## 	the service of the connection (twitch, youtube)
    revoked*: bool
    ## 	whether the connection is revoked
    integrations*: seq[void]
    ## an seq of partial server integrations