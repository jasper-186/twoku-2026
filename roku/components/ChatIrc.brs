' Twitch IRC transport for the chat panel.
'
' Twitch's IRC endpoint (irc.chat.twitch.tv:6667) is plain TCP, so no TLS is
' needed - the Roku cannot speak the TLS 1.3 that Twitch's EventSub WebSocket
' requires. An earlier EventSub transport that used to be in the tree offered
' TLS 1.2 with RSA key exchange only, and there was no AES implementation to
' decrypt records with. See .known_issues/tls-1.3-on-roku.md.
'
' The token must carry the legacy chat:read / chat:edit scopes. A token with
' only the modern user:read:chat / user:write:chat names is rejected by
' Twitch's IRC server with "Login unsuccessful".
'
' The task runs for the lifetime of the app. It watches its own channel field
' and reconnects when the channel changes - the chat panel being hidden is not
' a reason to drop the connection, and stopping and restarting the task races
' with its own startup.

function init()
    m.top.functionName = "onChatStart"
end function

function getChannelUserId() as Object
    user = lookupUserByLogin(m.top.channel)
    if user = invalid or user.id = invalid
        return ""
    end if
    return user.id
end function

' Helix chat badges. The legacy badges.twitch.tv host no longer resolves.
' The response has to come from a user token with chat scopes, so this only
' works while signed in.
function fetchChatBadges(broadcaster_id as string) as Object
    if broadcaster_id = "" or broadcaster_id = invalid
        return invalid
    end if
    badges = GETJSON("https://api.twitch.tv/helix/chat/badges?broadcaster_id=" + broadcaster_id)
    if badges = invalid or badges.data = invalid
        return invalid
    end if
    return badges
end function

function onChatStart()
    ? "ChatIrc > chat transport started"
    m.connectedChannel = ""
    m.badgesChannel = ""
    m.socket = invalid
    m.port = invalid
    m.queue = createObject("roArray", 100, true)
    m.buffer = CreateObject("roByteArray")
    m.buffer[8192] = 0
    m.pending = ""

    while true
        if m.top.channel = "" or m.top.channel = invalid
            ' Nothing to connect to yet.
            sleep(500)
        else if m.top.channel <> m.connectedChannel
            connectToChannel(m.top.channel)
        else if m.socket <> invalid
            readFromSocket()
        else
            ' The connection failed - wait a moment before trying again.
            sleep(1000)
        end if
    end while
end function

sub connectToChannel(channel as string)
    closeConnection()

    channel_user_id = getChannelUserId()

    ' Chat badges. Helix returns the global badges plus the channel's own in
    ' one response, so a single fetch covers both. They are refetched when
    ' the channel changes, but not on every reconnect attempt.
    if channel_user_id <> "" and channel_user_id <> m.badgesChannel
        badges = fetchChatBadges(channel_user_id)
        if badges <> invalid
            m.global.addFields({ globalBadges: badges, channelBadges: badges })
        end if
        m.badgesChannel = channel_user_id
        ensureChannelBTTVEmotes(channel_user_id)
        ensureChannelFFZEmotes(channel_user_id)
    end if

    ensureGlobalBTTVEmotes()

    addr = CreateObject("roSocketAddress")
    addr.SetAddress("irc.chat.twitch.tv:6667")

    socket = CreateObject("roStreamSocket")
    socket.SetSendToAddress(addr)

    ' Connect before the message port is attached, so the connect is
    ' synchronous and has actually completed when it returns.
    if not socket.Connect() or not socket.IsConnected()
        ? "ChatIrc > could not connect to irc.chat.twitch.tv:6667"
        socket.Close()
        return
    end if
    ? "ChatIrc > connected to irc.chat.twitch.tv:6667"

    port = CreateObject("roMessagePort")
    socket.SetMessagePort(port)
    socket.notifyReadable(true)

    ' The socket has to be published before anything is sent - sendLine uses
    ' m.socket.
    m.socket = socket
    m.port = port

    sendLine("CAP REQ :twitch.tv/tags twitch.tv/commands")

    user_auth_token = m.global.userToken
    if m.top.loggedInUserName = "" or user_auth_token = invalid or user_auth_token = ""
        ? "ChatIrc > no user token - cannot authenticate"
        closeConnection()
        return
    end if

    sendLine("PASS oauth:" + user_auth_token)
    sendLine("NICK " + m.top.loggedInUserName)

    ? "ChatIrc >> JOIN > " channel
    sendLine("JOIN #" + channel)

    m.connectedChannel = channel
end sub

sub closeConnection()
    if m.socket <> invalid
        m.socket.Close()
        m.socket = invalid
    end if
    m.port = invalid
    m.connectedChannel = ""
end sub

sub readFromSocket()
    event = wait(250, m.port)
    if type(event) <> "roSocketEvent"
        ' Nothing arrived in the meantime. This short timeout is what lets the
        ' loop notice a channel change and lets outgoing messages go out.
        return
    end if

    if not m.socket.IsReadable()
        ? "ChatIrc > socket closed"
        closeConnection()
        return
    end if

    received = m.socket.Receive(m.buffer, 0, 8192)
    if received <= 0
        ? "ChatIrc > socket closed"
        closeConnection()
        return
    end if

    ' The buffer is reused, so only the first "received" bytes are data.
    m.pending = m.pending + Left(m.buffer.ToAsciiString(), received)
    lines = m.pending.Split(Chr(13) + Chr(10))
    ' Whatever follows the last CRLF is an incomplete line - keep it for the
    ' next read rather than publishing half a message.
    m.pending = lines[lines.Count() - 1]
    for i = 0 to lines.Count() - 2
        handleLine(lines[i])
    end for

    ' Hand a queued message to the renderer when it is ready for one.
    if m.top.readyForNextComment and m.queue.Count() > 0
        m.top.nextComment = m.queue.shift()
    end if
end sub

sub sendLine(line as string)
    m.socket.SendStr(line + Chr(13) + Chr(10))
end sub

sub handleLine(line as string)
    if line = "" then return

    if Left(line, 4) = "PING"
        sendLine("PONG :tmi.twitch.tv")
        return
    end if

    ' Notices carry the server's complaints - a failed login, a channel you
    ' are banned from - so they are worth seeing.
    if InStr(line, "NOTICE") > 0
        ? "ChatIrc > " line
        return
    end if

    ' Only chat messages and the user's own state are of interest. JOIN, 353,
    ' 366 and ROOMSTATE are not messages to render.
    if InStr(line, "PRIVMSG") = 0 and InStr(line, "USERSTATE") = 0
        return
    end if

    ' The renderer parses the IRCv3 tags, and it needs the whole line -
    ' splitting on ";" here would break any message containing a semicolon.
    ' The queue is bounded; if the renderer falls behind the oldest message is
    ' dropped rather than growing without limit.
    if m.queue.Count() >= 100
        m.queue.shift()
    end if
    m.queue.push(line)

    ' An outgoing message goes out as soon as there is room in the queue.
    if m.top.sendMessage <> "" and m.top.readyForNextComment
        sent = m.socket.SendStr("PRIVMSG #" + m.connectedChannel + " :" + m.top.sendMessage)
        if sent > 0
            m.top.clientComment = m.top.sendMessage
            m.top.nextComment = ""
        end if
        m.top.sendMessage = ""
    end if
end sub
