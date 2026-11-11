' Backend endpoint configuration.
'
' The backend URL comes from the "env" file at the root of the package:
'
'   BASE-URL=https://twoku-web.clstr.dev/
'
' Self-hosters edit that file, run package.sh, and sideload the result. The
' value is baked into the package, so changing it needs a rebuild.
'
' If the file is missing, unreadable, or has no BASE-URL, the default
' deployment is used so the app still starts.
'
' The file is read on each call rather than cached in m.global. m.global is
' not safe for this: the XML children (LoginPage, HomeScene) run their init()
' before MainScene.init(), so a m.global field may not exist yet, and the
' field would have to be created from more than one thread. The file is a
' few dozen bytes and this is called only when a token or a stream link is
' needed, so re-reading it costs nothing.

function getBackendBaseUrl() as string
    url = readBaseUrlFromEnv()
    if url = "" then
        url = getDefaultBaseUrl()
    end if
    return url
end function

function getDefaultBaseUrl() as string
    return "https://twoku-web.clstr.dev"
end function

function readBaseUrlFromEnv() as string
    ' ReadAsciiFile returns "" when the file cannot be read.
    contents = ReadAsciiFile("pkg:/env")
    if contents = "" then return ""

    for each line in contents.Split(Chr(10))
        ' A CRLF file leaves a carriage return at the end of each line.
        if Len(line) > 0 and Right(line, 1) = Chr(13) then
            line = Left(line, Len(line) - 1)
        end if

        separator = InStr(line, "=")
        if separator > 0 then
            key = ""
            if separator > 1 then
                key = Left(line, separator - 1)
            end if
            if trimWhitespace(key) = "BASE-URL" then
                value = ""
                remaining = Len(line) - separator
                if remaining > 0 then
                    value = Right(line, remaining)
                end if
                return trimBaseUrl(value)
            end if
        end if
    end for

    return ""
end function

function trimBaseUrl(value as string) as string
    value = trimWhitespace(value)
    ' A trailing slash would double up when the endpoint path is appended.
    if Len(value) > 0 and Right(value, 1) = "/" then
        value = Left(value, Len(value) - 1)
    end if
    return value
end function

function trimWhitespace(value as string) as string
    ' Strip spaces and tabs from both ends.
    while Len(value) > 0 and isWhitespace(Left(value, 1))
        if Len(value) = 1 then
            value = ""
        else
            value = Right(value, Len(value) - 1)
        end if
    end while
    while Len(value) > 0 and isWhitespace(Right(value, 1))
        value = Left(value, Len(value) - 1)
    end while
    return value
end function

function isWhitespace(character as string) as boolean
    return character = " " or character = Chr(9)
end function
