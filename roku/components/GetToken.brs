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

    ? "GetToken response: " + response_string
    response = ParseJson(response_string)
    return response
end function