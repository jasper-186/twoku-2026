function init()
    m.top.functionName = "onStreamerChange"
end function

function onStreamerChange()

    stream_link = getStreamLink()
    m.top.streamUrl = stream_link

end function

function getAccessToken() as Object
    waitForAppToken()
    waitForUserToken()

    userToken = m.global.userToken
    if userToken <> ""
        return userToken
    else
        return m.global.appBearerToken
    end if
end function


function getStreamLink() as Object
    requestedStreamer = m.top.streamerRequested
    if requestedStreamer = invalid or requestedStreamer = ""
        ? "No streamer requested"
        return ""
    end if
    waitForAppToken()

    if m.top.streamerUserId = invalid or strtoi(m.top.streamerUserId) = 0
        ? "Filling streamer user id..."
        m.top.streamerUserId = getUserIdFromLogin(requestedStreamer)
    end if

    token = getAccessToken()
    stream_link_url = getBackendBaseUrl() + "/getlivestream"
    '? "Requesting stream link for " + requestedStreamer
    url = newUrlTransfer()
    url.SetUrl(stream_link_url)

    port = CreateObject("roMessagePort")
    url.SetMessagePort(port)
    
    'TODO Reference the Options file instead of re-hardcoding it here
    videoQualities = ["1080p60","1080p","720p60","720p","480p","360p","160p"]
    videoQualityText = videoQualities[m.global.videoQuality]
    
    request = {
        "twitch_channel": requestedStreamer,
        "access_token": token.EncodeUri(),
        "resolution": videoQualityText
        '"resolution": "720p60"
    }
    
    url.AsyncPostFromString(FormatJson(request))
    msg = port.WaitMessage(0)
    response_string =msg.GetString()

    '? "getStreamLink response: " + response_string
    response = ParseJson(response_string)
    '? response
    
    stream_data = response.stream_data
    stream_quality = stream_data.streams[videoQualityText]
    ? "Stream Quality Text"
    ? videoQualityText
    ? "Stream Quality Url"
    ? stream_quality.master
    return stream_quality.master
end function


function getUserIdFromLogin(login as String) as Integer
    user = lookupUserByLogin(login)
    if user = invalid
        return 0
    end if
    if user.status <> invalid and user.status = 401
        ? "401 - GetUser"
        return 0
    end if
    ? "Found user id " + user.id + " with login " + user.login + " for login " + login
    return strtoi(user.id)
end function