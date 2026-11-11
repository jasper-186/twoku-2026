sub init()
    m.code = m.top.findNode("code")
    m.instructions = m.top.findNode("instructions")
    ' The host comes from pkg:/env, so a self-hosted build tells the user
    ' where their own backend is.
    m.instructions.text = "Go to " + getBackendBaseUrl() + " and type the following code:"
    m.top.observeField("visible", "onVisible")
    m.getAuth = createObject("RoSGNode", "GetAuth")
    m.getAuth.observeField("code", "setUserCode")
    m.getAuth.observeField("finished", "whenFinished")
end sub

sub whenFinished()
    m.top.finished = true
end sub

sub setUserCode()
    m.code.text = m.getAuth.code
end sub

sub onVisible()
    if m.top.visible = true
        ? "RUN"
        m.getAuth.control = "RUN"
    else
        ? "STOP"
        m.getAuth.control = "STOP"
    end if
end sub