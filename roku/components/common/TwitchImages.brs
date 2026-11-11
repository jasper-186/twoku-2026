' Rewrites a Twitch image URL to a specific width/height.
'
' Handles two URL families:
'   - Fixed-size:  ".../prefix-300x300.jpeg"  → ".../prefix-WxH.jpeg"
'     (profile_image_url, offline_image_url, channel logo)
'   - Placeholder: ".../prefix-{width}x{height}.jpg" or ".../prefix-%{width}x%{height}.jpeg"
'     (stream thumbnails, VOD thumbnails)
'
' Returns the URL unchanged if it doesn't match either pattern.
function resizeTwitchImageUrl(url as Object, width as Integer, height as Integer) as String
    if url = invalid or url = ""
        return ""
    end if

    if Instr(1, url, "{width}") > 0
        result = url
        wRegex = createObject("roRegex", "%?\{width\}", "")
        result = wRegex.ReplaceAll(result, width.ToStr())
        hRegex = createObject("roRegex", "%?\{height\}", "")
        result = hRegex.ReplaceAll(result, height.ToStr())
        return result
    end if

    sizeRegex = createObject("roRegex", "\d+x\d+\.([a-zA-Z]+)$", "")
    match = sizeRegex.Match(url)
    if match.Count() >= 2
        return sizeRegex.Replace(url, width.ToStr() + "x" + height.ToStr() + "." + match[1])
    end if

    return url
end function
