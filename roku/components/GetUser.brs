
function init()

    sec = createObject("roRegistrySection", "LoggedInUserData")
    if sec.Exists("LoggedInUserName")
        m.top.loggedInUserName = sec.Read("LoggedInUserName")
    end if

    m.userProfiles = CreateObject("roAssociativeArray")
    m.top.functionName = "onSearchTextChange"
end function

function onSearchTextChange()
    m.top.searchResults = getUserSearchResults()
end function

function getProfilePicture(link)
    url = createUserUrl()
    if url = invalid
        ' No user token - there is no user scoped data to fetch.
        return ""
    end if
    'search_url = "https://api.twitch.tv/helix/users?id=" + user_id.ToStr()
    url.SetUrl(link.EncodeUri())
    '? "getProfilePicture > ";link.EncodeUri()
    response_string = url.GetToString()
    search = ParseJson(response_string)
    if search.data = invalid
        return ""
    end if
    for each profile in search.data
        m.userProfiles[profile.id] = resizeTwitchImageUrl(profile.profile_image_url, 50, 50)
    end for
end function

function getUserSearchResults(depth = 1) as object
    stream = lookupUserByLoginAuthed(m.top.loggedInUserName)
    if stream = invalid
        return {}
    end if
    if stream.status <> invalid and stream.status = 401
        ? "401 - GetUser"
        refreshToken(true)
        if depth < 3
            return getUserSearchResults(depth + 1)
        else
            ? "Failed to refresh token after 3 attempts"
            return {}
        end if
    end if

    result = {}
    result.id = stream.id
    result.login = stream.login
    result.display_name = stream.display_name
    result.profile_image_url = resizeTwitchImageUrl(stream.profile_image_url, 50, 50)

    if result.id = invalid
        ? "getUserSearchResults - Invalid result ID"
        return result
    end if

    url2 = createUserUrl()
    if url2 = invalid
        ' No user token - the followed streams list needs one.
        return result
    end if
    followed_streams_url = "https://api.twitch.tv/helix/streams/followed?user_id=" + result.id + "&first=100"
    url2.SetUrl(followed_streams_url.EncodeUri())
    response_string = url2.GetToString()
    '? "getUserSearchResults - getting followed streams with url: " + followed_streams_url
    '? "getUserSearchResults - response string: " + response_string
    followedstreamers = ParseJson(response_string)
    live_streamer_ids = {}
    result.followed_users = []


    if followedstreamers <> invalid and followedstreamers.data <> invalid
        user_ids_url = "https://api.twitch.tv/helix/users"
        addedUserIds = 0

        while true
            for each streamer in followedstreamers.data
                item = {}
                item.user_name = streamer.user_name
                item.viewer_count = streamer.viewer_count
                ' The streams response already carries the category name, so
                ' there is no need to resolve the id through helix/games - which
                ' also rejects the whole batch if any stream has no category.
                item.game_name = streamer.game_name
                if item.game_name = invalid
                    item.game_name = ""
                end if
                item.title = streamer.title
                item.thumbnail = resizeTwitchImageUrl(streamer.thumbnail_url, 320, 180)
                item.live_duration = formatElapsedHMS(secondsSinceISO8601(streamer.started_at))
                live_streamer_ids[streamer.user_id.ToStr()] = true

                ' The streams response carries the login too, so the login does
                ' not depend on the users batch succeeding.
                item.login = streamer.user_login
                if item.login = invalid
                    item.login = ""
                end if

                item.profile_image_url = streamer.user_id
                if addedUserIds = 0
                    user_ids_url += "?id=" + streamer.user_id.ToStr()
                    addedUserIds += 1
                else if addedUserIds < 100
                    user_ids_url += "&id=" + streamer.user_id.ToStr()
                    addedUserIds += 1
                else if addedUserIds = 100
                    getProfilePicture(user_ids_url)
                    user_ids_url = "https://api.twitch.tv/helix/users?id=" + streamer.user_id.ToStr()
                    addedUserIds = 1
                end if

                result.followed_users.push(item)
            end for

            ' Helix signals the last page either by omitting the cursor or by
            ' returning an empty one. An empty cursor is not invalid, so
            ' checking only for invalid would request the first page again
            ' and loop forever.
            cursor = invalid
            if followedstreamers.pagination <> invalid
                cursor = followedstreamers.pagination.cursor
            end if
            if cursor = invalid or cursor = ""
                exit while
            end if

            url2 = createUserUrl()
            if url2 = invalid
                exit while
            end if
            followed_streams_url = "https://api.twitch.tv/helix/streams/followed?user_id=" + result.id + "&first=100&after=" + cursor
            url2.SetUrl(followed_streams_url.EncodeUri())
            response_string = url2.GetToString()
            followedstreamers = ParseJson(response_string)
            if followedstreamers = invalid or followedstreamers.data = invalid
                exit while
            end if
        end while

        if addedUserIds > 0
            getProfilePicture(user_ids_url)
        end if
    end if

    for each streamer in result.followed_users
        ' profile_image_url is holding the user id until the avatar is resolved
        streamer.profile_image_url = m.userProfiles[streamer.profile_image_url]
        if streamer.profile_image_url = invalid
            streamer.profile_image_url = ""
        end if
    end for

    result.followed_users.SortBy("viewer_count", "r")

    m.top.currentlyLiveStreamerIds = live_streamer_ids
    '? "currentlyLiveStreamerIds getuser " m.top.currentlyLiveStreamerIds

    return result
end function