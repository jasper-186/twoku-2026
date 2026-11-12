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
        ? "UserToken: " + redactToken(userToken)
        ? "AuthHeader: Authorization Bearer " + redactToken(userToken)
        url.AddHeader("Authorization", "Bearer " + userToken)
    else
        ? "No UserToken found, using app token"
        ? "AuthHeader: Authorization Bearer " + redactToken(m.global.appBearerToken)
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
    ? "AuthHeader: Authorization Bearer " + redactToken(userToken)
    url.AddHeader("Authorization", "Bearer " + userToken)
    return url
end function

' A one-shot GET with no credentials attached. Third party APIs have no
' business seeing the Twitch token, so they get this instead of GETJSON.
function GETJSONPublic(link as String) as Object
    url = newUrlTransfer()
    url.SetUrl(link.EncodeUri())

    response_string = url.GetToString()

    if response_string = invalid or response_string = ""
        ? "GETJSONPublic return empty object for: " + link
        return {}
    end if

    parsed = ParseJson(response_string)
    if parsed = invalid
        ? "GETJSONPublic could not parse the response for: " + link
        return {}
    end if
    return parsed
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
    ? "Validating token: " + redactToken(token)
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


function refreshToken(force = false) as void
    ? "Refreshing user token..."
    refreshUserToken(force)
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

    response = ParseJson(response_string)
    if response <> invalid and response.access_token <> invalid
        ? "GetToken[refresh] response: " + redactToken(response.access_token)
    else
        ? "GetToken[refresh] response: no access token"
    end if

    ' m.top is the task this runs in, not the scene, so writing the token
    ' there dropped it on the floor. The app reads it from the global field.
    m.global.setField("appBearerToken", response.access_token)
end function

function refreshUserToken(force = false) as void
    sec = createObject("roRegistrySection", "LoggedInUserData")
    if NOT sec.Exists("UserToken") or sec.Read("UserToken") = ""
         ? "No user token found, skipping refresh"
         return
    end if
    ' A caller that got a 401 has already proved the token it used is no
    ' good. The stored token may have been replaced by a refresh that landed
    ' in the meantime, so the validity check alone would skip the refresh
    ' and retry with the same token.
    if NOT force
        ? "Validating user token..."
        if validateToken(sec.Read("UserToken")) <> invalid
            ? "User token is still valid, skipping refresh"
            return
        end if
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
    if msg = invalid
        ? "No response from the backend - keeping the stored login"
        return
    end if
    response_text = msg.GetString()
    oauth_token = ParseJson(response_text)
    if oauth_token = invalid
        ? "Could not read the refresh response - keeping the stored login"
        return
    end if
    if oauth_token.access_token = invalid or oauth_token.refresh_token = invalid
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

    saveLogin(oauth_token.access_token, oauth_token.refresh_token, response.login)
end function

function getUserRefreshToken()
    sec = createObject("roRegistrySection", "LoggedInUserData")
    if sec.Exists("RefreshToken")
        return sec.Read("RefreshToken")
    end if
    return ""
end function

function saveLogin(access_token, refresh_token, login) as void
    sec = createObject("roRegistrySection", "LoggedInUserData")
    sec.Write("UserToken", access_token)
    sec.Write("RefreshToken", refresh_token)
    sec.Write("LoggedInUserName", login)
    ? "Setting user token: " + redactToken(access_token)
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
    if sec.Exists("Reset")
        sec.Delete("Reset")
    end if
    sec.Flush()

    ' The empty string is the anonymous state. "invalid" is the state that
    ' means the token has not been set yet, and waitForUserToken() spins on
    ' it - leaving it there would wedge every request that follows.
    m.global.setField("userToken", "")

    ' These nodes live on MainScene. The tasks that call this do not have
    ' them, so only touch the ones that are actually there.
    if m.login <> invalid
        m.login = ""
    end if
    if m.getUser <> invalid
        m.getUser.loggedInUserName = ""
    end if
    if m.homeScene <> invalid
        m.homeScene.loggedInUserName = ""
        m.homeScene.loggedInUserProfileImage = ""
    end if
    if m.chat <> invalid
        m.chat.loggedInUserName = ""
    end if
end function

