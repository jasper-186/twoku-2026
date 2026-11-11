function init()
    m.top.functionName = "onStreamerChange"
end function

function onStreamerChange()

    stream_link = getStreamLink()

    m.top.streamUrl = stream_link

end function

sub extractThumbnailUrl(streamUrl)
    index = Len(streamUrl)
    secondSlash = false
    while index > 0
        if Mid(streamUrl, index, 1) = "/"
            if secondSlash
                info_url = Mid(streamUrl, 1, index - 1) + "/storyboards/"
                url = createUrl()
                url.SetUrl(info_url + m.top.videoId + "-info.json")
                ? "video info url > "; info_url + m.top.videoId + "-info.json"
                response_string = url.GetToString()
                thumbnailInfo = ParseJson(response_string)
                if thumbnailInfo <> invalid and thumbnailInfo[0] <> invalid
                    url2 = createUrl()
                    url2.SetUrl(info_url + thumbnailInfo[1].images[0])
                    ? "image url: "; info_url + thumbnailInfo[1].images[0]
                    m.top.thumbnailInfo = { count: thumbnailInfo[1].count,
                                            width: thumbnailInfo[1].width,
                                            rows: thumbnailInfo[1].rows,
                                            interval: thumbnailInfo[1].interval,
                                            cols: thumbnailInfo[1].cols,
                                            height: thumbnailInfo[1].height,
                                            info_url: info_url,
                                            thumbnail_parts: thumbnailInfo[1].images,
                                            video_id: m.top.videoId }
                else
                    m.top.thumbnailInfo = { video_id: m.top.videoId }
                end if
                exit while
            end if
            secondSlash = true
        end if
        index -= 1
    end while
end sub

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

    ? "GetPreviousLiveStreamVideo > getStreamLink > response: " + response_string
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
    ? stream_quality.master
    link = stream_quality.master
    extractThumbnailUrl(link)
    return link
end function

