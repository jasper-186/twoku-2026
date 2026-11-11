function checkRegistrySection(section as object, key as object)
    sec = createObject("roRegistrySection", section)
    if sec.Exists(key)
        return sec.Read(key)
    end if
    return invalid
end function

function setRegistrySection(section as object, key as object, value as object)
    sec = createObject("roRegistrySection", section)
    sec.Write(key, value)
    sec.Flush()
end function
