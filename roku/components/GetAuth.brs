function init()
    m.top.functionName = "onStreamerChange"
end function

function onStreamerChange()

    stream_link = getStreamLink()

    m.top.finished = true

end function

function getStreamLink() as Object
    m.top.finished = false

    enter_code_url = getBackendBaseUrl() + "/register"

    url = newUrlTransfer()
    url.SetUrl(enter_code_url)
    response_string = url.GetToString()
    ? "getAuth enter code received (" + Len(response_string).ToStr() + " chars)"
    m.top.code = response_string

    url = newUrlTransfer()
    url.SetUrl(getBackendBaseUrl() + "/unregister")
    port = CreateObject("roMessagePort")
    url.SetMessagePort(port)

    while true
        url.AsyncPostFromString("{""code"": """ + response_string + """}")
        msg = port.WaitMessage(0)
        response_text = msg.GetString()
        res = ParseJson(response_text)
        if res <> invalid and res.DoesExist("access_token")
            exit while
        end if
        ?"GetAuth - getStreamLink - msg: " + response_text
        sleep(5000)
    end while

    oauth_token = ParseJson(response_text)
    ?"GetAuth - getStreamLink - msg: " + redactToken(oauth_token.access_token)

    url = newUrlTransfer()
    url.SetUrl("https://id.twitch.tv/oauth2/validate")
    url.AddHeader("Authorization", "Bearer " + oauth_token.access_token)

    response_string = url.GetToString()
    response = ParseJson(response_string)

    ? "GetAuth - getStreamLink - response: " + response_string
    saveLogin(oauth_token.access_token, oauth_token.refresh_token, response.login)

    return ""
end function
