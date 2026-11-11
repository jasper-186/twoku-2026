sub init()
    m.itemThumbnail = m.top.findNode("itemThumbnail")
    m.itemTitle = m.top.findNode("itemTitle")
    m.itemGame = m.top.findNode("itemGame")
    m.itemViewers = m.top.findNode("itemViewers")
    m.viewsRect = m.top.findNode("viewsRect")
end sub

sub showContent()
    itemContent = m.top.itemContent
    '? "itemContent: " 
    '? itemContent
    if itemContent = invalid
        ? "ShowContent: No content to show"
        return
    end if
    if itemContent.HDPosterUrl = invalid or itemContent.HDPosterUrl = ""
        ' There is no placeholder image in the package - clear the poster
        ' rather than point it at a file that is not there.
        m.itemThumbnail.uri = ""
    else
        m.itemThumbnail.uri = itemContent.HDPosterUrl
    end if
    if itemContent.ShortDescriptionLine2 = invalid
        m.itemTitle.text = ""
    else
        m.itemTitle.text = itemContent.ShortDescriptionLine2
    end if
    if itemContent.Categories = invalid
        m.itemGame.text = ""
    else
        m.itemGame.text = itemContent.Categories[0]
    end if
    if itemContent.Title = invalid
        m.itemViewers.text = ""
    else
        m.itemViewers.text = itemContent.Title
    end if

    m.viewsRect.width = m.itemViewers.localBoundingRect().width + 16
    m.viewsRect.height = m.itemViewers.localBoundingRect().height
end sub