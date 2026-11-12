
function init()
    m.top.functionName = "onSearchTextChange"
end function

function onSearchTextChange()

    m.top.searchResults = getSearchResults()

end function

function getGameNameFromId(id as String)
    game_info = GETJSON("https://api.twitch.tv/helix/games?id=" + id)
    if game_info <> invalid and game_info.data <> invalid and game_info.data[0] <> invalid
        return game_info.data[0].name
    end if
    return id
end function

function getSearchResults(depth = 1) as Object
    stream = lookupUserByLogin(m.top.loginRequested)
    if stream <> invalid and stream.status <> invalid and stream.status = 401
        ? "401 - GetChannel"
        refreshToken(true)
        if depth < 3
            return getSearchResults(depth + 1)
        else
            ? "Failed to refresh token after 3 attempts"
            return {}
        end if
    end if

    result = {}

    if stream <> invalid
        result.id = stream.id
        result.display_name = stream.display_name
        result.description = stream.description

        result.profile_image_url = resizeTwitchImageUrl(stream.profile_image_url, 50, 50)
        result.offline_image_url = resizeTwitchImageUrl(stream.offline_image_url, 896, 504)
    end if

    search_results_url = "https://api.twitch.tv/helix/streams?user_login=" + m.top.loginRequested

    url = createUrl()
    url.SetUrl(search_results_url.EncodeUri())

    response_string = url.GetToString()
    search = ParseJson(response_string)

    if search <> invalid and search.data <> invalid and search.data[0] <> invalid
        stream = search.data[0]

        result.title = stream.title
        result.thumbnail_url = resizeTwitchImageUrl(stream.thumbnail_url, 896, 504)
        result.game = getGameNameFromId(stream.game_id)
        elapsedSeconds = secondsSinceISO8601(stream.started_at)
        m.top.streamDurationSeconds = elapsedSeconds
        result.live_duration = formatElapsedHMS(elapsedSeconds)
        ? "get viewer count > " stream.viewer_count
        result.viewer_count = formatCountAbbrev(stream.viewer_count) + " viewers"

        result.is_live = true
    else
        result.is_live = false
    end if

    search_results_url = "https://api.twitch.tv/helix/users/follows?first=1&to_id=" + result.id

    url = createUrl()
    url.SetUrl(search_results_url.EncodeUri())

    response_string = url.GetToString()
    search = ParseJson(response_string)

    if search <> invalid and search.total <> invalid
        result.followers = formatCountAbbrev(search.total) + " followers"
    else
        result.followers = "0 followers"
    end if

    return result
end function