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
    videoId = m.top.videoId
    if videoId = invalid or videoId = ""
        ? "GetPreviousLiveStreamVideo > getStreamLink > no video id"
        return ""
    end if
    waitForAppToken()

    token = getAccessToken()
    stream_link_url = getBackendBaseUrl() + "/getvod"
    url = newUrlTransfer()
    url.SetUrl(stream_link_url)

    port = CreateObject("roMessagePort")
    url.SetMessagePort(port)

    'TODO Reference the Options file instead of re-hardcoding it here
    videoQualities = ["1080p60","1080p","720p60","720p","480p","360p","160p"]
    videoQualityText = videoQualities[m.global.videoQuality]

    request = {
        "video_id": videoId,
        "access_token": token.EncodeUri(),
        "resolution": videoQualityText
    }

    url.AsyncPostFromString(FormatJson(request))
    msg = port.WaitMessage(0)
    response_string = msg.GetString()

    ? "GetPreviousLiveStreamVideo > getStreamLink > response received"
    response = ParseJson(response_string)

    if response = invalid
        ? "GetPreviousLiveStreamVideo > getStreamLink > invalid response"
        return ""
    end if

    stream_data = response.stream_data
    stream_quality = stream_data.streams[videoQualityText]
    ? "GetPreviousLiveStreamVideo > Stream Quality Text"
    ? videoQualityText
    ? "GetPreviousLiveStreamVideo > Stream Quality Url"
    ? redactUrl(stream_quality.master)
    link = stream_quality.master
    m.top.thumbnailInfo = { video_id: m.top.videoId }
    return link
end function

