
function init()
    m.top.functionName = "onSearchTextChange"
end function

function onSearchTextChange()

    m.top.searchResults = getSearchResults()

end function

function getSearchResults() as Object
    search_results_url = "https://api.twitch.tv/helix/search/channels?query=" + m.top.searchText + "&limit=5"

    search = GETJSON(search_results_url)

    ' ? "wtf is hjappenign: " search.data[0]

    result = []
    if search <> invalid and search.data <> invalid
        for each channel in search.data
            ? "SEARCH: " channel
            item = {}
            item.id = channel.id
            item.login = channel.broadcaster_login
            item.name = channel.display_name
            if channel.thumbnail_url <> invalid
                item.logo = resizeTwitchImageUrl(channel.thumbnail_url, 50, 50)
            end if
            result.push(item)
        end for
    end if

    return result
end function