function newUrlTransfer() as Object
    url = CreateObject("roUrlTransfer")
    url.EnableEncodings(true)
    url.RetainBodyOnError(true)
    url.SetCertificatesFile("common:/certs/ca-bundle.crt")
    url.InitClientCertificates()
    return url
end function

sub waitForAppToken()
    ' These are busy waits, so say it once rather than on every pass - the
    ' console cannot keep up and the spin burns a core.
    if m.global.appClientId = invalid
        ? "Waiting for app client id to be set..."
    end if
    while m.global.appClientId = invalid
        sleep(1)
    end while
    if m.global.appBearerToken = invalid
        ? "Waiting for app bearer token to be set..."
    end if
    while m.global.appBearerToken = invalid
        sleep(1)
    end while
end sub

sub waitForUserToken()
    if m.global.userToken = invalid
        ? "Waiting for user token to be set..."
    end if
    while m.global.userToken = invalid
        sleep(1)
    end while
end sub

' A short, non-reversible hint for a credential, so the device log can be
' correlated without holding the secret itself.
function redactToken(token) as String
    if token = invalid or token = ""
        return ""
    end if
    if Len(token) <= 8
        mask = ""
        for i = 1 to Len(token)
            mask = mask + "*"
        end for
        return mask
    end if
    return Left(token, 4) + "...(" + Str(Len(token)) + " chars)"
end function

' A URL without its query string. The signed parameters in a playback URL
' are credentials of their own - anyone holding one can play the stream.
function redactUrl(url) as String
    if url = invalid or url = ""
        return ""
    end if
    questionMark = InStr(url, "?")
    if questionMark = 0
        return url
    end if
    return Left(url, questionMark - 1)
end function
