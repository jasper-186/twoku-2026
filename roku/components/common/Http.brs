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
