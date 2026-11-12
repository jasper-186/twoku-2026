
function init()
    'm.DURATION_REGEX = createObject("roRegex", "h|m|s", "")
    m.top.functionName = "onSearchTextChange"
end function

function onSearchTextChange()

    m.top.searchResults = getSearchResults()

end function

function getRelativeTimePublished(timePublished as String) as String
    secondsSincePublished = createObject("roDateTime")
    secondsSincePublished.FromISO8601String(timePublished)
    currentTime = createObject("roDateTime").AsSeconds()
    elapsedTime = currentTime - secondsSincePublished.AsSeconds()

    elapsedTime = Int(elapsedTime / 60)
    if elapsedTime < 60
        if elapsedTime = 1
            return "1 minute ago"
        else
            return elapsedTime.ToStr() + " minutes ago"
        end if
    end if

    elapsedTime = Int(elapsedTime / 60)
    if elapsedTime < 24
        if elapsedTime = 1
            return "1 hour ago"
        else
            return elapsedTime.ToStr() + " hours ago"
        end if
    end if

    elapsedTime = Int(elapsedTime / 24)
    if elapsedTime < 30
        if elapsedTime = 1
            return "1 day ago"
        else
            return elapsedTime.ToStr() + " days ago"
        end if
    end if

    elapsedTime = Int(elapsedTime / 30)
    if elapsedTime < 12
        if elapsedTime = 1
            return "Last month"
        else
            return elapsedTime.ToStr() + " months ago"
        end if
    end if

    elapsedTime = Int(elapsedTime / 12)
    if elapsedTime = 1
        return "1 year ago"
    else
        return elapsedTime.ToStr() + " years ago"
    end if
    
end function

function convertDurationFormat(org_duration as String) as String
    new_duration = ""
    DURATION_REGEX = createObject("roRegex", "h|m|s", "")
    
    values = DURATION_REGEX.Split(org_duration)
    values_length = values.Count()


    for number = 0 to values_length - 1
        if values[number].Len() = 1 and not (number = 0 and values_length = 3)
            values[number] = "0" + values[number]
        end if
    end for

    if values_length = 3
        new_duration = values[0] + ":" + values[1] + ":" + values[2]
    else if values_length = 2
        new_duration = values[0] + ":" + values[1]
    else if values_length = 1
        new_duration = "0" + ":" + values[0]
    end if

    return new_duration
end function

function getSearchResults(depth = 1) as Object
    search_results_url = "https://api.twitch.tv/helix/videos?user_id=" + m.top.userId

    url = createUrl()
    
    'url.SetUrl(search_results_url.EncodeUri() + m.top.gameRequested.EncodeUriComponent())

    if m.top.pagination <> ""
        search_results_url = search_results_url + m.top.pagination
    end if

    url.SetUrl(search_results_url.EncodeUri())

    response_string = url.GetToString()
    search = ParseJson(response_string)

    if search.status <> invalid and search.status = 401
        ? "401 - GetVideos"
        ? "401 - Response string: " + response_string
        refreshToken(true)
        if depth < 3
            return getSearchResults(depth + 1)
        else
            ? "Failed to refresh token after 3 attempts"
            return []
        end if
    end if

    result = []
    if search <> invalid and search.data <> invalid
        for each video in search.data
            item = {}
            item.id = video.id
            item.user_name = video.user_name
            item.duration = convertDurationFormat(video.duration)
            item.title = video.title
            item.published_at = getRelativeTimePublished(video.published_at)
            item.viewer_count = formatCountAbbrev(video.view_count) + " views"
            item.thumbnail_url = resizeTwitchImageUrl(video.thumbnail_url, 320, 180)
            result.push(item)
        end for
    end if

    if search.pagination <> invalid and search.pagination.cursor <> invalid
        m.top.pagination = "&after=" + search.pagination.cursor
    end if

    return result
end function