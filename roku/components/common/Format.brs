' Returns "1.2M", "750K", "4.2K", "742" — no suffix. Caller appends " viewers" etc.
function formatCountAbbrev(number) as String
    s = StrI(number)
    result = ""
    if number >= 1000000
        result = Left(s, 2) + "." + Mid(s, 3, 1) + "M"
    else if number >= 100000
        result = Left(s, 4) + "K"
    else if number >= 10000
        result = Left(s, 3) + "." + Mid(s, 4, 1) + "K"
    else if number >= 1000
        result = Left(s, 2) + "." + Mid(s, 3, 1) + "K"
    else
        result = s
    end if
    return result
end function

function secondsSinceISO8601(timestamp as String) as Integer
    dt = createObject("roDateTime")
    dt.FromISO8601String(timestamp)
    return createObject("roDateTime").AsSeconds() - dt.AsSeconds()
end function

function formatElapsedHMS(elapsedSeconds as Integer) as String
    hours = Int(elapsedSeconds / 60 / 60)
    mins = elapsedSeconds / 60 mod 60
    secs = elapsedSeconds mod 60
    if mins < 10
        mins = "0" + mins.ToStr()
    else
        mins = mins.ToStr()
    end if
    if secs < 10
        secs = "0" + secs.ToStr()
    else
        secs = secs.ToStr()
    end if
    return hours.ToStr() + ":" + mins + ":" + secs
end function
