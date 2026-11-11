function createUrl()
    ? "Creating URL object"
    url = newUrlTransfer()

    waitForAppToken()
    waitForUserToken()

    ' Wait until we have an app token, as it also sets the client id which is required for all requests
    url.AddHeader("Client-ID", m.global.appClientId)
    ? "AuthHeader: Client-ID " + m.global.appClientId
    userToken = m.global.userToken
    if userToken <> ""
        ? "Found UserToken:"
        ? "UserToken: " userToken
        ? "AuthHeader: Authorization Bearer " + userToken
        url.AddHeader("Authorization", "Bearer " + userToken)
    else
        ? "No UserToken found, using app token"
        ? "AuthHeader: Authorization Bearer " + m.global.appBearerToken
        url.AddHeader("Authorization", "Bearer " + m.global.appBearerToken)
    end if
    return url
end function

function createUserUrl()

    waitForUserToken()

    userToken = m.global.userToken
    if userToken = ""
        return invalid
    end if

    ? "Creating User URL object"
    url = newUrlTransfer()

    waitForAppToken()

    ' Wait until we have an app token, as it also sets the client id which is required for all requests
    url.AddHeader("Client-ID", m.global.appClientId)
    ? "AuthHeader: Client-ID " + m.global.appClientId
    ? "AuthHeader: Authorization Bearer " + userToken
    url.AddHeader("Authorization", "Bearer " + userToken)
    return url
end function

function GETJSON(link as String) as Object
    url = createUrl()
    url.SetUrl(link.EncodeUri())

    response_string = url.GetToString()

    if response_string = invalid or response_string = ""
        ? "GETJSON return empty object for: " + link
        return {}
    end if
    return ParseJson(response_string)
end function

function validateToken(token as string) as Object
    ? "Validating token: " + token
    url = newUrlTransfer()
    url.SetUrl("https://id.twitch.tv/oauth2/validate")
    url.AddHeader("Authorization", "Bearer " + token)
    response_string = url.GetToString()
    ? "Validating token Response: " + response_string
    response = ParseJson(response_string)
    if response.status <> invalid and response.status = 401
        ? "Token is invalid"
        return invalid
    else
        ? "Token is valid"
        return true
    end if
end function


function refreshToken() as void
    ? "Refreshing user token..."
    refreshUserToken()
    ? "Refreshing app token..."
    refreshAppToken()
end function

function refreshAppToken() as void
    ' The app token is fetched by GetToken on its own thread. Wait for it
    ' rather than validating a token that has not arrived yet - passing an
    ' unset token to validateToken is a type error, and it takes the app down
    ' before it has even started.
    waitForAppToken()
    ? "Validating app token..."
    if validateToken(m.global.appBearerToken) <> invalid
        ? "App token is still valid, skipping refresh"
        return
    end if

    ? "Refreshing app token..."
    access_token_url = getBackendBaseUrl() + "/apptoken"
    url = newUrlTransfer()
    url.SetUrl(access_token_url)
    response_string = url.GetToString()

    ? "GetToken[refresh] response: " + response_string
    response = ParseJson(response_string)

    ' m.top is the task this runs in, not the scene, so writing the token
    ' there dropped it on the floor. The app reads it from the global field.
    m.global.setField("appBearerToken", response.access_token)
end function

function refreshUserToken() as void
    sec = createObject("roRegistrySection", "LoggedInUserData")
    if NOT sec.Exists("UserToken") or sec.Read("UserToken") = ""
         ? "No user token found, skipping refresh"
         return
    end if
    ? "Validating user token..."
    if validateToken(sec.Read("UserToken")) <> invalid
        ? "User token is still valid, skipping refresh"
        return
    end if
    url = newUrlTransfer()
    url.SetUrl(getBackendBaseUrl() + "/refresh")
    port = CreateObject("roMessagePort")
    url.SetMessagePort(port)
    token = getUserRefreshToken()
    if token = ""
        ? "No refresh token found, cannot refresh"
        clearLogin()
        return
    end if
    url.AsyncPostFromString("code=" + token)
    msg = port.WaitMessage(0)
    ? "Refresh response: " + msg.GetString()
    oauth_token = ParseJson(msg.GetString())
    if oauth_token = invalid or oauth_token.access_token = invalid or oauth_token.refresh_token = invalid
        ? "Invalid tokens received during refresh"
        clearLogin()
        return
    end if
    url = newUrlTransfer()
    url.SetUrl("https://id.twitch.tv/oauth2/validate")
    url.AddHeader("Authorization", "Bearer " + oauth_token.access_token)
    res = url.GetToString()
    ? "Response: " + res
    response = ParseJson(res)

    saveLogin(oauth_token.access_token, oauth_token.refresh_token, response.login, response.user_id)
end function

function getUserRefreshToken()
    sec = createObject("roRegistrySection", "LoggedInUserData")
    if sec.Exists("RefreshToken")
        return sec.Read("RefreshToken")
    end if
    return ""
end function

function saveLogin(access_token, refresh_token, login, user_id = "") as void
    sec = createObject("roRegistrySection", "LoggedInUserData")
    sec.Write("UserToken", access_token)
    sec.Write("RefreshToken", refresh_token)
    sec.Write("LoggedInUserName", login)
    if user_id <> ""
        sec.Write("LoggedInUserId", user_id)
    end if
    ? "Setting user token: " + access_token
    m.global.setField("userToken", access_token)
    sec.Flush()
end function

function clearLogin() as void
    ? "Clearing user login data..."
    sec = createObject("roRegistrySection", "LoggedInUserData")
    if sec.Exists("UserToken")
        sec.Delete("UserToken")
    end if
    if sec.Exists("RefreshToken")
        sec.Delete("RefreshToken")
    end if
    if sec.Exists("LoggedInUserName")
        sec.Delete("LoggedInUserName")
    end if
    if sec.Exists("LoggedInUserId")
        sec.Delete("LoggedInUserId")
    end if
    if sec.Exists("Reset")
        sec.Delete("Reset")
    end if
    sec.Flush()

    m.global.setField("userToken", invalid)
    m.login = ""
    m.getUser.loggedInUserName = ""
    m.homeScene.loggedInUserName = ""
    m.homeScene.loggedInUserProfileImage = ""
    m.chat.loggedInUserName = ""
end function

