
function init()
    m.top.functionName = "onSearchTextChange"
end function

function onSearchTextChange()
    m.top.offlineFollowedUsers = getOfflineFollowedChannelsSearchResults()
end function


function getOfflineFollowedChannelsSearchResults() as Object
    ? "GetOfflineFollowedChannels > getOfflineFollowedChannelsSearchResults > called"
    offlineFollowedStreamers = []
    if m.top.loggedInUserName = invalid or m.top.loggedInUserName = ""
        return offlineFollowedStreamers
    end if

    if m.top.currentlyLiveStreamerIds = invalid
        ' Without the live streamer ids there is no way to tell which of the
        ' followed channels are actually offline.
        ? "GetOfflineFollowedChannels > no live streamer ids - skipping offline channels"
        return offlineFollowedStreamers
    end if

    current_user = lookupUserByLoginAuthed(m.top.loggedInUserName)
    if current_user = invalid or current_user.id = invalid
        ? "GetOfflineFollowedChannels > getOfflineFollowedChannelsSearchResults > failed to get current user info"
        return offlineFollowedStreamers
    end if

    user_id = current_user.id
    followed_channels_url = "https://api.twitch.tv/helix/channels/followed?user_id=" + user_id + "&first=100"
    '? "GetOfflineFollowedChannels > getOfflineFollowedChannelsSearchResults > getting followed channels with url: " + followed_channels_url

    followed_channels_url_call = createUserUrl()
    if followed_channels_url_call = invalid
        ' No user token - following channels needs one.
        return offlineFollowedStreamers
    end if
    followed_channels_url_call.SetUrl(followed_channels_url)
    response_string = followed_channels_url_call.GetToString()
    '? "GetOfflineFollowedChannels > getOfflineFollowedChannelsSearchResults > followed_channels response received, response " + response_string

    followed_channels = ParseJson(response_string)
    addedUsers = 0
    streamer_info_url = "https://api.twitch.tv/helix/users"

    while followed_channels <> invalid and followed_channels.data <> invalid
        for each follow in followed_channels.data
            if not m.top.currentlyLiveStreamerIds.DoesExist(follow.broadcaster_id)
                if addedUsers = 0
                    streamer_info_url += "?id=" + follow.broadcaster_id
                else
                    streamer_info_url += "&id=" + follow.broadcaster_id
                end if
                addedUsers += 1
            end if

            if addedUsers = 100
                ? "GetOfflineFollowedChannels > getOfflineFollowedChannelsSearchResults > added 100 users, making API call to get their info"
                offline_streamer_info = GETJSON(streamer_info_url)
                for each offline_streamer in offline_streamer_info.data
                    streamer_info = {}
                    streamer_info.login = offline_streamer.login
                    streamer_info.display_name = offline_streamer.display_name
                    streamer_info.profile_image_url = resizeTwitchImageUrl(offline_streamer.profile_image_url, 150, 150)
                        '? "Pushing to offlineFollowedStreamers: " + streamer_info.login
                    offlineFollowedStreamers.push(streamer_info)
                end for
                addedUsers = 0
                streamer_info_url = "https://api.twitch.tv/helix/users"
            end if
        end for

        ' Helix signals the last page either by omitting the cursor or by
        ' returning an empty one. An empty cursor is not invalid, so checking
        ' only for invalid would request the first page again and loop forever.
        cursor = invalid
        if followed_channels.pagination <> invalid
            cursor = followed_channels.pagination.cursor
        end if
        if cursor = invalid or cursor = ""
            exit while
        end if
        followed_channels = GETJSON("https://api.twitch.tv/helix/channels/followed?user_id=" + user_id + "&first=100&after=" + cursor)
    end while

    '? "GetOfflineFollowedChannels > getOfflineFollowedChannelsSearchResults > finished processing followed channels, total added users: " + addedUsers.ToStr()
    if addedUsers > 0
        offline_streamer_info = GETJSON(streamer_info_url)
        for each offline_streamer in offline_streamer_info.data
            streamer_info = {}
            streamer_info.login = offline_streamer.login
            streamer_info.display_name = offline_streamer.display_name
            streamer_info.profile_image_url = resizeTwitchImageUrl(offline_streamer.profile_image_url, 150, 150)
            '? "Pushing to offlineFollowedStreamers: " + streamer_info.login
            offlineFollowedStreamers.push(streamer_info)
        end for
    end if

    return offlineFollowedStreamers
end function