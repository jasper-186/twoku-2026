function init()
    m.videoPlayer = m.top.findNode("videoPlayer")
    m.keyboardGroup = m.top.findNode("keyboardGroup")
    m.homeScene = m.top.findNode("homeScene")
    m.categoryScene = m.top.findNode("categoryScene")
    ' m.channelPage = m.top.findNode("channelPage")
    m.loginPage = m.top.findNode("loginPage")

    m.keyboardGroup.observeField("streamUrl", "onStreamChange")
    m.keyboardGroup.observeField("streamerSelectedName", "onStreamerSelected")

    m.homeScene.observeField("streamUrl", "onStreamChange")
    m.homeScene.observeField("streamerSelectedName", "onStreamerSelected")
    m.homeScene.observeField("categorySelected", "onCategoryItemSelect")
    m.homeScene.observeField("buttonPressed", "onHeaderButtonPress")
    m.homeScene.observeField("videoUrl", "onStreamChangeFromChannelPage")

    m.keyboardGroup.observeField("categorySelected", "onCategoryItemSelectFromSearch")

    m.categoryScene.observeField("streamUrl", "onStreamChange")
    m.categoryScene.observeField("streamerSelectedThumbnail", "onStreamerSelected")
    m.categoryScene.observeField("clipUrl", "onClipChange")

    ' m.channelPage.observeField("videoUrl", "onStreamChangeFromChannelPage")
    ' m.channelPage.observeField("streamUrl", "onStreamChange")

    m.loginPage.observeField("finished", "onLoginFinish")

    m.videoPlayer.observeField("back", "onVideoPlayerBack")
    m.videoPlayer.observeField("toggleChat", "onToggleChat")
    m.videoPlayer.observeField("streamLayoutMode", "onToggleStreamLayout")

    m.top.backgroundColor = "0x18181BFF"
    m.top.backgroundUri = ""

    m.currentScene = "home"
    m.lastScene = ""
    m.lastLastScene = ""

    m.stream = createObject("RoSGNode", "ContentNode")
    m.stream["streamFormat"] = "hls"

    m.getToken = createObject("roSGNode", "GetToken")
    m.getToken.observeField("appBearerToken", "onBearerTokenReceived")
    m.getToken.control = "RUN"

    m.login = ""
    m.getUser = createObject("roSGNode", "GetUser")
    m.getUser.observeField("searchResults", "onUserLogin")

    m.followsRefreshTimer = m.top.findNode("followsRefreshTimer")
    m.followsRefreshTimer.control = "start"
    m.followsRefreshTimer.ObserveField("fire", "refreshFollows")

    if checkRegistrySection("LoggedInUserData", "Reset") = invalid
        ' Registry writes are not committed until Flush() is called, and each
        ' section is a snapshot - so write the Reset flag on the same section
        ' as the rest and flush once.
        sec = createObject("roRegistrySection", "LoggedInUserData")
        sec.Write("UserToken", "")
        sec.Write("RefreshToken", "")
        sec.Write("LoggedInUserName", "")
        sec.Write("Reset", "true")
        sec.Flush()
        ? "RESETTED"
    end if
    
    ' Seed the user token before anything can ask for it. GetUser starts
    ' below, and a browse refresh may already have replaced the token in the
    ' registry - do not overwrite that with the older copy.
    if m.global.userToken = invalid
        userToken = checkRegistrySection("LoggedInUserData", "UserToken")
        if userToken <> invalid and userToken <> ""
            m.global.addFields({userToken: userToken})
        else
            m.global.addFields({userToken: ""})
        end if
    end if

    ' registry = CreateObject("roRegistry")
    ' registry.Delete("LoggedInUserNameData")
    ' registry.Delete("VideoSettings")

    ' loggedInUserName = checkIfLoggedIn()
    loggedInUserName = checkRegistrySection("LoggedInUserData", "LoggedInUserName")
    if loggedInUserName <> invalid
        m.getUser.loggedInUserName = loggedInUserName
        m.getUser.control = "RUN"
        m.login = loggedInUserName
        m.homeScene.loggedInUserLogin = loggedInUserName
    end if

    ' videoQuality = checkSavedVideoQuality()
    videoQuality = checkRegistrySection("VideoSettings", "VideoQuality")
    if videoQuality <> invalid
        m.global.addFields({videoQuality: Int(Val(videoQuality))})
    else
        m.global.addFields({videoQuality: 2})
    end if

    ' chatOption = checkSavedChatOption()
    chatOption = checkRegistrySection("VideoSettings", "ChatOption")
    if chatOption <> invalid and chatOption = "true"
        m.global.addFields({chatOption: true})
    else
        m.global.addFields({chatOption: false})
    end if

    ' videoBookmarks = checkVideoBookmarks()
    videoBookmarks = checkRegistrySection("VideoSettings", "VideoBookmarks")
    ? "MainScene >> videoBookmarks > " videoBookmarks
    if videoBookmarks <> invalid
        'm.videoPlayer.videoBookmarks = {}
        m.videoPlayer.videoBookmarks = ParseJSON(videoBookmarks)
        ? "MainScene >> ParseJSON > " m.videoPlayer.videoBookmarks
    else
        m.videoPlayer.videoBookmarks = {}
    end if

    ' The registry holds a limited amount of data and the recently watched
    ' list grows by one entry per channel watched, so keep only the most
    ' recent. Twenty is more than the recents rail can show anyway.
    m.maxRecents = 20

    m.homeScene.recentStreamers = []
    recentStreamers = checkRegistrySection("LoggedInUserData", "RecentStreamers")
    if recentStreamers <> invalid and recentStreamers <> ""
        parsedRecents = ParseJSON(recentStreamers)
        if parsedRecents <> invalid
            if parsedRecents.recents <> invalid
                m.homeScene.recentStreamers = trimRecents(parsedRecents.recents)
            end if
        end if
    end if

    ? "MainScene >> registry space > " createObject("roRegistry").GetSpaceAvailable()

    deviceInfo = CreateObject("roDeviceInfo")
    m.uiResolutionWidth = deviceInfo.GetUIResolution().width

    m.chat = m.top.findNode("chat")
    m.chat.observeField("doneFocus", "onChatDoneFocus")

    m.options = createObject("roSGNode", "Options")
    m.options.visible = false

    m.top.appendChild(m.options)

    m.homeScene.setFocus(true)
end function

sub onChatDoneFocus()
    if m.chat.doneFocus
        m.videoPlayer.setFocus(true)
        m.chat.doneFocus = false
    end if
end sub

sub onLoginFinish()
    if m.loginPage.finished = true
        ' loggedInUserName = checkIfLoggedIn()
        loggedInUserName = checkRegistrySection("LoggedInUserData", "LoggedInUserName")
        if loggedInUserName <> invalid
            m.getUser.loggedInUserName = loggedInUserName
            m.getUser.control = "RUN"
            m.login = loggedInUserName
        end if
        m.loginPage.visible = false
        m.homeScene.visible = false
        m.homeScene.visible = true
        m.homeScene.setFocus(true)
        m.loginPage.finished = false
    end if
end sub

sub onBearerTokenReceived()
    m.global.addFields({appClientId: m.getToken.appClientId})
    m.global.addFields({appBearerToken: m.getToken.appBearerToken})
end sub

sub onStreamChangeFromChannelPage()
    m.stream["streamFormat"] = "hls"
    m.stream["url"] = m.homeScene.videoUrl
    m.chat.visible = false
    m.videoPlayer.chatIsVisible = m.chat.visible

    m.videoPlayer.videoTitle =  m.homeScene.videoTitle
    m.videoPlayer.channelUsername =  m.homeScene.channelUsername
    'm.videoPlayer.channelAvatar =  ""
    m.videoPlayer.channelAvatar =  m.homeScene.channelAvatar
    updateRecents()

    m.videoPlayer.width = 0
    m.videoPlayer.height = 0
    m.videoPlayer.setFocus(true)
    
    m.keyboardGroup.visible = false
    ' m.channelPage.visible = false
    
    m.videoPlayer.visible = true
    m.videoPlayer.content = m.stream
    m.videoPlayer.thumbnailInfo = m.homeScene.thumbnailInfo
    m.homeScene.thumbnailInfo = invalid
    ' The seek has to be set before playback starts. A seek that arrives
    ' after the player is already running takes the media player down and
    ' the video never starts at all.
    if m.videoPlayer.thumbnailInfo <> invalid
        if m.videoPlayer.videoBookmarks.DoesExist(m.videoPlayer.thumbnailInfo.video_id.ToStr())
            ? "MainScene >> position > " m.videoPlayer.videoBookmarks[m.videoPlayer.thumbnailInfo.video_id.ToStr()]
            m.videoPlayer.seek = Val(m.videoPlayer.videoBookmarks[m.videoPlayer.thumbnailInfo.video_id.ToStr()])
        end if
    end if
    m.videoPlayer.control = "play"
end sub

sub updateRecents()
    recents = m.homeScene.recentStreamers
    for streamer = 0 to recents.count() - 1
        if recents[streamer].user_name = m.homeScene.channelUsername
            recents.delete(streamer)
            exit for
        end if
    end for
    streamer = {
        user_name: m.homeScene.channelUsername,
        profile_image_url: m.homeScene.channelAvatar,
        login: m.homeScene.streamerSelectedName
    }
    recents.push(streamer)
    recents = trimRecents(recents)

    m.homeScene.recentStreamers = recents
    ' setRegistrySection writes and flushes - a bare Write is never committed.
    setRegistrySection("LoggedInUserData", "RecentStreamers", FormatJSON({recents: recents}))
end sub

' Drops the oldest entries until the list is within the cap. The recents rail
' renders the list newest first, so the oldest entries are at the front.
function trimRecents(recents) as Object
    while recents.count() > m.maxRecents
        recents.delete(0)
    end while
    return recents
end function

sub onStreamerSelected()
    if m.homeScene.visible
        'm.channelPage.streamerSelectedName = m.homeScene.streamerSelectedName
        'm.channelPage.streamerSelectedThumbnail = m.homeScene.streamerSelectedThumbnail
        m.lastScene = "home"
    else if m.categoryScene.visible
        m.homeScene.lastScene = "category"
        m.homeScene.streamerSelectedThumbnail = m.categoryScene.streamerSelectedThumbnail
        m.homeScene.streamerSelectedName = m.categoryScene.streamerSelectedName
        m.lastLastScene = "home" 'm.lastScene
        m.lastScene = "category"
    else if m.keyboardGroup.visible
        'm.channelPage.streamerSelectedName = m.keyboardGroup.streamerSelectedName
        'm.channelPage.streamerSelectedThumbnail = ""
        m.homeScene.streamerSelectedName = m.keyboardGroup.streamerSelectedName
        m.homeScene.streamerSelectedThumbnail = ""
        m.lastLastScene = "home"
        m.lastScene = "search"
    end if
    m.homeScene.visible = false
    m.keyboardGroup.visible = false
    m.categoryScene.visible = false

    'm.channelPage.visible = true
    m.homeScene.visible = true

    m.currentScene = "channel"
end sub

function onHeaderButtonPress()
    if m.homeScene.buttonPressed = "search"
        m.homeScene.visible = false
        m.keyboardGroup.visible = true
        m.keyboardGroup.setFocus(true)
    else if m.homeScene.buttonPressed = "login"
        m.homeScene.visible = false
        m.loginPage.visible = true
        m.loginPage.setFocus(true)
    else if m.homeScene.buttonPressed = "options"
        m.homeScene.visible = false
        m.options.visible = true
        m.options.setFocus(true)
    end if
end function

function onUserLogin()
    if m.getUser.searchResults = invalid or m.getUser.searchResults.Count() = 0
        ' A lookup that comes back empty is usually transient - a dropped
        ' request or an expired token that has not been refreshed yet.
        ' Throwing the stored login away here would leave the user with
        ' nothing to sign back in with on the next launch. clearLogin() is
        ' what actually signs someone out.
        ? "GetUser returned no results - keeping the stored login"
    else
        m.homeScene.loggedInUserName = m.getUser.searchResults.display_name
        m.homeScene.loggedInUserLogin = m.getUser.searchResults.login
        m.homeScene.loggedInUserProfileImage = m.getUser.searchResults.profile_image_url
        m.chat.loggedInUserName = m.getUser.searchResults.login
    ' searchResults.id is the Twitch user id - the chat needs it to
    ' subscribe to a channel's events.
    m.chat.loggedInUserId = m.getUser.searchResults.id
        m.homeScene.followedStreams = m.getUser.searchResults.followed_users
        m.homeScene.currentlyLiveStreamerIds = m.getUser.currentlyLiveStreamerIds
        '? "currentlyLiveStreamerIds mainscene " m.getUser.currentlyLiveStreamerIds
        ' saveLogin()
        setRegistrySection("LoggedInUserData", "LoggedInUser", m.homeScene.loggedInUserName)
    end if
end function

function onCategoryItemSelectFromSearch()
    m.categoryScene.currentCategory = m.keyboardGroup.categorySelected
    m.homeScene.visible = false
    m.keyboardGroup.visible = false
    m.categoryScene.visible = true
    m.lastLastScene = "home"
    m.lastScene = "search"
end function

function onCategoryItemSelect()
    m.categoryScene.currentCategory = m.homeScene.categorySelected
    m.homeScene.visible = false
    m.keyboardGroup.visible = false
    m.categoryScene.visible = true
    m.lastScene = "home"
end function

function onClipChange()
    m.categoryScene.fromClip = true
    m.stream["streamFormat"] = "mp4"
    if m.categoryScene.visible = true
        m.currentScene = "category"
        m.stream["url"] = m.categoryScene.clipUrl
    end if
    m.videoPlayer.setFocus(true)
    m.categoryScene.visible = false
    m.keyboardGroup.visible = false
    m.videoPlayer.width = 0
    m.videoPlayer.height = 0
    m.videoPlayer.visible = true
    m.videoPlayer.content = m.stream
    m.videoPlayer.control = "play"
end function

function onStreamChange()
    m.stream["streamFormat"] = "hls"
    if m.keyboardGroup.visible
        m.currentScene = "search"
        m.chat.channel = m.keyboardGroup.streamerRequested
        m.chat.broadcasterUserId = m.keyboardGroup.streamerUserId
        m.stream["url"] = m.keyboardGroup.streamUrl
    else if m.homeScene.visible
        m.currentScene = "home"
        m.chat.channel = m.homeScene.streamerSelectedName 'm.homeScene.streamerRequested
        m.chat.broadcasterUserId = strtoi(m.homeScene.streamerUserId)
        m.videoPlayer.videoTitle =  m.homeScene.videoTitle
        m.videoPlayer.channelUsername =  m.homeScene.channelUsername
        m.videoPlayer.channelAvatar =  m.homeScene.channelAvatar
        updateRecents()
        m.videoPlayer.streamDurationSeconds =  m.homeScene.streamDurationSeconds
        m.stream["url"] = m.homeScene.streamUrl
    else if m.categoryScene.visible
        m.currentScene = "category"
        m.chat.channel = m.categoryScene.streamerRequested
        m.chat.broadcasterUserId = m.categoryScene.streamerUserId
        m.stream["url"] = m.categoryScene.streamUrl
    end if
    ' onToggleStreamLayout applies the chat option.
    onToggleStreamLayout()
    m.videoPlayer.setFocus(true)
    m.keyboardGroup.visible = false
    m.videoPlayer.visible = true
    m.videoPlayer.content = m.stream
    m.videoPlayer.control = "play"
end function

function refreshFollows()
    ' Only refresh while the user is browsing. The video player covers the
    ' screen when a stream is playing, and there is nothing to refresh then.
    if m.login <> "" and m.videoPlayer.visible = false
        m.getUser.loggedInUserName = m.login
        m.getUser.control = "RUN"
    end if
end function


sub onVideoPlayerBack()
    if m.videoPlayer.back = true
        m.videoPlayer.control = "stop"
        m.videoPlayer.visible = false
        m.keyboardGroup.visible = false
        if m.currentScene = "home"
            m.homeScene.visible = false
            m.homeScene.visible = true
            m.homeScene.setFocus(true)
        else if m.currentScene = "category"
            m.categoryScene.visible = true
            'm.categoryScene.fromClip = false
            m.categoryScene.setFocus(true)
        else if m.currentScene = "search"
            m.keyboardGroup.visible = true
        else if m.currentScene = "channel"
            m.homeScene.visible = false
            m.homeScene.visible = true
            m.homeScene.setFocus(true)
            'm.channelPage.visible = true
            'm.channelPage.setFocus(true)
        end if
        m.chat.visible = false
        m.videoPlayer.chatIsVisible = m.chat.visible
        m.videoPlayer.back = false
    end if
end sub

sub onToggleChat()
    if m.videoPlayer.toggleChat = true
        m.chat.visible = not m.chat.visible
        m.videoPlayer.chatIsVisible = m.chat.visible
        m.videoPlayer.toggleChat = false
    end if
end sub

sub onToggleStreamLayout()
    if m.videoPlayer.streamLayoutMode = 0 'stream is shrinked
        m.videoPlayer.width = 1030
        m.videoPlayer.height = 720
        m.chat.visible = m.global.chatOption
        m.videoPlayer.chatIsVisible = m.chat.visible
    else if m.videoPlayer.streamLayoutMode = 1 'layout with chat on top of stream
        m.videoPlayer.width = 0
        m.videoPlayer.height = 0
        m.chat.visible = m.global.chatOption
        m.videoPlayer.chatIsVisible = m.chat.visible
    else if m.videoPlayer.streamLayoutMode = 2 'no chat layout fullscreen
        m.videoPlayer.width = 0
        m.videoPlayer.height = 0
        m.chat.visible = false
        m.videoPlayer.chatIsVisible = m.chat.visible
    end if
end sub

function onKeyEvent(key, press) as Boolean
    handled = false
    if press
        if m.videoPlayer.visible = true and key = "back" 
            m.videoPlayer.back = true
            handled = true
        else if m.videoPlayer.visible = true and key = "rewind"
            'm.chat.visible = not m.chat.visible
            'handled = true
        else if m.homeScene.visible = true and key = "options"
            m.homeScene.visible = false
            m.keyboardGroup.visible = true
            m.keyboardGroup.setFocus(true)
            handled = true
        else if m.options.visible and key = "back"
            m.options.visible = false
            m.homeScene.visible = false
            m.homeScene.visible = true
            m.homeScene.setFocus(true)
            handled = true
        'else if (m.keyboardGroup.visible or m.categoryScene.visible or m.channelPage.visible) and key = "back"
        else if (m.keyboardGroup.visible or m.categoryScene.visible) and key = "back"
            m.categoryScene.visible = false
            m.keyboardGroup.visible = false
            m.options.visible = false
            'm.channelPage.visible = false
            m.homeScene.visible = false
            if m.lastScene = "home"
                m.homeScene.visible = false
                m.homeScene.visible = true
                m.homeScene.setFocus(true)
            else if m.lastScene = "category"
                m.lastScene = m.lastLastScene
                m.lastLastScene = "home"
                m.categoryScene.visible = true
                'm.categoryScene.fromClip = false
                m.categoryScene.setFocus(true)
            else if m.lastScene = "search"
                m.lastScene = m.lastLastScene
                m.lastLastScene = "home"
                m.keyboardGroup.visible = true
            else
                m.homeScene.visible = false
                m.homeScene.visible = true
                m.homeScene.setFocus(true)
            end if
            handled = true
        else if m.homeScene.visible and key = "back"
            if m.homeScene.lastScene = "category"
                m.homeScene.visible = false
                m.categoryScene.visible = true
                m.lastScene = m.lastLastScene
                m.lastLastScene = "home"
                'm.categoryScene.setFocus(true)
                handled = true
            end if
            'handled = true
        else if m.loginPage.visible and key = "back"
            m.loginPage.visible = false
            m.homeScene.visible = false
            m.homeScene.visible = true
            m.homeScene.setFocus(true)
            return true
        else if key = "OK" and m.videoPlayer.visible
            m.chat.setKeyboardFocus = true
            handled = true
        end if
    end if

    '? "MAINSCENE > handled " handled " > (" key ", " press ")"
    return handled
end function