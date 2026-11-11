
function init()
    m.top.functionName = "onSearchTextChange"
end function

function onSearchTextChange()

    m.top.searchResults = getSearchResults()

end function

function getSearchResults() as Object
    search_results_url = "https://api.twitch.tv/helix/search/categories?query=" + m.top.searchText + "&first=5"

    search = GETJSON(search_results_url)

    result = []
    if search <> invalid and search.data <> invalid
        for each game in search.data
            item = {}
            item.id = game.id
            item.name = game.name
            item.logo = game.box_art_url
            result.push(item)
        end for
    end if

    return result
end function