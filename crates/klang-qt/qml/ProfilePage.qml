// The signed-in user's TIDAL profile: hero band with name/bio, edit/share
// actions, their public playlists and social links.
//
// `controller` is shared with the header's UserMenu (see Main.qml) instead
// of being owned here like CatalogController is by AlbumPage/ArtistPage —
// the same profile fetch feeds the header avatar, so it lives once at the
// top level and this page just reloads it in place on each visit.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import me.unbk.klang

Item {
    id: root

    required property var controller
    required property int userId

    /// Navigation requests bubble up to Main.qml.
    signal openPlaylist(string uuid, string title)
    signal viewAllPlaylistsRequested(var playlists, string profileName)
    signal backRequested()

    readonly property int heroHeight: 320
    property bool bioExpanded: false
    property bool editOpen: false
    property string shareFeedback: ""

    function profile() {
        return JSON.parse(root.controller.profile_json || "{}")
    }

    function hasProfile() {
        return root.profile().userId !== undefined
    }

    function reload() {
        if (root.userId !== 0)
            root.controller.load(root.userId)
    }

    Component.onCompleted: root.reload()

    // TIDAL's fan count has no thousands separators of its own; a rough
    // K/M abbreviation (no Intl dependency) matches the compact style
    // upstream shows on tidal.com.
    function formatCompact(n) {
        if (n >= 1000000)
            return (n / 1000000).toFixed(1).replace(/\.0$/, "") + "M"
        if (n >= 1000)
            return (n / 1000).toFixed(1).replace(/\.0$/, "") + "K"
        return String(n)
    }

    function metaLine() {
        const p = root.profile()
        const parts = []
        if (p.handle)
            parts.push("@" + p.handle)
        if (p.hasFanCount)
            parts.push(Tr.t(p.fanCount === 1 ? "%1 fan" : "%1 fans")
                       .arg(root.formatCompact(p.fanCount)))
        return parts.join(" · ")
    }

    // TIDAL exposes these five social kinds on a profile; a homepage link
    // (the sixth external-link type) is shown as the "Link" field in the
    // edit dialog instead, not in this list.
    readonly property var socialTypes: ["INSTAGRAM", "TIKTOK", "FACEBOOK", "TWITTER", "SNAPCHAT"]
    readonly property var socialLabels: ({
        INSTAGRAM: "Instagram",
        TIKTOK: "TikTok",
        FACEBOOK: "Facebook",
        TWITTER: "X",
        SNAPCHAT: "Snapchat",
    })

    function socialLinks() {
        const links = root.profile().externalLinks || []
        const found = {}
        for (const link of links) {
            if (root.socialTypes.includes(link.linkType))
                found[link.linkType] = link.href
        }
        return root.socialTypes.filter((t) => found[t]).map((t) => ({ type: t, href: found[t] }))
    }

    function playlistCards() {
        return root.profile().playlists || []
    }

    // Qt Quick has no clipboard API of its own; routing a copy through a
    // hidden TextEdit's own copy() is the standard QML workaround.
    TextEdit {
        id: clipboardHelper
        visible: false
        function copyText(t) {
            text = t
            selectAll()
            copy()
        }
    }

    Timer {
        id: shareFeedbackTimer
        interval: 1500
        onTriggered: root.shareFeedback = ""
    }

    function share() {
        const artistId = root.profile().artistId
        if (!artistId)
            return
        clipboardHelper.copyText("https://tidal.com/artist/" + artistId + "/u")
        root.shareFeedback = Tr.t("Copied!")
        shareFeedbackTimer.restart()
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.base
    }

    // ---- Not signed in ------------------------------------------------

    ColumnLayout {
        anchors.centerIn: parent
        spacing: Theme.spaceSm
        visible: root.userId === 0

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Tr.t("Not signed in")
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeLg
            font.weight: Font.Bold
            color: Theme.textPrimary
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Tr.t("Sign in to view your profile.")
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            color: Theme.textMuted
        }
    }

    QQC2.BusyIndicator {
        anchors.centerIn: parent
        running: root.userId !== 0 && root.controller.loading && !root.hasProfile()
    }

    // ---- Not found ------------------------------------------------------

    ColumnLayout {
        anchors.centerIn: parent
        spacing: Theme.spaceSm
        visible: root.userId !== 0 && !root.controller.loading && root.controller.not_found

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Tr.t("Profile not found")
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeLg
            font.weight: Font.Bold
            color: Theme.textPrimary
        }
    }

    // ---- Error ------------------------------------------------------

    ColumnLayout {
        anchors.centerIn: parent
        spacing: Theme.space
        visible: root.userId !== 0 && !root.controller.loading && !root.controller.not_found
                 && root.controller.error.length > 0

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Tr.t("Couldn't load profile")
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeLg
            font.weight: Font.Bold
            color: Theme.textPrimary
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.controller.error
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            color: Theme.textMuted
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: goBackText.implicitWidth + Theme.spaceXl
            implicitHeight: 36
            radius: Theme.radiusFull
            color: Theme.textPrimary

            TapHandler { onSingleTapped: root.backRequested() }

            Text {
                id: goBackText
                anchors.centerIn: parent
                text: Tr.t("Go back")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                font.weight: Font.Bold
                color: Theme.base
            }
        }
    }

    // ---- Loaded profile ---------------------------------------------------

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        visible: root.userId !== 0 && !root.controller.not_found
                 && root.controller.error.length === 0 && root.hasProfile()

        HoverHandler { id: pageHover }
        WheelScroller { view: flick; rowHeight: Theme.rowHeight }
        QQC2.ScrollBar.vertical: ThemedScrollBar { listHovered: pageHover.hovered }

        ColumnLayout {
            id: column
            width: flick.width
            spacing: Theme.spaceLg

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: root.heroHeight
                clip: true

                CoverArt {
                    anchors.fill: parent
                    uuid: root.profile().heroUrl || ""
                    placeholderGlyph: "☺"
                }

                // Fades the photo down into the page background, strongest
                // at the bottom so the text panel below always reads clean.
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.55; color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.6) }
                        GradientStop { position: 1.0; color: Theme.base }
                    }
                }

                ColumnLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Theme.spaceLg
                    spacing: Theme.space

                    Text {
                        Layout.fillWidth: true
                        text: root.profile().name || ""
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeDisplay
                        font.weight: Font.ExtraBold
                        color: Theme.textPrimary
                    }

                    Text {
                        visible: text.length > 0
                        text: root.metaLine()
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.weight: Font.DemiBold
                        color: Theme.textSecondary
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.maximumWidth: 760
                        spacing: Theme.spaceXs
                        visible: bioText.text.length > 0

                        Text {
                            id: bioText
                            Layout.fillWidth: true
                            text: root.profile().bio || ""
                            wrapMode: Text.WordWrap
                            elide: Text.ElideRight
                            maximumLineCount: root.bioExpanded ? 1000 : 3
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.weight: Font.DemiBold
                            color: Theme.textSecondary
                        }

                        Text {
                            visible: bioText.truncated || root.bioExpanded
                            text: root.bioExpanded ? "Show less" : "Show more"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Font.DemiBold
                            color: bioToggleHover.hovered ? Theme.textPrimary : Theme.accent

                            HoverHandler { id: bioToggleHover }
                            TapHandler { onSingleTapped: root.bioExpanded = !root.bioExpanded }
                        }
                    }

                    Rectangle {
                        visible: !!root.profile().hasArtistId && bioText.text.length === 0
                        implicitWidth: addBioText.implicitWidth + Theme.space
                        implicitHeight: 30
                        radius: Theme.radiusFull
                        color: "transparent"
                        border.color: Theme.textSecondary
                        border.width: 1

                        HoverHandler { id: addBioHover }
                        TapHandler { onSingleTapped: root.editOpen = true }

                        Text {
                            id: addBioText
                            anchors.centerIn: parent
                            text: Tr.t("Add bio")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Font.DemiBold
                            color: addBioHover.hovered ? Theme.textPrimary : Theme.textSecondary
                        }
                    }

                    RowLayout {
                        spacing: Theme.spaceLg
                        visible: !!root.profile().hasArtistId

                        Text {
                            text: Tr.t("Edit profile")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Font.Bold
                            color: editHover.hovered ? Theme.textPrimary : Theme.textSecondary

                            HoverHandler { id: editHover }
                            TapHandler { onSingleTapped: root.editOpen = true }
                        }

                        Text {
                            text: root.shareFeedback.length > 0 ? root.shareFeedback : Tr.t("Share")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Font.Bold
                            color: shareHover.hovered ? Theme.textPrimary : Theme.textSecondary

                            HoverHandler { id: shareHover }
                            TapHandler { onSingleTapped: root.share() }
                        }
                    }
                }
            }

            CardCarousel {
                Layout.fillWidth: true
                visible: root.playlistCards().length > 0
                title: Tr.t("Public playlists")
                items: root.playlistCards()
                hasViewAll: true
                onItemActivated: (item) => root.openPlaylist(item.id, item.title)
                onItemPlayRequested: (item) => root.openPlaylist(item.id, item.title)
                onViewAllRequested: root.viewAllPlaylistsRequested(root.playlistCards(), root.profile().name || "")
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spaceLg
                Layout.rightMargin: Theme.spaceLg
                Layout.bottomMargin: Theme.spaceXl
                spacing: Theme.space
                visible: root.socialLinks().length > 0

                Text {
                    text: Tr.t("Social")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeHeading
                    font.weight: Font.Bold
                    color: Theme.textPrimary
                }

                ColumnLayout {
                    spacing: Theme.spaceSm

                    Repeater {
                        model: root.socialLinks()

                        Text {
                            required property var modelData
                            text: root.socialLabels[modelData.type] || modelData.type
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.weight: Font.DemiBold
                            color: socialHover.hovered ? Theme.textPrimary : Theme.textSecondary

                            HoverHandler { id: socialHover }
                            TapHandler { onSingleTapped: Qt.openUrlExternally(modelData.href) }
                        }
                    }
                }
            }
        }
    }

    ScrollMemory {
        flickable: flick
        pageKey: "profile:" + root.userId
    }

    ProfileEditDialog {
        anchors.fill: parent
        controller: root.controller
        open: root.editOpen
        onCloseRequested: root.editOpen = false
    }
}
