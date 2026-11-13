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

function refreshUserToken() as void
    ' Only one refresh at a time. Several tasks can find the token expired
    ' at once, and every refresh rotates the refresh token - so a second
    ' one spends a token the first one has already replaced.
    waited = 0
    while m.global.tokenRefreshInProgress = true and waited < 15000
        sleep(200)
        waited = waited + 200
    end while
    m.global.setField("tokenRefreshInProgress", true)

    sec = createObject("roRegistrySection", "LoggedInUserData")
    if NOT sec.Exists("UserToken") or sec.Read("UserToken") = ""
        m.global.setField("tokenRefreshInProgress", false)
         ? "No user token found, skipping refresh"
         return
    end if

    storedToken = sec.Read("UserToken")
    ? "Validating user token..."
    if validateToken(storedToken) <> invalid
        m.global.setField("tokenRefreshInProgress", false)
        ? "User token is still valid, skipping refresh"
        ' The token in use can be an older one that a refresh elsewhere has
        ' already replaced, so take the stored one.
        m.global.setField("userToken", storedToken)
        return
    end if

    url = newUrlTransfer()
    url.SetUrl(getBackendBaseUrl() + "/refresh")
    port = CreateObject("roMessagePort")
    url.SetMessagePort(port)
    token = getUserRefreshToken()
    if token = ""
        m.global.setField("tokenRefreshInProgress", false)
        ? "No refresh token found, cannot refresh"
        clearLogin()
        return
    end if
    url.AsyncPostFromString("code=" + token)
    msg = port.WaitMessage(0)
    if msg = invalid
        m.global.setField("tokenRefreshInProgress", false)
        ? "No response from the backend - keeping the stored login"
        return
    end if
    response_text = msg.GetString()
    oauth_token = ParseJson(response_text)
    if oauth_token = invalid
        m.global.setField("tokenRefreshInProgress", false)
        ? "Could not read the refresh response - keeping the stored login"
        return
    end if
    if oauth_token.access_token = invalid or oauth_token.refresh_token = invalid
        m.global.setField("tokenRefreshInProgress", false)
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
    ' The flag is held until the new token is stored, so that a task waiting
    ' for it finds the new token rather than the one that just expired.
    m.global.setField("tokenRefreshInProgress", false)
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

