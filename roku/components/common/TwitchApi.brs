' Returns the raw data[0] assoc array from helix/users?login=<x>, or invalid.
' Uses createUrl() (app-token fallback). 401 propagates as data.status = 401 in the returned wrapper;
' callers decide whether to refresh + retry.
function lookupUserByLogin(login as String) as Object
    search_results_url = "https://api.twitch.tv/helix/users?login=" + login
    url = createUrl()
    if url = invalid
        return invalid
    end if
    url.SetUrl(search_results_url.EncodeUri())
    response_string = url.GetToString()
    parsed = ParseJson(response_string)
    if parsed = invalid
        return invalid
    end if
    if parsed.status <> invalid and parsed.status = 401
        return { status: 401 }
    end if
    if parsed.data = invalid or parsed.data.Count() = 0
        return invalid
    end if
    return parsed.data[0]
end function

' Populates m.global.globalTTVEmotes (BTTV global emotes keyed by code) if not already set.
sub ensureGlobalBTTVEmotes()
    if m.global.globalTTVEmotes <> invalid
        return
    end if
    temp = GETJSON("https://api.betterttv.net/3/cached/emotes/global")
    assocEmotes = {}
    for each emote in temp
        assocEmotes[emote.code] = emote.id
    end for
    m.global.addFields({ globalTTVEmotes: assocEmotes })
end sub

' Populates m.global.channelTTVEmotes (BTTV channel-shared emotes keyed by code).
' Overwrites on subsequent channel switches.
sub ensureChannelBTTVEmotes(channelId as String)
    temp = GETJSON("https://api.betterttv.net/3/cached/users/twitch/" + channelId)
    assocEmotes = {}
    for each emote in temp.sharedEmotes
        assocEmotes[emote.code] = emote.id
    end for
    if m.global.channelTTVEmotes = invalid
        m.global.addFields({channelTTVEmotes: assocEmotes})
    else
        m.global.setField("channelTTVEmotes", assocEmotes)
    end if
end sub

' Populates m.global.channelTTVFrankerEmotes (FFZ channel emotes keyed by code → 1x image URL).
sub ensureChannelFFZEmotes(channelId as String)
    temp = GETJSON("https://api.betterttv.net/3/cached/frankerfacez/users/twitch/" + channelId)
    assocEmotes = {}
    for each emote in temp
        assocEmotes[emote.code] = emote.images["1x"]
    end for
    if m.global.channelTTVFrankerEmotes = invalid
        m.global.addFields({channelTTVFrankerEmotes: assocEmotes})
    else
        m.global.setField("channelTTVFrankerEmotes", assocEmotes)
    end if
end sub

' Same as lookupUserByLogin but uses createUserUrl() (returns invalid when anonymous).
function lookupUserByLoginAuthed(login as String) as Object
    search_results_url = "https://api.twitch.tv/helix/users?login=" + login
    url = createUserUrl()
    if url = invalid
        return invalid
    end if
    url.SetUrl(search_results_url.EncodeUri())
    response_string = url.GetToString()
    parsed = ParseJson(response_string)
    if parsed = invalid
        return invalid
    end if
    if parsed.status <> invalid and parsed.status = 401
        return { status: 401 }
    end if
    if parsed.data = invalid or parsed.data.Count() = 0
        return invalid
    end if
    return parsed.data[0]
end function
