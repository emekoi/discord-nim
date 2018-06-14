include discordobjects, endpoints
import httpclient, asyncnet, strutils, json, marshal, net, re, ospaths, mimetypes, cgi, sequtils

proc request(s: DiscordClient, 
                bucketid, meth, url, contenttype, b: string = "", 
                sequence : int, 
                mp: MultipartData = nil,
                xheaders: HttpHeaders = nil): Future[AsyncResponse] {.gcsafe, async.} =
    let client = newAsyncHttpClient("DiscordBot (https://github.com/Krognol/discordnim, v" & VERSION & ")")
    await s.globalRL.preCheck(bucketid)

    client.headers["Authorization"] = s.token
    client.headers["Content-Type"] = contenttype 
    client.headers["Content-Length"] = $(b.len)
    if mp == nil:
        result = await client.request(url, meth, b)
    elif mp != nil and meth == "POST":
        result = await client.post(url, b, mp)
    client.close()
    
    if (await s.globalRL.postUpdate(url, result)) and sequence < 5:
        result = await s.request(bucketid, meth, url, contenttype, b, sequence+1)
    if result == nil: raise newException(Exception, "Rest API returned nil")

proc request(s: Shard,
                bucketid, meth, url, contenttype, b: string = "",
                sequence: int,
                mp: MultipartData = nil,
                xheaders: HttpHeaders = nil): Future[AsyncResponse] {.gcsafe, async.} =
    var id: string
    if bucketid == "":
        id = split(url, "?", 2)[0]
    else:
        id = bucketid
    await s.limiter.preCheck(id)
    result = await s.client.request(id, meth, url, contenttype, b, sequence, mp, xheaders)
    if (await s.limiter.postUpdate(url, result)):
        echo "You got ratelimited"

type
    CacheError* = object of Exception

proc join(g1: var Guild, g2: Guild): Guild =
    ## Joins g1(regular guild) and g2(Ready event guild)
    ## with g2's Ready event only fields
    g1.joined_at = g2.joined_at
    g1.large = g2.large
    g1.unavailable = g2.unavailable
    g1.member_count = g2.member_count
    g1.voice_states = g2.voice_states
    g1.members = g2.members
    g1.channels = g2.channels
    g1.presences = g2.presences
    result = g1

# Caching stuff
proc getGuild*(c: Cache, id: string): tuple[guild: Guild, exists: bool] {.gcsafe.} =
    ## Gets a guild from the cache
    if c == nil: raise newException(CacheError, "The cache is nil")
    initLock(c.lock)
    defer: deinitLock(c.lock)
    result = (Guild(), false)
    
    if c.guilds.hasKey(id):
        var guild = c.guilds[id]
        let t = c.ready.guilds.filterIt(it.id == guild.id)
        if t.len == 1: result = (guild.join(t[0]), true)

proc removeGuild*(c: Cache, guildid: string) {.raises: CacheError, gcsafe.}  =
    ## Removes a guild from the cache
    if c == nil: raise newException(CacheError, "The cache is nil")

    if not c.guilds.hasKey(guildid): return
    
    initLock(c.lock)
    c.guilds.del(guildid)
    deinitLock(c.lock)

proc updateGuild*(c: Cache, guild: Guild) {.raises: CacheError, inline, gcsafe.} =
    ## Updates a guild in the cache
    if c == nil: raise newException(CacheError, "The cache is nil")
    
    initLock(c.lock)
    c.guilds[guild.id] = guild
    deinitLock(c.lock)

proc getUser*(c: Cache, id: string): tuple[user: User, exists: bool] {.gcsafe.}  =
    ## Gets a user from the cache
    if c == nil: raise newException(CacheError, "The cache is nil")
    initLock(c.lock)
    defer: deinitLock(c.lock)
    result = (User(), false)
    
    if c.users.hasKey(id):
       result = (c.users[id], true)

proc removeUser*(c: Cache, id: string) {.raises: CacheError, inline, gcsafe.}  =
    ## Removes a user from the cache
    if c == nil: raise newException(CacheError, "The cache is nil")
    initLock(c.lock)
    defer: deinitLock(c.lock)
    if not c.users.hasKey(id): return

    c.users.del(id)

proc updateUser*(c: Cache, user: User) {.inline, gcsafe.}  =
    ## Updates a user in the cache
    if c == nil: raise newException(CacheError, "The cache is nil")

    initLock(c.lock)
    c.users[user.id] = user
    deinitLock(c.lock)

proc getChannel*(c: Cache, id: string): tuple[channel: DChannel, exists: bool] {.gcsafe.} =
    ## Gets a channel from the cache
    if c == nil: raise newException(CacheError, "The cache is nil")
    initLock(c.lock)
    defer: deinitLock(c.lock)
    result = (DChannel(), false)

    if c.channels.hasKey(id):
        result = (c.channels[id], true)


proc updateChannel*(c: Cache, chan: DChannel) {.inline, gcsafe.}  =
    ## Updates a channel in the cache
    if c == nil: raise newException(CacheError, "The cache is nil")
    initLock(c.lock)
    c.channels[chan.id] = chan
    deinitLock(c.lock)

proc removeChannel*(c: Cache, chan: string) {.raises: CacheError, inline, gcsafe.}  =
    ## Removes a channel from the cache
    if c == nil: raise newException(CacheError, "The cache is nil")
    initLock(c.lock)
    defer: deinitLock(c.lock)
    if not c.channels.hasKey(chan): return

    c.channels.del(chan)

proc getGuildMember*(c: Cache, guild, memberid: string): tuple[member: GuildMember, exists: bool] {.gcsafe.} =
    ## Gets a guild member from the cache
    if c == nil: raise newException(CacheError, "The cache is nil")
    
    result = (GuildMember(), false)
    var (guild, exists) = c.getGuild(guild)

    if not exists:
        return
    
    initLock(c.lock)
    defer: deinitLock(c.lock)
    for member in guild.members:
        if member.user.id == memberid:
            result = (member, true)
            break

proc addGuildMember*(c: Cache, member: GuildMember) {.inline, gcsafe.} =
    ## Adds a guild member to the cache
    if c == nil: raise newException(CacheError, "The cache is nil")

    initLock(c.lock)
    c.members.add(member.user.id, member)
    deinitLock(c.lock)

proc updateGuildMember*(c: Cache, m: GuildMember) {.inline, gcsafe.} =
    ## Updates a guild member in the cache
    if c == nil: raise newException(CacheError, "The cache is nil")

    initLock(c.lock)
    c.members[m.user.id] = m
    deinitLock(c.lock)

proc removeGuildMember*(c: Cache, gmember: GuildMember) {.inline, gcsafe.} =
    ## Removes a guild member from the cache
    if c == nil: raise newException(CacheError, "The cache is nil")
    initLock(c.lock)
    c.members.del(gmember.user.id)
    deinitLock(c.lock)

proc getRole*(c: Cache, guildid, roleid: string): tuple[role: Role, exists: bool] {.gcsafe.} =
    ## Gets a role from the cache
    if c == nil: raise newException(CacheError, "The cache is nil")
    
    result = (Role(), false)
    var (guild, exists) = c.getGuild(guildid)

    if not exists:
        return
    
    initLock(c.lock)
    defer: deinitLock(c.lock)
    for role in guild.roles:
        if role.id == roleid:
            result = (role, true)
            return

proc updateRole*(c: Cache, role: Role) {.raises: CacheError, gcsafe.} =
    ## Updates a role in the cache
    if c == nil: raise newException(CacheError, "The cache is nil")
    initLock(c.lock)
    defer: deinitLock(c.lock)

    c.roles[role.id] = role

proc removeRole*(c: Cache, role: string) {.raises: CacheError, gcsafe.} =
    ## Removes a role from the cache
    if c == nil: raise newException(CacheError, "The cache is nil")
    initLock(c.lock)
    defer: deinitLock(c.lock)

    if not c.roles.hasKey(role): return

    c.roles.del(role)

proc clear*(c: Cache) {.gcsafe.} =
    ## Clears a cache of all cached objects
    c.channels.clear()
    c.guilds.clear()
    c.members.clear()
    c.roles.clear()
    c.users.clear()

proc channel*(s: Shard, channel_id: string): Future[DChannel] {.gcsafe, async.} =
    ## Returns the channel with the given ID
    if s.cache.cacheChannels:
        var (chan, exists) = s.cache.getChannel(channel_id)

        if exists and chan.guild_id != "":
            return chan

    var url = endpointChannels(channel_id)
    let res = await s.request(url, "GET", url, "application/json", "", 0)
    let body = await res.body
    result = marshal.to[DChannel](body)

    if s.cache.cacheChannels:
        s.cache.channels[result.id] = result

proc channelEdit*(s: Shard, channelid: string, params: ChannelParams, reason: string = ""): Future[Guild] {.gcsafe, async.} =
    ## Edits a channel with the ChannelParams
    var url = endpointChannels(channelid)
    var h = if reason != "": newHttpHeaders() else: nil
    if h != nil: h["X-Audit-Log-Reason"] = reason.encodeUrl
    let res = await s.request(url, "PATCH", url, "application/json", $$params, 0, xheaders = h)
    let body = await res.body
    result = newGuild(parseJson(body))

proc deleteChannel*(s: Shard, channelid: string, reason: string = ""): Future[DChannel] {.gcsafe, async.} =
    ## Deletes a channel
    var url = endpointChannels(channelid)
    var h = if reason != "": newHttpHeaders() else: nil
    if h != nil: h["X-Audit-Log-Reason"] = reason.encodeUrl
    let res = await s.request(url, "DELETE", url, "application/json", "", 0, xheaders = h)
    let body = await res.body
    result = newChannel(parseJson(body))

proc channelMessages*(s: Shard, channelid: string, before, after, around: string, limit: int): Future[seq[Message]] {.gcsafe, async.} =
    ## Returns a channels messages
    ## Maximum of 100 messages
    var url = endpointChannelMessages(channelid) & "?"
    
    if before != "":
        url = url & "before=" & before & "&"
    
    if after != "":
        url = url & "after=" & after & "&"

    if around != "":
        url = url & "around=" & around & "&"

    if limit > 0 and limit <= 100:
        url = url & "limit=" & $limit

    let res = await s.request("", "GET", url, "application/json", "", 0)
    let body = await res.body
    let js = parseJson(body)
    result = @[]
    for msg in js.elems:
        result.add(newMessage(msg))

proc channelMessage*(s: Shard, channelid, messageid: string): Future[Message] {.gcsafe, async.} =
    ## Returns a message from a channel
    var url = endpointChannelMessage(channelid, messageid)
    let res = await s.request(url, "GET", url, "application/json", "", 0)
    let body = await res.body
    result = newMessage(parseJson(body))


proc channelMessageSend*(s: Shard, channelid, message: string): Future[Message] {.gcsafe, async.} =
    ## Sends a regular text message to a channel
    var url = endpointChannelMessages(channelid)
    let payload = %*{"content": message}
    let res = await s.request(url, "POST", url, "application/json", $payload, 0)
    let body = await res.body
    result = newMessage(parseJson(body))
    

proc channelMessageSendEmbed*(s: Shard, channelid: string, embed: Embed): Future[Message] {.gcsafe, async.} =
    ## Sends an Embed message to a channel
    var url = endpointChannelMessages(channelid)

    let payload = %*{
        "content": "",
        "embed": embed
    }

    let res = await s.request(url, "POST", url, "application/json", $payload, 0)
    let body = await res.body
    result = newMessage(parseJson(body))

proc channelMessageSendTTS*(s: Shard, channelid, message: string): Future[Message] {.gcsafe, async.} =
    ## Sends a TTS message to a channel
    var url = endpointChannelMessages(channelid)
    let payload = %*{"content": message, "tts": true}
    let res = await s.request(url, "POST", url, "application/json", $payload, 0)
    let body = await res.body
    result = newMessage(parseJson(body))

proc channelFileSendWithMessage*(s: Shard, channelid, name, message: string): Future[Message] {.gcsafe, async.} =
    ## Sends a file to a channel along with a message
    var data = newMultipartData()
    var url = endpointChannelMessages(channelid)

    let payload = %*{"content": message}
    data = data.addFiles({"file": name})
    data.add("payload_json", $payload, contentType = "application/json")
    let res = await s.request(url, "POST", url, "multipart/form-data", "", 0, data)
    let body = await res.body
    result = newMessage(parseJson(body))

proc channelFileSendWithMessage*(s: Shard, channelid, name, fbody, message: string): Future[Message] {.gcsafe, async.} =
    ## Sends the contents of a file as a file to a channel.
    if name == "":
        raise newException(Exception, "Parameter `name` of `channelFileSendWithMessage` can't be empty and has to have an extension")
    var data = newMultipartData()
    var url = endpointChannelMessages(channelid)

    let payload = %*{"content": message}
    var contenttype: string
    let (_, fname, ext) = splitFile(name)
    if ext.len > 0: contenttype = newMimetypes().getMimetype(ext[1..high(ext)], nil)
    
    data.add(name, fbody, fname & ext, contenttype)
    data.add("payload_json", $payload, contentType = "application/json")
    let res = await s.request(url, "POST", url, "multipart/form-data", "", 0, data)
    let body = await res.body
    result = newMessage(parseJson(body))

proc channelFileSend*(s: Shard, channelid, fname: string): Future[Message] {.gcsafe, async, inline.} =
    ## Sends a file to a channel
    result = await s.channelFileSendWithMessage(channelid, fname, "")

proc channelFileSend*(s: Shard, channelid, fname, fbody: string): Future[Message] {.gcsafe, async, inline.} =
    ## Sends the contents of a file as a file to a channel.
    result = await s.channelFileSendWithMessage(channelid, fname, fbody, "")

proc channelMessageReactionAdd*(s: Shard, channelid, messageid, emojiid: string) {.gcsafe, async, inline.} =
    ## Adds a reaction to a message
    var url = endpointMessageReactions(channelid, messageid, emojiid)
    asyncCheck s.request(url, "PUT", url, "application/json", "", 0)

proc messageDeleteOwnReaction*(s: Shard, channelid, messageid, emojiid: string) {.gcsafe, async, inline.} =
    ## Deletes your own reaction to a message
    var url = endpointOwnReactions(channelid, messageid, emojiid)
    asyncCheck s.request(url, "DELETE", url, "application/json", "", 0)

proc messageDeleteReaction*(s: Shard, channelid, messageid, emojiid, userid: string) {.gcsafe, async, inline.} =
    ## Deletes a reaction from a user from a message
    var url = endpointMessageUserReaction(channelid, messageid, emojiid, userid)
    asyncCheck s.request(url, "DELETE", url, "application/json", "", 0)

proc messageGetReactions*(s: Shard, channelid, messageid, emojiid: string): Future[seq[User]] {.gcsafe, async.} =
    ## Gets a message's reactions
    var url = endpointMessageReactions(channelid, messageid, emojiid)
    let res = await s.request(url, "GET", url, "application/json", "", 0)
    let body = await res.body
    let js = parseJson(body)
    result = @[]
    for user in js.elems:
        result.add(newUser(user))

proc messageDeleteAllReactions*(s: Shard, channelid, messageid: string) {.gcsafe, async, inline.} =
    ## Deletes all reactions on a message
    var url = endpointReactions(channelid, messageid)
    asyncCheck s.request(url, "DELETE", url, "application/json", "", 0)

proc channelMessageEdit*(s: Shard, channelid, messageid, content: string): Future[Message] {.gcsafe, async.} =
    ## Edits a message's contents
    var url = endpointChannelMessage(channelid, messageid)
    let payload = %*{"content": content}
    let res = await s.request(url, "PATCH", url, "application/json", $payload, 0)
    let body = await res.body
    result = newMessage(parseJson(body))
    
proc channelMessageDelete*(s: Shard, channelid, messageid: string, reason: string = "") {.gcsafe, async.} =
    ## Deletes a message
    var url = endpointChannelMessage(channelid, messageid)
    var h = if reason != "": newHttpHeaders() else: nil
    if h != nil: h["X-Audit-Log-Reason"] = reason.encodeUrl
    asyncCheck s.request(url, "DELETE", url, "application/json", "", 0, xheaders = h)

proc channelMessagesDeleteBulk*(s: Shard, channelid: string, messages: seq[string]) {.gcsafe, async.} =
    ## Deletes messages in bulk.
    ## Will not delete messages older than 2 weeks
    var url = endpointBulkDelete(channelid)
    let payload = %*{"messages": messages}
    asyncCheck s.request(url, "POST", url, "application/json", $payload, 0)

proc channelEditPermissions*(s: Shard, channelid: string, overwrite: Overwrite, reason: string = "") {.gcsafe, async.} =
    ## Edits a channel's permissions
    var url = endpointChannelPermissions(channelid, overwrite.id)
    let payload = %*{
        "type": overwrite.`type`, 
        "allow": overwrite.allow, 
        "deny": overwrite.deny
    }
    var h: HttpHeaders = if reason != "": newHttpHeaders() else: nil
    if h != nil: h["X-Audit-Log-Reason"] = reason.encodeUrl
    asyncCheck s.request(url, "PUT", url, "application/json", $payload, 0, xheaders = h)

proc channelInvites*(s: Shard, channel: string): Future[seq[Invite]] {.gcsafe, async.} =
    ## Returns all invites to a channel
    var url = endpointChannelInvites(channel)
    let res = await s.request(url, "GET", url, "application/json", "", 0)
    let body = await res.body
    let js = parseJson(body)
    result = @[]
    for invite in js.elems:
        result.add(newInvite(invite))

proc channelCreateInvite*(
                s: Shard, 
                channel: string, 
                max_age, max_uses: int, 
                temp, unique: bool, 
                reason: string = ""): Future[Invite] 
                {.gcsafe, async.} =
    ## Creates an invite to a channel
    var url = endpointChannelInvites(channel)
    let payload = %*{"max_age": max_age, "max_uses": max_uses, "temp": temp, "unique": unique}
    var h = if reason != "": newHttpHeaders() else: nil
    if h != nil: h["X-Audit-Log-Reason"] = reason.encodeUrl
    let res = await s.request(url, "POST", url, "application/json", $payload, 0, xheaders = h)
    let body = await res.body
    result = newInvite(parseJson(body))
    

proc channelDeletePermission*(s: Shard, channel, target: string, reason: string = "") {.gcsafe, async, inline.} =
    ## Deletes a channel permission
    var url = endpointChannelPermissions(channel, target)
    var h = if reason != "": newHttpHeaders() else: nil
    if h != nil: h["X-Audit-Log-Reason"] = reason.encodeUrl
    asyncCheck s.request(url, "DELETE", url, "application/json", "", 0, xheaders = h)

proc typingIndicatorTrigger*(s: Shard, channel: string) {.gcsafe, async, inline.} =
    ## Triggers the "X is typing" indicator
    var url = endpointTriggerTypingIndicator(channel)
    asyncCheck s.request(url, "POST", url, "application/json", "", 0)

proc channelPinnedMessages*(s: Shard, channel: string): Future[seq[Message]] {.gcsafe, async.} =
    ## Returns all pinned messages in a channel
    var url = endpointChannelPinnedMessages(channel)
    let res = await s.request(url, "GET", url, "application/json", "", 0)
    let body = await res.body
    let js = parseJson(body)
    result = @[]
    for msg in js.elems:
        result.add(newMessage(msg))

proc channelPinMessage*(s: Shard, channel, message: string) {.gcsafe, async, inline.} =
    ## Pins a message in a channel
    var url = endpointPinnedChannelMessage(channel, message)
    asyncCheck s.request(url, "PUT", url, "application/json", "", 0)

proc channelDeletePinnedMessage*(s: Shard, channel, message: string) {.gcsafe, async, inline.} =
    var url = endpointPinnedChannelMessage(channel, message)
    asyncCheck s.request(url, "DELETE", url, "application/json", "", 0)

# This might work?
type AddGroupDMUser* = object
    id: string
    nick: string

# This might work?
proc groupDMCreate*(s: Shard, accesstokens: seq[string], nicks: seq[AddGroupDMUser]): Future[DChannel] {.gcsafe, async.} =
    ## Creates a group DM channel
    var url = endpointDM()
    let payload = %*{"access_tokens": accesstokens, "nicks": nicks}
    let res = await s.request(url, "POST", url, "application/json", $payload, 0)
    let body = await res.body
    result = newChannel(parseJson(body))

proc groupDMAddUser*(s: Shard, channelid, userid, access_token, nick: string) {.gcsafe, async, inline.} =
    ## Adds a user to a group dm.
    ## Requires the 'gdm.join' scope.
    var url = endpointGroupDMRecipient(channelid, userid)
    let payload = %*{"access_token": access_token, "nick": nick}
    asyncCheck s.request(url, "PUT", url, "application/json", $payload, 0)
    
proc groupdDMRemoveUser*(s: Shard, channelid, userid: string) {.gcsafe, async, inline.} =
    ## Removes a user from a group dm.
    var url = endpointGroupDMRecipient(channelid, userid)
    asyncCheck s.request(url, "DELETE", url, "application/json", "", 0)

proc createGuild*(s: Shard, name: string): Future[Guild] {.gcsafe, async.} =
    ## Creates a guild.
    ## This endpoint is limited to 10 active guilds
    var url = endpointGuilds()
    let payload = %*{"name": name}
    let res = await s.request(url, "POST", url, "application/json", $payload, 0)
    let body = await res.body
    result = newGuild(parseJson(body))
    
proc guild*(s: Shard, id: string): Future[Guild] {.gcsafe, async.} =
    ## Gets a guild
    if s.cache.cacheGuilds:
        var (guild, exists) = s.cache.getGuild(id)

        if exists:
            return guild

    var url = endpointGuild(id)
    let res = await s.request(url, "GET", url, "application/json", "", 0)
    let body = await res.body
    result = newGuild(parseJson(body))
   
    if s.cache.cacheGuilds:
        s.cache.guilds[result.id] = result

        if s.cache.cacheRoles:
            for role in result.roles:
                s.cache.roles[role.id] = role

proc guildEdit*(s: Shard, guild: string, settings: GuildParams, reason: string = ""): Future[Guild] {.gcsafe, async.} =
    ## Edits a guild with the GuildParams
    var url = endpointGuild(guild)
    var h = if reason != "": newHttpHeaders() else: nil
    if h != nil: h["X-Audit-Log-Reason"] = reason.encodeUrl
    let res = await s.request(url, "PATCH", url, "application/json", $$settings, 0, xheaders = h)
    let body = await res.body
    result = newGuild(parseJson(body))
    
proc deleteGuild*(s: Shard, guild: string): Future[Guild] {.gcsafe, async.} =
    ## Deletes a guild
    var url = endpointGuild(guild)
    let res = await s.request(url, "DELETE", url, "application/json", "", 0)
    let body = await res.body
    result = newGuild(parseJson(body))
    
proc guildChannels*(s: Shard, guild: string): Future[seq[DChannel]] {.gcsafe, async.} =
    ## Returns all guild channels
    var url = endpointGuildChannels(guild)
    let res = await s.request(url, "GET", url, "application/json", "", 0)
    let body = await res.body
    let js = parseJson(body)
    result = @[]
    for chan in js.elems:
        result.add(newChannel(chan))

proc guildChannelCreate*(s: Shard, guild, channelname: string, voice: bool, reason: string = ""): Future[DChannel] {.gcsafe, async.} =
    ## Creates a new channel in a guild
    var url = endpointGuildChannels(guild)
    let payload = %*{"name": channelname, "voice": voice}
    var h = if reason != "": newHttpHeaders() else: nil
    if h != nil: h["X-Audit-Log-Reason"] = reason.encodeUrl
    let res = await s.request(url, "POST", url, "application/json", $payload, 0, xheaders = h)
    let body = await res.body
    result = newChannel(parseJson(body))

proc guildChannelPositionEdit*(s: Shard, guild, channel: string, position: int, reason: string = ""): Future[seq[DChannel]] {.gcsafe, async.} =
    ## Reorders the position of a channel and returns the new order
    var url = endpointGuildChannels(guild)
    let payload = %*{"id": channel, "position": position}
    var h = if reason != "": newHttpHeaders() else: nil
    if h != nil: h["X-Audit-Log-Reason"] = reason.encodeUrl
    let res = await s.request(url, "PATCH", url, "application/json", $payload, 0, xheaders = h)
    let body = await res.body
    let js = parseJson(body)
    result = @[]
    for chan in js.elems:
        result.add(newChannel(chan))

proc guildMembers*(s: Shard, guild: string, limit, after: int): Future[seq[GuildMember]] {.gcsafe, async.} =
    ## Returns up to 1000 guild members
    var url = endpointGuildMembers(guild) & "?"

    if limit > 1:
        url &= "limit=" & $limit & "&"
    if after > 0:
        url &= "after=" & $after & "&"

    let res = await s.request("", "GET", url, "application/json", "", 0)
    let body = await res.body
    let js = parseJson(body)
    result = @[]
    for member in js.elems:
        result.add(newGuildMember(member))

proc guildMember*(s: Shard, guild, userid: string): Future[GuildMember] {.gcsafe, async.} =
    ## Returns a guild member with the userid
    if s.cache.cacheGuildMembers:
        var (member, exists) = s.cache.getGuildMember(guild, userid)
        if exists:
            return member

    var url = endpointGuildMember(guild, userid)
    let res = await s.request(url, "GET", url, "application/json", "", 0)
    let body = await res.body
    result = newGuildMember(parseJson(body))
    
    if s.cache.cacheGuildMembers:
        s.cache.addGuildMember(result)

proc guildAddMember*(s: Shard, guild, userid, accesstoken: string): Future[GuildMember] {.gcsafe, async.} =
    ## Adds a guild member to the guild
    var url = endpointGuildMember(guild, userid)
    let payload = %*{"access_token": accesstoken}
    let res = await s.request(url, "PUT", url, "application/json", $payload, 0)
    let body = await res.body
    result = newGuildMember(parseJson(body))
    

proc guildMemberRoles*(s: Shard, guild, userid: string, roles: seq[string]) {.gcsafe, async, inline.} =
    ## Edits a guild member's roles
    var url = endpointGuildMember(guild, userid)
    let payload = %*{"roles": $roles}
    asyncCheck s.request(url, "PATCH", url, "application/json", $payload, 0)

proc guildMemberNick*(s: Shard, guild, userid, nick: string, reason: string = "") {.gcsafe, async.} =
    ## Sets the nickname of a member
    var url = endpointGuildMember(guild, userid)
    let payload = %*{"nick": nick}
    var h = if reason != "": newHttpHeaders() else: nil
    if h != nil: h["X-Audit-Log-Reason"] = reason.encodeUrl
    asyncCheck s.request(url, "PATCH", url, "application/json", $payload, 0, xheaders = h)

proc guildMemberMute*(s: Shard, guild, userid: string, mute: bool, reason: string = "") {.gcsafe, async.} =
    ## Mutes a guild member
    var url = endpointGuildMember(guild, userid)
    let payload = %*{"mute": mute}
    var h = if reason != "": newHttpHeaders() else: nil
    if h != nil: h["X-Audit-Log-Reason"] = reason.encodeUrl
    asyncCheck s.request(url, "PATCH", url, "application/json", $payload, 0, xheaders = h)

proc guildMemberDeafen*(s: Shard, guild, userid: string, deafen: bool, reason: string = "") {.gcsafe, async.} =
    ## Deafens a guild member
    var url = endpointGuildMember(guild, userid)
    let payload = %*{"deaf": deafen}
    var h = if reason != "": newHttpHeaders() else: nil
    if h != nil: h["X-Audit-Log-Reason"] = reason.encodeUrl
    asyncCheck s.request(url, "PATCH", url, "application/json", $payload, 0, xheaders = h)
 
proc guildMemberMove*(s: Shard, guild, userid, channel: string, reason: string = "") {.gcsafe, async.} =
    ## Moves a guild member from one channel to another
    ## only works if they are connected to a voice channel
    var url = endpointGuildMember(guild, userid)
    let payload = %*{"channel_id": channel}
    var h = if reason != "": newHttpHeaders() else: nil
    if h != nil: h["X-Audit-Log-Reason"] = reason.encodeUrl
    asyncCheck s.request(url, "PATCH", url, "application/json", $payload, 0, xheaders = h)

proc nick*(s: Shard, guild, nick: string, reason: string = "") {.gcsafe, async.} =
    ## Sets the nick for the current user
    var url = endpointEditNick(guild)
    let payload = %*{"nick": nick}
    var h = if reason != "": newHttpHeaders() else: nil
    if h != nil: h["X-Audit-Log-Reason"] = reason.encodeUrl
    asyncCheck s.request(url, "PATCH", url, "application/json", $payload, 0, xheaders = h)

proc guildMemberAddRole*(s: Shard, guild, userid, roleid: string, reason: string = "") {.gcsafe, async, inline.} =
    ## Adds a role to a guild member
    var url = endpointGuildMemberRoles(guild, userid, roleid)
    var h = if reason != "": newHttpHeaders() else: nil
    if h != nil: h["X-Audit-Log-Reason"] = reason.encodeUrl
    asyncCheck s.request(url, "PUT", url, "application/json", "", 0, xheaders = h)

proc guildMemberRemoveRole*(s: Shard, guild, userid, roleid: string, reason: string = "") {.gcsafe, async, inline.} =
    ## Removes a role from a guild member
    var url = endpointGuildMemberRoles(guild, userid, roleid)
    var h = if reason != "": newHttpHeaders() else: nil
    if h != nil: h["X-Audit-Log-Reason"] = reason.encodeUrl
    asyncCheck s.request(url, "DELETE", url, "application/json", "", 0, xheaders = h)

proc guildRemoveMemberWithReason*(s: Shard, guild, userid, reason: string) {.gcsafe, async.} =
    var url = endpointGuildMember(guild, userid)
    if reason != "": url &= "?reason=" & encodeUrl(reason)
    var h = if reason != "": newHttpHeaders() else: nil
    if h != nil: h["X-Audit-Log-Reason"] = reason.encodeUrl
    asyncCheck s.request(url, "DELETE", url, "application/json", "", 0, xheaders = h)

proc guildRemoveMember*(s: Shard, guild, userid: string, reason: string = "") {.gcsafe, async, inline.} =
    ## Removes a guild membe from the guild
    asyncCheck s.guildRemoveMemberWithReason(guild, userid, "")

proc guildBans*(s: Shard, guild: string): Future[seq[User]] {.gcsafe, async.} =
    ## Returns all users who have been banned from the guild
    var url = endpointGuildBans(guild)
    let res = await s.request(url, "GET", url, "application/json", "", 0)
    let body = await res.body
    let js = parseJson(body)
    result = @[]
    for user in js.elems:
        result.add(newUser(user))

proc guildUserBan*(s: Shard, guild, userid: string, reason: string = "") {.gcsafe, async, inline.} =
    ## Bans a user from the guild
    var url = endpointGuildBan(guild, userid)
    var h = if reason != "": newHttpHeaders() else: nil
    if h != nil: h["X-Audit-Log-Reason"] = reason.encodeUrl
    asyncCheck s.request(url, "PUT", url, "application/json", "", 0, xheaders = h)

proc guildRemoveBan*(s: Shard, guild, userid: string, reason: string = "") {.gcsafe, async, inline.} =
    ## Removes a ban from the guild
    var url = endpointGuildBan(guild, userid)
    var h = if reason != "": newHttpHeaders() else: nil
    if h != nil: h["X-Audit-Log-Reason"] = reason.encodeUrl
    asyncCheck s.request(url, "DELETE", url, "application/json", "", 0, xheaders = h)

proc guildRoles*(s: Shard, guild: string): Future[seq[Role]] {.gcsafe, async.} =
    ## Returns all guild roles
    var url = endpointGuildRoles(guild)
    let res = await s.request(url, "GET", url, "application/json", "", 0)
    let body = await res.body
    let js = parseJson(body)
    result = @[]
    for role in js.elems:
        result.add(newRole(role))
    
proc guildRole*(s: Shard, guild, roleid: string): Future[Role] {.gcsafe, async.} =
    ## Returns a role with the given id.
    if s.cache.cacheRoles:
        var (rolea, exists) = s.cache.getRole(guild, roleid)

        if exists:
            return rolea

    let roles = await s.guildRoles(guild)

    for role in roles:
        if role.id == roleid:
            s.cache.roles[role.id] = role
            result = role
            break
    
    if s.cache.cacheRoles:
        s.cache.roles[result.id] = result

proc guildCreateRole*(s: Shard, guild: string, reason: string = ""): Future[Role] {.gcsafe, async.} =
    ## Creates a new role in the guild
    var url = endpointGuildRoles(guild)
    var h = if reason != "": newHttpHeaders() else: nil
    if h != nil: h["X-Audit-Log-Reason"] = reason.encodeUrl
    let res = await s.request(url, "POST", url, "application/json", "", 0, xheaders = h)
    let body = await res.body
    result = newRole(parseJson(body))
    
proc guildEditRolePosition*(s: Shard, guild: string, roles: seq[Role], reason: string = ""): Future[seq[Role]] {.gcsafe, async.} =
    ## Edits the positions of a guilds roles roles
    ## and returns the new roles order
    var url = endpointGuildRoles(guild)
    var h = if reason != "": newHttpHeaders() else: nil
    if h != nil: h["X-Audit-Log-Reason"] = reason.encodeUrl
    let res = await s.request(url, "PATCH", url, "application/json", $$roles, 0, xheaders = h)
    let body = await res.body
    let js = parseJson(body)
    result = @[]
    for role in js.elems:
        result.add(newRole(role))    

proc guildEditRole*(
            s: Shard, 
            guild, roleid, name: string, 
            permissions, color: int, 
            hoist, mentionable: bool,
            reason: string = ""): Future[Role] 
            {.gcsafe, async.} =
    ## Edits a role
    var url = endpointGuildRole(guild, roleid)
    let payload = %*{"name": name, "permissions": permissions, "color": color, "hoist": hoist, "mentionable": mentionable}
    var h = if reason != "": newHttpHeaders() else: nil
    if h != nil: h["X-Audit-Log-Reason"] = reason.encodeUrl
    let res = await s.request(url, "PATCH", url, "application/json", $payload, 0, xheaders = h)
    let body = await res.body
    result = newRole(parseJson(body))
   
proc guildDeleteRole*(s: Shard, guild, roleid: string, reason: string = "") {.gcsafe, async, inline.} =
    ## Deletes a role
    var url = endpointGuildRole(guild, roleid)
    var h = if reason != "": newHttpHeaders() else: nil
    if h != nil: h["X-Audit-Log-Reason"] = reason.encodeUrl
    asyncCheck s.request(url, "DELETE", url, "application/json", "", 0, xheaders = h)

proc guildPruneCount*(s: Shard, guild: string, days: int): Future[int] {.gcsafe, async.} =
    ## Returns the number of members who would get kicked
    ## during a prune operation
    var url = endpointGuildPruneCount(guild) & "?days=" & $days
    let res = await s.request(url, "GET", "", "application/json", "", 0)
    let body = await res.body
    let js = parseJson(body)
    result = js["pruned"].num.int

proc guildPruneBegin*(s: Shard, guild: string, days: int, reason: string = ""): Future[int] {.gcsafe, async.} =
    ## Begins a prune operation and
    ## kicks all members who haven't been active
    ## for N days
    var url = endpointGuildPruneCount(guild) & "?days=" & $days
    var h = if reason != "": newHttpHeaders() else: nil
    if h != nil: h["X-Audit-Log-Reason"] = reason.encodeUrl
    let res = await s.request(url, "POST", "", "application/json", "", 0, xheaders = h)
    let body = await res.body
    let js = parseJson(body)
    result = js["pruned"].num.int

proc guildVoiceRegions*(s: Shard, guild: string): Future[seq[VoiceRegion]] {.gcsafe, async.} =
    ## Lists all voice regions in a guild
    var url = endpointGuildVoiceRegions(guild)
    let res = await s.request(url, "GET", url, "application/json", "", 0)
    let body = await res.body
    let js = parseJson(body)
    result = @[]
    for vr in js.elems:
        result.add(newVoiceRegion(vr))
    
proc guildInvites*(s: Shard, guild: string): Future[seq[Invite]] {.gcsafe, async.} =
    ## Lists all guild invites
    var url = endpointGuildInvites(guild)
    let res = await s.request(url, "GET", url, "application/json", "", 0)
    let body = await res.body
    let js = parseJson(body)
    result = @[]
    for invite in js.elems:
        result.add(newInvite(invite))    

proc guildIntegrations*(s: Shard, guild: string): Future[seq[Integration]] {.gcsafe, async.} =
    ## Lists all guild integrations
    var url = endpointGuildIntegrations(guild)
    let res = await s.request(url, "GET", url, "application/json", "", 0)
    let body = await res.body
    let js = parseJson(body)
    result = @[]
    for integ in js.elems:
        result.add(newIntegration(integ))

proc guildIntegrationCreate*(s: Shard, guild, typ, id: string) {.gcsafe, async.} =
    ## Creates a new guild integration
    var url = endpointGuildIntegrations(guild)
    let payload = %*{"type": typ, "id": id}
    asyncCheck s.request(url, "POST", url, "application/json", $payload, 0)

proc guildIntegrationEdit*(s: Shard, guild, integrationid: string, behaviour, grace: int, emotes: bool) {.gcsafe, async.} =
    ## Edits a guild integration
    var url = endpointGuildIntegration(guild, integrationid)
    let payload = %*{"expire_behavior": behaviour, "expire_grace_period": grace, "enable_emoticons": emotes}
    asyncCheck s.request(url, "PATCH", url, "application/json", $payload, 0)

proc guildIntegrationDelete*(s: Shard, guild, integration: string) {.gcsafe, async.} =
    ## Deletes a guild Integration
    var url = endpointGuildIntegration(guild, integration)
    asyncCheck s.request(url, "DELETE", url, "application/json", "", 0)

proc guildIntegrationSync*(s: Shard, guild, integration: string) {.gcsafe, async.} =
    ## Syncs an existing guild integration
    var url = endpointSyncGuildIntegration(guild, integration)
    asyncCheck s.request(url, "POST", url, "application/json", "", 0)

proc guildEmbed*(s: Shard, guild: string): Future[GuildEmbed] {.gcsafe, async.} =
    ## Gets a GuildEmbed
    var url = endpointGuildEmbed(guild)
    let res = await s.request(url, "GET", url, "application/json", "", 0)
    let body = await res.body
    result = newGuildEmbed(parseJson(body))
    
proc guildEmbedEdit*(s: Shard, guild: string, enabled: bool, channel: string): Future[GuildEmbed] {.gcsafe, async.} =
    ## Edits a GuildEmbed
    var url = endpointGuildEmbed(guild)
    let embed = GuildEmbed(enabled: enabled, channel_id: channel)
    let res = await s.request(url, "PATCH", url, "application/json", $$embed, 0)
    let body = await res.body
    result = newGuildEmbed(parseJson(body))

proc guildAuditLog*(s: Shard, guild: string, 
                        user_id: string = "", action_type: int = -1, 
                        before: string = "", limit: int = 50): Future[AuditLog]
                        {.gcsafe, async.} =
    
    var url = endpointGuildAuditLog(guild) & "?"
    if user_id != "": url &= "user_id=" & user_id & "&"
    if action_type >= 1: url &= "action_type" & $action_type & "&"
    if before != "": url &= "before=" & before & "&"
    url &= "limit=" & $limit
    let res = await s.request("", "GET", url, "application/json", "", 0)
    let body = await res.body
    let temp = parseJson(body)
    result = newAuditLog(temp)

proc invite*(s: Shard, code: string): Future[Invite] {.gcsafe, async.} =
    ## Gets an invite with code
    var url = endpointInvite(code)
    let res = await s.request(url, "GET", url, "application/json", "", 0)
    let body = await res.body
    result = newInvite(parseJson(body))
   
proc inviteDelete*(s: Shard, code: string, reason: string = ""): Future[Invite] {.gcsafe, async.} =
    ## Deletes an invite
    var url = endpointInvite(code)
    var h = if reason != "": newHttpHeaders() else: nil
    if h != nil: h["X-Audit-Log-Reason"] = reason.encodeUrl
    let res = await s.request(url, "DELETE", url, "application/json", "", 0, xheaders = h)
    let body = await res.body
    result = newInvite(parseJson(body))
    
proc me*(s: Shard): Future[User] {.gcsafe, async.} =
    ## Returns the current user
    var url = endpointCurrentUser()
    let res = await s.request(url, "GET", url, "application/json", "", 0)
    let body = await res.body
    result = newUser(parseJson(body))

proc user*(s: Shard, userid: string): Future[User] {.gcsafe, async.} =
    ## Gets a user
    if s.cache.cacheUsers:
        var (user, exists) = s.cache.getUser(userid)

        if exists:
            return user

    var url = endpointUser(userid)
    let res = await s.request(url, "GET", url, "application/json", "", 0)
    let body = await res.body
    result = newUser(parseJson(body))

    if s.cache.cacheUsers:
        s.cache.users[result.id] = result
        
proc usernameEdit*(s: Shard, name: string): Future[User] {.gcsafe, async.} =
    ## Edits the current users username
    var url = endpointCurrentUser()
    let payload = %*{"username": name}
    let res = await s.request(url, "PATCH", url, "application/json", $payload, 0)
    let body = await res.body
    result = newUser(parseJson(body))
    
proc avatarEdit*(s: Shard, avatar: string): Future[User] {.gcsafe, async.} =
    ## Changes the current users avatar
    var url = endpointCurrentUser()
    let payload = %*{"avatar": avatar}
    let res = await s.request(url, "PATCH", url, "application/json", $payload, 0)
    let body = await res.body
    result = newUser(parseJson(body))

proc currentUserGuilds*(s: Shard): Future[seq[UserGuild]] {.gcsafe, async.} =
    ## Lists the current users guilds
    var url = endpointCurrentUserGuilds()
    let res = await s.request(url, "GET", url, "application/json", "", 0)
    let body = await res.body
    let js = parseJson(body)
    result = @[]
    for uguild in js.elems:
        result.add(newUserGuild(uguild))

proc leaveGuild*(s: Shard, guild: string) {.gcsafe, async.} =
    ## Makes the current user leave the specified guild
    var url = endpointLeaveGuild(guild)
    asyncCheck s.request(url, "DELETE", url, "application/json", "", 0)

proc activePrivateChannels*(s: Shard): Future[seq[DChannel]] {.gcsafe, async.} =
    ## Lists all active DM channels
    var url = endpointUserDMs()
    let res = await s.request(url, "GET", url, "application/json", "", 0)
    let body = await res.body
    let js = parseJson(body)
    result = @[]
    for chan in js.elems:
        result.add(newChannel(chan))

proc privateChannelCreate*(s: Shard, recipient: string): Future[DChannel] {.gcsafe, async.} =
    ## Creates a new DM channel
    var url = endpointDM()
    let payload = %*{"recipient_id": recipient}
    let res = await s.request(url, "POST", url, "application/json", $payload, 0)
    let body = await res.body
    result = newChannel(parseJson(body))
    
proc voiceRegions*(s: Shard): Future[seq[VoiceRegion]] {.gcsafe, async.} =
    ## Lists all voice regions
    var url = endpointListVoiceRegions()
    let res = await s.request(url, "GET", url, "application/json", "", 0)
    let body = await res.body
    let js = parseJson(body)
    result = @[]
    for vreg in js.elems:
        result.add(newVoiceRegion(vreg))

proc webhookCreate*(s: Shard, channel, name, avatar: string, reason: string = ""): Future[Webhook] {.gcsafe, async.} =
    ## Creates a webhook
    var url = endpointWebhooks(channel)
    let payload = %*{"name": name, "avatar": avatar}
    var h = if reason != "": newHttpHeaders() else: nil
    if h != nil: h["X-Audit-Log-Reason"] = reason.encodeUrl
    let res = await s.request(url, "POST", url, "application/json", $payload, 0, xheaders = h)
    let body = await res.body
    result = newWebhook(parseJson(body))

proc channelWebhooks*(s: Shard, channel: string): Future[seq[Webhook]] {.gcsafe, async.} =
    ## Lists all webhooks in a channel
    var url = endpointWebhooks(channel)
    let res = await s.request(url, "GET", url, "application/json", "", 0)
    let body = await res.body
    let js = parseJson(body)
    result = @[]
    for webhook in js.elems:
        result.add(newWebhook(webhook))

proc guildWebhooks*(s: Shard, guild: string): Future[seq[Webhook]] {.gcsafe, async.} =
    ## Lists all webhooks in a guild
    var url = endpointGuildWebhooks(guild)
    let res = await s.request(url, "GET", url, "application/json", "", 0)
    let body = await res.body
    let js = parseJson(body)
    result = @[]
    for webhook in js.elems:
        result.add(newWebhook(webhook))

proc getWebhookWithToken*(s: Shard, webhook, token: string): Future[Webhook] {.gcsafe, async.} =
    ## Gets a webhook with a token
    var url = endpointWebhookWithToken(webhook, token)
    let res = await s.request(url, "GET", url, "application/json", "", 0)
    let body = await res.body
    result = newWebhook(parseJson(body))

proc webhookEdit*(s: Shard, webhook, name, avatar: string, reason: string = ""): Future[Webhook] {.gcsafe, async.} =
    ## Edits a webhook
    var url = endpointWebhook(webhook)
    let payload = %*{"name": name, "avatar": avatar}
    var h = if reason != "": newHttpHeaders() else: nil
    if h != nil: h["X-Audit-Log-Reason"] = reason.encodeUrl
    let res = await s.request(url, "PATCH", url, "application/json", $payload, 0, xheaders = h)
    let body = await res.body
    result = newWebhook(parseJson(body))
    
proc webhookEditWithToken*(s: Shard, webhook, token, name, avatar: string, reason: string = ""): Future[Webhook] {.gcsafe, async.} =
    ## Edits a webhook with a token
    var url = endpointWebhookWithToken(webhook, token)
    let payload = %*{"name": name, "avatar": avatar}
    var h = if reason != "": newHttpHeaders() else: nil
    if h != nil: h["X-Audit-Log-Reason"] = reason.encodeUrl
    let res = await s.request(url, "PATCH", url, "application/json", $payload, 0, xheaders = h)
    let body = await res.body
    result = newWebhook(parseJson(body))

proc webhookDelete*(s: Shard, webhook: string, reason: string = ""): Future[Webhook] {.gcsafe, async.} =
    ## Deletes a webhook
    var url = endpointWebhook(webhook)
    var h = if reason != "": newHttpHeaders() else: nil
    if h != nil: h["X-Audit-Log-Reason"] = reason.encodeUrl
    let res = await s.request(url, "DELETE", url, "application/json", "", 0, xheaders = h)
    let body = await res.body
    result = newWebhook(parseJson(body))
    
proc webhookDeleteWithToken*(s: Shard, webhook, token: string, reason: string = ""): Future[Webhook] {.gcsafe, async.} =
    ## Deltes a webhook with a token
    var url = endpointWebhookWithToken(webhook, token)
    var h = if reason != "": newHttpHeaders() else: nil
    if h != nil: h["X-Audit-Log-Reason"] = reason.encodeUrl
    let res = await s.request(url, "DELETE", url, "application/json", "", 0, xheaders = h)
    let body = await res.body
    result = newWebhook(parseJson(body))

proc executeWebhook*(s: Shard, webhook, token: string, wait: bool, payload: WebhookParams) {.gcsafe, async, inline.} =
    ## Executes a webhook
    var url = endpointWebhookWithToken(webhook, token)
    asyncCheck s.request(url, "POST", url, "application/json", $$payload, 0) 

proc `$`*(u: User): string {.gcsafe, inline.} =
    ## Stringifies a user.
    ##
    ## e.g: Username#1234
    result = u.username & "#" & u.discriminator

proc `$`*(c: DChannel): string {.gcsafe, inline.} =
    ## Stringifies a channel.
    ##
    ## e.g: #channel-name
    result = "#" & c.name

proc `$`*(e: Emoji): string {.gcsafe, inline.} =
    ## Stringifies an emoji.
    ##
    ## e.g: :emojiName:129837192873
    result = ":" & e.name & ":" & e.id

proc `@`*(u: User): string {.gcsafe, inline.} =
    ## Returns a message formatted user mention.
    ##
    ## e.g: <@109283102983019283>
    result = "<@" & u.id & ">"

proc `@`*(c: DChannel): string {.gcsafe, inline.} = 
    ## Returns a message formatted channel mention.
    ##
    ## e.g: <#1239810283>
    result = "<#" & c.id & ">"

proc `@`*(r: Role): string {.gcsafe, inline.} =
    ## Returns a message formatted role mention
    ##
    ## e.g: <@&129837128937>
    result = "<@&" & r.id & ">"

proc `@`*(e: Emoji): string {.gcsafe, inline.} =
    ## Returns a message formated emoji.
    ##
    ## e.g: <:emojiName:1920381>
    result = "<" & $e & ">"

proc defaultAvatar*(u: User): string =
    ## Returns the avatar url of the user.
    ##
    ## If the user doesn't have an avatar it returns the users default avatar.
    if u.avatar.isNilOrEmpty():
        result = "https://cdn.discordapp.com/embed/avatars/$1.png" % [$(u.discriminator.parseInt mod 5)]
    else: 
        if u.avatar.startsWith("a_"):
            result = endpointAvatarAnimated(u.id, u.avatar)
        else:
            result = endpointAvatar(u.id, u.avatar)

proc stripMentions*(msg: Message): string {.gcsafe.} =  
    ## Strips all user mentions from a message
    ## and replaces them with plaintext
    ##
    ## e.g: <@1901092738173> -> @Username#1234
    if msg.mentions == nil or msg.mentions.len == 0: return msg.content

    result = msg.content

    for user in msg.mentions:
        let regex = re("(<@!?" & user.id & ">)")
        result = result.replace(regex, "@" & $user)

proc stripEveryoneMention*(msg: Message): string {.gcsafe, inline.} =
    ## Strips a message of any @everyone and @here mention
    if not msg.mention_everyone: return msg.content
    result = msg.content.replace(re"(@everyone)", "").replace(re"(@here)", "")

proc newChannelParams*(name, topic: string = "",
                       position: int = 0,
                       bitrate: int = 48,
                       userlimit: int = 0): ChannelParams {.gcsafe, inline.} =
    ## Initialises a new ChannelParams object
    ## for altering channel settings.
    result = ChannelParams(
        name: name,
        position: position,
        topic: topic,
        bitrate: bitrate,
        user_limit: userlimit)

proc newGuildParams*(name, region, afkchan: string = "", 
                     verlvl: int = 0,
                     defnotif: int = 0,
                     afktim: int = 0,
                     icon: string = "",
                     ownerid: string = "",
                     splash: string = ""): GuildParams {.gcsafe, inline.} =
    ## Initialises a new GuildParams object
    ## for altering guild settings.
    result = GuildParams(
        name: name,
        region: region,
        verification_level: verlvl,
        default_message_notifications: defnotif,
        afk_channel_id: afkchan,
        afk_timeout: afktim,
        icon: icon,
        owner_id: ownerid,
        splash: splash
    )

proc newGuildMemberParams*(nick, channelid: string = "",
                          roles: seq[string] = @[],
                          mute: bool = false,
                          deaf: bool = false): GuildMemberParams {.gcsafe, inline.} =
    ## Initialises a new GuildMemberParams object
    ## for altering guild members.
    result = GuildMemberParams(
        nick: nick,
        roles: roles,
        mute: mute,
        deaf: deaf,
        channel_id: channelid
    )

proc newWebhookParams*(content, username, avatarurl: string = "", 
                       tts: bool = false, embeds: seq[Embed] = nil): WebhookParams {.gcsafe, inline.} =
    ## Initialises a new WebhookParams object
    ## for altering webhooks.
    result = WebhookParams(
        content: content, 
        username: username,
        avatar_url: avatarurl,
        tts: tts,
        embeds: embeds
    )

proc messageGuild*(s: Shard, m: Message): string =
    ## Returns the guild id of the guild
    ## the message was sent in.
    ##
    ## Returns an empty string if it can't find the guild in the cache
    ## or by requesting it from the API.
    result = ""
    if s.cache.cacheChannels:
        var (chan, exists) = s.cache.getChannel(m.channel_id)
        if exists:
            return chan.guild_id
    var chan = waitFor s.channel(m.channel_id)
    if chan != DChannel():
        result = chan.guild_id