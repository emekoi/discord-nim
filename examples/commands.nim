## Has to be compiled with 
## '-d:ssl' and '--threads:on' flags

import asyncdispatch, discord, times

const PREFIX = "!!!"

proc messageCreate(s: Session, m: Message) =
    if m.author.id != s.State.me.id:
        let command = m.content

        case command:
            of PREFIX & "help":
                discard s.SendMessage(m.channel_id, "This is supposed to be some help command!")
            of PREFIX & "date":
                discard s.SendMessage(m.channel_id, $getLocalTime(getTime()))
            else: discard

let s = NewSession("Bot <token>")
s.messageCreate = messageCreate

asyncCheck s.SessionStart()
runForever()