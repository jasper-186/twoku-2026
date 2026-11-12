function init()
    m.top.functionName = "onStreamerChange"
end function

function onStreamerChange()
    appCredentials = getAppCredentials()
    m.top.appClientId = appCredentials.client_id
    m.top.appBearerToken = appCredentials.access_token
end function

function getAppCredentials() as Object
    access_token_url = getBackendBaseUrl() + "/apptoken"

    url = newUrlTransfer()
    url.SetUrl(access_token_url)
    
    response_string = url.GetToString()

    response = ParseJson(response_string)
    if response <> invalid and response.access_token <> invalid
        ? "GetToken response: " + redactToken(response.access_token)
    else
        ? "GetToken response: no access token"
    end if
    return response
end function
