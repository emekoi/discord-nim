## 
##  Copyright (c) 2018 emekoi
##
##  This library is free software; you can redistribute it and/or modify it
##  under the terms of the MIT license. See LICENSE for details.
##

import
  private/shared,
  webhook,
  user

type
  AuditLogChangeValueType* {.pure.} = enum
    STRING,
    SNOWFLAKE,
    INTEGER,
    ROLES,
    OVERWRITE,
    BOOL


  AuditLogEvent* {.pure.} = enum
    NOT_AN_ACTUAL_LOG_EVENT = 0
    GUILD_UPDATE = 1
    CHANNEL_CREATE = 10
    CHANNEL_UPDATE = 11
    CHANNEL_DELETE = 12
    CHANNEL_OVERWRITE_CREATE = 13
    CHANNEL_OVERWRITE_UPDATE = 14
    CHANNEL_OVERWRITE_DELETE = 15
    MEMBER_KICK = 20
    MEMBER_PRUNE = 21
    MEMBER_BAN_ADD = 22
    MEMBER_BAN_REMOVE = 23
    MEMBER_UPDATE = 24
    MEMBER_ROLE_UPDATE = 25
    ROLE_CREATE = 30
    ROLE_UPDATE = 31
    ROLE_DELETE = 32
    INVITE_CREATE = 40
    INVITE_UPDATE = 41
    INVITE_DELETE = 42
    WEBHOOK_CREATE = 50
    WEBHOOK_UPDATE = 51
    WEBHOOK_DELETE = 52
    EMOJI_CREATE = 60
    EMOJI_UPDATE = 61
    EMOJI_DELETE = 62
    MESSAGE_DELETE = 72

  AuditLogChanges* = object
    new_value*: Option[AuditLogChangeValue]
    ## new value of the key
    old_value*: Option[AuditLogChangeValue]
    ## old value of the key
    key*: string
    ## type of audit log change key

  AuditEntryInfo* = object
    case action_type*: AuditLogEvent:
      of MEMBER_PRUNE:
        delete_member_days*: string
        ## number of days after which inactive members were kicked
        members_removed*: string
        ## number of members removed by the prune
      of MESSAGE_DELETE:
        channel_id*: SnowFlake
        ## channel in which the messages were deleted
        count*: string
        ## number of deleted messages
      of CHANNEL_OVERWRITE_CREATE,
        CHANNEL_OVERWRITE_UPDATE,
        CHANNEL_OVERWRITE_DELETE:
          id*: SnowFlake
          ## id of the overwritten entity
          kind*: string
          ## type of overwritten entity ("member" or "role")
          role_name*: string
          ## name of the role if type is "role"
      else: discard

  AuditLogEntry* = object
    target_id*: Option[string]
    ## 	id of the affected entity (webhook, user, role, etc.)
    changes*: Option[seq[AuditLogChanges]]
    ## seq of audit log change objects
    user_id*: SnowFlake
    ## the user who made the changes
    id*: SnowFlake
    ## id of the entry
    action_type*: AuditLogEvent
    ## type of action that occured
    options*: Option[AuditEntryInfo]
    ## additional info for certain action types
    reason*: Option[string]
    ## the reason for the change

  AuditLog* = object
    webhooks*: seq[WebHook]
    ## seq of Webhook objects
    users*: seq[User]
    ## seq of User objects
    audit_log_entries*: seq[AuditLogEntry]
    ## seq of audit log entry objects