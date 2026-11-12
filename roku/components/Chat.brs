sub init()
    m.chatPanel = m.top.findNode("chatPanel")
    m.keyboard = m.top.findNode("keyboard")
    m.chatButton = m.top.findNode("chatButton")
    m.chat = CreateObject("roSGNode", "ChatIrc")
    m.chat.observeField("nextComment", "onNewComment")
    m.chat.observeField("clientComment", "onNewComment")
    m.top.observeField("loggedInUserName", "setLoggedInUserName")
    m.top.observeField("loggedInUserId", "setLoggedInUserId")
    m.chat.readyForNextComment = true
    ' The transport runs for the lifetime of the app and reconnects itself
    ' when the channel changes. Starting and stopping it around the panel
    ' being visible or hidden races with its own startup - a stop that
    ' arrives before the thread has run cancels it for good.
    m.chat.control = "run"
    m.userstate_change = false
    m.translation = 0
end sub

sub onSetKeyboardFocus()
    if m.top.setKeyboardFocus
        m.keyboard.visible = true
        m.chatButton.visible = true
        m.top.setKeyboardFocus = false
        m.keyboard.setFocus(true)
    end if
end sub

sub setLoggedInUserName()
    m.chat.loggedInUserName = m.top.loggedInUserName
end sub
sub setLoggedInUserId()
    m.chat.loggedInUserId = m.top.loggedInUserId
end sub

sub onVideoChange()
    ' Deliberately does nothing. Hiding or showing the chat panel does not
    ' disconnect the chat - the transport keeps the connection and reconnects
    ' by itself when the channel changes.
end sub

sub onEnterChannel()
    ? "Chat >> onEnterChannel > " m.top.channel
    m.chat.channel = m.top.channel
    m.chat.broadcasterUserId = m.top.broadcasterUserId
end sub

' Pull an IRC line apart into its IRCv3 tags, its command and parameters,
' and the trailing message.
'
' The line looks like:
'   @tag=value;tag2=value2 :nick!nick@nick PRIVMSG #channel :the message
'
' The tags end at the first " :", and the message is everything after the
' first " :" in what is left. Tag values cannot contain a space, so the
' first " :" is always the right boundary.
function parseIrcLine(line as string) as object
    parsed = { tags: {}, params: "", message: "" }

    tagPart = line
    rest = ""
    boundary = InStr(line, " :")
    if boundary > 0
        tagPart = Left(line, boundary - 1)
        rest = Mid(line, boundary + 2)
    end if

    if Left(tagPart, 1) = "@"
        tagList = Mid(tagPart, 2).Split(";")
        for each tag in tagList
            if tag <> ""
                equals = InStr(tag, "=")
                if equals > 0
                    parsed.tags[Left(tag, equals - 1)] = Mid(tag, equals + 1)
                end if
            end if
        end for
    end if

    trailing = InStr(rest, " :")
    if trailing > 0
        parsed.params = Left(rest, trailing - 1)
        parsed.message = Mid(rest, trailing + 2)
    else
        parsed.params = rest
    end if

    return parsed
end function

' The emotes tag looks like "25:0-4,12-16/1902:6-10" - an emote id, then the
' character ranges it covers.
function parseEmotes(emotes as string) as object
    emote_set = {}
    if emotes = "" or emotes = invalid
        return emote_set
    end if
    emoteList = emotes.Split("/")
    for each emote in emoteList
        if emote <> ""
            parts = emote.Split(":")
            if parts.Count() >= 2
                value = { starts: [] }
                intervalList = parts[1].Split(",")
                for each interval in intervalList
                    range = interval.Split("-")
                    if range.Count() >= 2
                        value.starts.Push(Val(range[0]))
                        value.length = Val(range[1]) - Val(range[0]) + 1
                    end if
                end for
                emote_set[parts[0]] = value
            end if
        end if
    end for
    return emote_set
end function

' The chat badges come from helix/chat/badges, which returns
' data[].set_id and data[].versions[].id / .image_url_1x. The old
' badges.twitch.tv host no longer resolves.
function findBadgeImage(badges as object, set_id as string, version as string) as string
    if badges = invalid or badges.data = invalid
        return ""
    end if
    for each badge_set in badges.data
        if badge_set.set_id = set_id
            for each badge_version in badge_set.versions
                if badge_version.id = version
                    return badge_version.image_url_1x
                end if
            end for
        end if
    end for
    return ""
end function

sub onNewComment()
    m.chat.readyForNextComment = false
    parsed = parseIrcLine(m.chat.nextComment)
    tags = parsed.tags

    display_name = ""
    message = parsed.message
    color = ""
    badges = []
    emote_set = {}

    if tags.DoesExist("display-name")
        display_name = tags["display-name"]
    end if
    if tags.DoesExist("color")
        color = tags["color"]
        if Left(color, 1) = "#"
            color = Mid(color, 2)
        end if
    end if
    if tags.DoesExist("badges")
        badges = tags["badges"].Split(",")
    end if
    if tags.DoesExist("emotes")
        emote_set = parseEmotes(tags["emotes"])
    end if

    if InStr(parsed.params, " USERSTATE ") > 0
        m.userstate_change = true
    end if

    if display_name = "" or message = ""
        if m.userstate_change
            clientInfo = {}
            clientInfo.display_name = display_name
            clientInfo.color = color
            clientInfo.badges = badges
            'm.top.clientInfo.emotes = emotes
            clientInfo.emote_set = emote_set
            m.top.clientInfo = clientInfo
            m.userstate_change = false
        end if
        if m.chat.clientComment <> ""
            message = m.chat.clientComment
            display_name = m.top.clientInfo.display_name
            color = m.top.clientInfo.color
            badges = m.top.clientInfo.badges
            'emotes = m.top.clientInfo.emotes
            emote_set = m.top.clientInfo.emote_set
            m.chat.clientComment = ""
        else
            m.chat.readyForNextComment = true
            return
        end if
    end if

    group = createObject("roSGNode", "Group")
    group.visible = true
    group.translation = [5, m.translation]

    badge_translation = 0
    for each badge in badges
        if badge <> ""
            badge_parts = badge.Split("/")
            badge_image = findBadgeImage(m.global.channelBadges, badge_parts[0], badge_parts[1])
            if badge_image = ""
                badge_image = findBadgeImage(m.global.globalBadges, badge_parts[0], badge_parts[1])
            end if
            if badge_image <> ""
                poster = createObject("roSGNode", "Poster")
                poster.uri = badge_image
                poster.width = 18
                poster.height = 18
                poster.visible = true
                poster.translation = [badge_translation, 0]
                group.appendChild(poster)
                badge_translation += 20
            end if
        end if
    end for

    username = createObject("roSGNode", "SimpleLabel")
    username.text = display_name
    if color = ""
        color = "FFFFFF"
    end if
    username.color = "0x" + color + "FF"
    username.translation = [badge_translation, 0]
    username.visible = true
    username.fontSize = "14"
    username.fontUri = "pkg:/fonts/Inter-SemiBold.ttf"

    message_chars = message.Split(" ")

    username_width = username.localBoundingRect().width
    x_translation = badge_translation + username_width + 1
    y_translation = 0
    first_line = true
    appended_last_line = false

    message_text = createObject("roSGNode", "SimpleLabel")
    message_text.fontSize = "14"
    message_text.fontUri = "pkg:/fonts/Inter-Regular.ttf"
    message_text.visible = true
    message_text.text = ""

    colon = createObject("roSGNode", "SimpleLabel")
    colon.fontSize = "14"
    colon.fontUri = "pkg:/fonts/Inter-Regular.ttf"
    colon.color = "0xFFFFFFFF"
    colon.translation = [x_translation, y_translation]
    colon.visible = true
    colon.text = ":"

    currentWord = createObject("roSGNode", "SimpleLabel")
    currentWord.fontSize = "14"
    currentWord.fontUri = "pkg:/fonts/Inter-Regular.ttf"
    currentWord.color = "0xFFFFFFFF"
    currentWord.translation = [x_translation, y_translation]
    currentWord.visible = true
    currentWord.text = ""

    x_translation += 7

    word_number = 1
    char = 0
    for each word in message_chars
        appended_last_line = false
        is_emote = false

        currentWord.text = word

        width = message_text.localBoundingRect().width
        currentWordWidth = currentWord.localBoundingRect().width

        '? "Current word width ("; word; "): "; currentWordWidth; ", Total message width: "; width

        for each emote in emote_set.Items()
            for each start in emote.value.starts
                if start = char
                    message_text.translation = [x_translation, y_translation]
                    group.appendChild(message_text)

                    message_text = createObject("roSGNode", "SimpleLabel")
                    message_text.fontSize = "14"
                    message_text.fontUri = "pkg:/fonts/Inter-Regular.ttf"
                    message_text.visible = true
                    message_text.text = ""

                    x_translation += width

                    poster = createObject("roSGNode", "Poster")
                    poster.uri = "https://static-cdn.jtvnw.net/emoticons/v1/" + emote.key + "/1.0"
                    poster.visible = true
                    poster.translation = [x_translation, y_translation - 5]

                    group.appendChild(poster)

                    x_translation += 35

                    if x_translation >= 230 or word_number = message_chars.Count()
                        x_translation = 0
                        y_translation += 23
                    end if

                    is_emote = true
                    appended_last_line = true
                end if
            end for
        end for

        'for each emote in m.global.globalTTVEmotes
        if m.global.globalTTVEmotes <> invalid
            if m.global.globalTTVEmotes.DoesExist(word) and not is_emote
                message_text.translation = [x_translation, y_translation]
                group.appendChild(message_text)

                message_text = createObject("roSGNode", "SimpleLabel")
                message_text.fontSize = "14"
                message_text.fontUri = "pkg:/fonts/Inter-Regular.ttf"
                message_text.visible = true
                message_text.text = ""

                x_translation += width

                poster = createObject("roSGNode", "Poster")
                poster.uri = "https://cdn.betterttv.net/emote/" + m.global.globalTTVEmotes[word] + "/1x"
                poster.visible = true
                poster.translation = [x_translation, y_translation - 5]

                group.appendChild(poster)

                x_translation += 35

                if x_translation >= 230 or word_number = message_chars.Count()
                    x_translation = 0
                    y_translation += 23
                end if

                is_emote = true
                appended_last_line = true
            end if
        end if
        'end for

        if m.global.channelTTVFrankerEmotes <> invalid
            'for each emote in m.global.channelTTVFrankerEmotes
            if not is_emote
                if m.global.channelTTVFrankerEmotes.DoesExist(word)
                    message_text.translation = [x_translation, y_translation]

                    group.appendChild(message_text)

                    message_text = createObject("roSGNode", "SimpleLabel")
                    message_text.fontSize = "14"
                    message_text.fontUri = "pkg:/fonts/Inter-Regular.ttf"
                    message_text.visible = true
                    message_text.text = ""

                    x_translation += width

                    poster = createObject("roSGNode", "Poster")
                    poster.uri = m.global.channelTTVFrankerEmotes[word]
                    poster.visible = true
                    poster.translation = [x_translation, y_translation - 5]

                    group.appendChild(poster)

                    x_translation += 35

                    if x_translation >= 230 or word_number = message_chars.Count()
                        x_translation = 0
                        y_translation += 23
                    end if

                    is_emote = true
                    appended_last_line = true
                end if
            end if
        end if

        if not is_emote
            if (x_translation + currentWordWidth + width) < 230
                temp = message_text.text
                temp2 = word + " "
                temp.AppendString(temp2, Len(temp2))
                message_text.text = temp
                'appended_last_line = false
            else if (x_translation + currentWordWidth + width) >= 230
                if currentWordWidth >= 230
                    currentWordChars = word.Split("")
                    for each character in currentWordChars
                        width = message_text.localBoundingRect().width
                        appended_last_line = false
                        if width >= 230
                            message_text.translation = [x_translation, y_translation]
                            group.appendChild(message_text)

                            appended_last_line = true

                            message_text = createObject("roSGNode", "SimpleLabel")
                            message_text.fontSize = "14"
                            message_text.fontUri = "pkg:/fonts/Inter-Regular.ttf"
                            message_text.visible = true
                            message_text.text = ""

                            x_translation = 0
                            y_translation += 23
                        end if
                        message_text.text += character
                    end for
                else
                    message_text.translation = [x_translation, y_translation]
                    group.appendChild(message_text)

                    message_text = createObject("roSGNode", "SimpleLabel")
                    message_text.fontSize = "14"
                    message_text.fontUri = "pkg:/fonts/Inter-Regular.ttf"
                    message_text.visible = true
                    message_text.text = word

                    appended_last_line = false

                    x_translation = 0
                    y_translation += 23
                end if
                message_text.text += " "
            else
                ' message_text.translation = [ x_translation, y_translation ]
                ' group.appendChild(message_text)

                ' message_text = createObject("roSGNode", "SimpleLabel")
                ' message_text.fontSize = "14"
                ' message_text.fontUri = "pkg:/fonts/Inter-Regular.ttf"
                ' message_text.visible = true
                ' message_text.text = word + " "

                ' x_translation = 0
                ' y_translation += 28

                ' appended_last_line = true
            end if
        end if
        char += Len(word) + 1
        word_number += 1
    end for

    if not appended_last_line
        message_text.translation = [x_translation, y_translation]

        group.appendChild(message_text)

        y_translation += 32
    end if

    group.appendChild(username)
    ' group.appendChild(colon)

    m.chatPanel.appendChild(group)

    if m.translation + y_translation > 700
        for each chatmessage in m.chatPanel.getChildren(-1, 0)
            if chatmessage.translation[1] - y_translation < 0
                m.chatPanel.removeChild(chatmessage)
            else
                chatmessage.translation = [0, (chatmessage.translation[1] - y_translation)]
            end if
        end for
    else
        m.translation += y_translation
    end if

    '? "";display_name;": ";message
    'm.chat.clientComment = ""
    m.chat.readyForNextComment = true
end sub

function onKeyEvent(key, press) as boolean
    handled = false
    if press
        if key = "down" and m.keyboard.hasFocus()
            m.chatButton.color = "0xBD00FFFF"
            m.chatButton.setFocus(true)
            handled = true
        else if key = "down"
            m.chatButton.color = "0xBD00FFFF"
            m.chatButton.setFocus(true)
            handled = true
        else if key = "up" and m.chatButton.hasFocus()
            m.keyboard.setFocus(true)
            m.chatButton.color = "0x18181BFF"
            handled = true
        else if key = "OK" and m.chatButton.hasFocus()
            m.chat.sendMessage = m.keyboard.text
            m.keyboard.text = ""
            m.chatButton.visible = false
            m.keyboard.visible = false
            m.chatButton.color = "0x18181BFF"
            m.chatButton.setFocus(false)
            m.top.doneFocus = true
            handled = true
        else if key = "OK" and not m.keyboard.visible
            m.keyboard.visible = true
            m.chatButton.visible = true
            m.keyboard.setFocus(true)
        else if key = "back"
            m.keyboard.text = ""
            m.chatButton.visible = false
            m.keyboard.visible = false
            m.chatButton.color = "0x18181BFF"
            handled = true
            m.top.doneFocus = true
        end if
    end if
    return handled
end function
