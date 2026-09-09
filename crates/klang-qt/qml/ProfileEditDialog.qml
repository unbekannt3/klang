// Edit modal for the signed-in user's profile: name, handle, link, bio,
// picture and social links. A "Social media" sub-screen swaps in over the
// main form, mirroring upstream's two-panel layout.
//
// The panel is behind a Loader keyed on `open` rather than a plain child, so
// every open is a fresh mount — the same one-shot "seed fields from the
// current profile" semantics upstream gets from mounting a fresh React
// component each time, without QML's draft fields going stale if the dialog
// is closed unsaved and reopened later in the same page visit.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Dialogs
import me.unbk.klang

Item {
    id: root

    required property var controller
    property bool open: false
    signal closeRequested()

    visible: root.open
    enabled: root.open

    Keys.onEscapePressed: root.closeRequested()

    readonly property var socialTypes: ["INSTAGRAM", "TIKTOK", "FACEBOOK", "TWITTER", "SNAPCHAT"]
    readonly property var socialLabels: ({
        INSTAGRAM: "Instagram",
        TIKTOK: "TikTok",
        FACEBOOK: "Facebook",
        TWITTER: "X",
        SNAPCHAT: "Snapchat",
    })
    readonly property string websiteLinkType: "OFFICIAL_HOMEPAGE"

    function splitLinks(links) {
        let website = ""
        const socials = {}
        for (const link of links) {
            if (link.linkType === root.websiteLinkType)
                website = link.href
            else if (root.socialTypes.includes(link.linkType))
                socials[link.linkType] = link.href
        }
        return { website: website, socials: socials }
    }

    function assembleLinks(website, socials) {
        const out = []
        const trimmedWebsite = (website || "").trim()
        if (trimmedWebsite.length > 0)
            out.push({ href: trimmedWebsite, linkType: root.websiteLinkType })
        for (const type of root.socialTypes) {
            const value = (socials[type] || "").trim()
            if (value.length > 0)
                out.push({ href: value, linkType: type })
        }
        return out
    }

    function localFilePath(fileUrl) {
        return decodeURIComponent(fileUrl.toString().replace(/^file:\/\//, ""))
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.overlay
        opacity: 0.55

        TapHandler { onSingleTapped: root.closeRequested() }
    }

    Loader {
        anchors.fill: parent
        active: root.open
        sourceComponent: panelComponent
    }

    Component {
        id: panelComponent

        Item {
            id: panelRoot
            anchors.fill: parent

            function profile() {
                return JSON.parse(root.controller.profile_json || "{}")
            }

            readonly property var initialProfile: profile()
            readonly property bool canEdit: !!initialProfile.hasArtistId
            readonly property bool busy: root.controller.saving
            readonly property int bioMax: 5000

            property bool showSocial: false
            // Which action is in flight, so the dialog only auto-closes after
            // a successful main-form save — an in-progress picture change
            // must not dismiss it, matching upstream's modal.
            property string pendingAction: ""

            Connections {
                target: root.controller
                function onSavingChanged() {
                    if (root.controller.saving || root.controller.error.length > 0)
                        return
                    if (panelRoot.pendingAction === "profile")
                        root.closeRequested()
                    panelRoot.pendingAction = ""
                }
            }

            function collectSocials() {
                const out = {}
                for (let i = 0; i < socialRepeater.count; i++) {
                    const item = socialRepeater.itemAt(i)
                    if (item)
                        out[root.socialTypes[i]] = item.value
                }
                return out
            }

            function save() {
                if (!panelRoot.canEdit || panelRoot.busy)
                    return
                panelRoot.pendingAction = "profile"
                const links = root.assembleLinks(websiteInput.text, panelRoot.collectSocials())
                root.controller.save(
                    panelRoot.initialProfile.artistId,
                    nameInput.text,
                    handleInput.text,
                    bioInput.text,
                    JSON.stringify(links))
            }

            function deletePicture() {
                if (!panelRoot.canEdit || panelRoot.busy)
                    return
                panelRoot.pendingAction = "picture"
                root.controller.delete_picture(panelRoot.initialProfile.artistId)
            }

            FileDialog {
                id: pictureDialog
                title: Tr.t("Choose profile picture")
                nameFilters: ["Images (*.png *.jpg *.jpeg)"]
                onAccepted: {
                    panelRoot.pendingAction = "picture"
                    root.controller.upload_picture(
                        panelRoot.initialProfile.artistId,
                        root.localFilePath(selectedFile))
                }
            }

            // ---- Main form --------------------------------------------
            Rectangle {
                id: formPanel
                anchors.centerIn: parent
                width: 460
                height: Math.min(620, panelRoot.height - Theme.spaceXl * 2)
                radius: Theme.radiusLg
                color: Theme.elevated
                border.color: Theme.border
                border.width: 1
                visible: !panelRoot.showSocial

                TapHandler {}

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.margins: Theme.space

                        Text {
                            Layout.fillWidth: true
                            text: Tr.t("Edit profile")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeLg
                            font.weight: Font.Bold
                            color: Theme.textPrimary
                        }

                        Item {
                            implicitWidth: 24
                            implicitHeight: 24
                            HoverHandler { id: closeHover }
                            TapHandler { onSingleTapped: root.closeRequested() }
                            Icon {
                                anchors.centerIn: parent
                                width: 16
                                height: 16
                                name: "close"
                                color: closeHover.hovered ? Theme.textPrimary : Theme.textFaint
                            }
                        }
                    }

                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.leftMargin: Theme.space
                        Layout.rightMargin: Theme.space
                        contentWidth: width
                        contentHeight: form.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: form
                            width: parent.width
                            spacing: Theme.space

                            Text {
                                Layout.fillWidth: true
                                text: Tr.t("Information you add to your profile will be visible to everyone on and off TIDAL.")
                                wrapMode: Text.WordWrap
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                color: Theme.textMuted
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.space

                                CoverArt {
                                    Layout.preferredWidth: 64
                                    Layout.preferredHeight: 64
                                    radius: width / 2
                                    uuid: panelRoot.profile().avatarUrl || ""
                                    placeholderGlyph: "☺"
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spaceXs

                                    Text {
                                        text: Tr.t("Profile picture")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize
                                        font.weight: Font.DemiBold
                                        color: Theme.textPrimary
                                    }

                                    RowLayout {
                                        spacing: Theme.spaceSm

                                        SettingsButton {
                                            label: Tr.t("Choose picture")
                                            enabled: panelRoot.canEdit && !panelRoot.busy
                                            onClicked: pictureDialog.open()
                                        }

                                        SettingsButton {
                                            label: Tr.t("Delete")
                                            enabled: panelRoot.canEdit && !panelRoot.busy
                                            onClicked: panelRoot.deletePicture()
                                        }
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spaceXs

                                Text {
                                    text: Tr.t("Name")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSm
                                    font.weight: Font.DemiBold
                                    color: Theme.textSecondary
                                }

                                SettingsField {
                                    id: nameInput
                                    Layout.fillWidth: true
                                    text: panelRoot.initialProfile.name || ""
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spaceXs

                                Text {
                                    text: Tr.t("Username")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSm
                                    font.weight: Font.DemiBold
                                    color: Theme.textSecondary
                                }

                                SettingsField {
                                    id: handleInput
                                    Layout.fillWidth: true
                                    text: panelRoot.initialProfile.handle || ""
                                }

                                Text {
                                    text: Tr.t("Use only the letters a-z, numbers 0-9 and underscores.")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSm
                                    color: Theme.textFaint
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spaceXs

                                Text {
                                    text: Tr.t("Link")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSm
                                    font.weight: Font.DemiBold
                                    color: Theme.textSecondary
                                }

                                SettingsField {
                                    id: websiteInput
                                    Layout.fillWidth: true
                                    placeholder: Tr.t("Link")
                                    text: root.splitLinks(panelRoot.initialProfile.externalLinks || []).website
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spaceXs

                                Text {
                                    text: Tr.t("Bio")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSm
                                    font.weight: Font.DemiBold
                                    color: Theme.textSecondary
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 96
                                    radius: Theme.radiusXs
                                    color: Theme.inset
                                    border.color: bioInput.activeFocus ? Theme.accent : Theme.border
                                    border.width: 1
                                    opacity: panelRoot.canEdit ? 1 : 0.5

                                    TextEdit {
                                        id: bioInput
                                        anchors.fill: parent
                                        anchors.margins: Theme.spaceSm
                                        readOnly: !panelRoot.canEdit
                                        wrapMode: TextEdit.WordWrap
                                        text: panelRoot.initialProfile.bio || ""
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize
                                        color: Theme.textPrimary
                                        selectionColor: Theme.accent
                                        selectedTextColor: Theme.onAccent

                                        onTextChanged: {
                                            if (text.length > panelRoot.bioMax)
                                                text = text.substring(0, panelRoot.bioMax)
                                        }
                                    }
                                }

                                Text {
                                    text: panelRoot.canEdit
                                          ? (panelRoot.bioMax - bioInput.text.length) + " characters remaining"
                                          : "Bio editing is unavailable for this profile."
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSm
                                    color: Theme.textFaint
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 44
                                radius: Theme.radiusSm
                                color: socialRowHover.hovered ? Theme.hlMed : Theme.inset

                                HoverHandler { id: socialRowHover }
                                TapHandler { onSingleTapped: panelRoot.showSocial = true }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.spaceSm
                                    anchors.rightMargin: Theme.spaceSm

                                    Text {
                                        Layout.fillWidth: true
                                        text: Tr.t("Social media")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize
                                        color: Theme.textPrimary
                                    }

                                    Icon {
                                        Layout.preferredWidth: 14
                                        Layout.preferredHeight: 14
                                        name: "forward"
                                        color: Theme.textFaint
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: root.controller.error.length > 0
                                text: root.controller.error
                                wrapMode: Text.WordWrap
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                color: Theme.error
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.margins: Theme.space

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            implicitWidth: saveText.implicitWidth + Theme.spaceXl
                            implicitHeight: 36
                            radius: Theme.radiusFull
                            opacity: panelRoot.canEdit && !panelRoot.busy ? 1 : 0.4
                            color: Theme.textPrimary

                            TapHandler {
                                enabled: panelRoot.canEdit && !panelRoot.busy
                                onSingleTapped: panelRoot.save()
                            }

                            Text {
                                id: saveText
                                anchors.centerIn: parent
                                text: panelRoot.busy && panelRoot.pendingAction === "profile" ? "Saving…" : "Save"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                font.weight: Font.Bold
                                color: Theme.base
                            }
                        }
                    }
                }
            }

            // ---- Social media sub-screen -------------------------------
            Rectangle {
                anchors.centerIn: parent
                width: 440
                height: Math.min(560, panelRoot.height - Theme.spaceXl * 2)
                radius: Theme.radiusLg
                color: Theme.elevated
                border.color: Theme.border
                border.width: 1
                visible: panelRoot.showSocial

                TapHandler {}

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.margins: Theme.space

                        Item {
                            implicitWidth: 24
                            implicitHeight: 24
                            HoverHandler { id: backHover }
                            TapHandler { onSingleTapped: panelRoot.showSocial = false }
                            Icon {
                                anchors.centerIn: parent
                                width: 16
                                height: 16
                                name: "back"
                                color: backHover.hovered ? Theme.textPrimary : Theme.textFaint
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: Tr.t("Social media")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeLg
                            font.weight: Font.Bold
                            color: Theme.textPrimary
                        }

                        Item {
                            implicitWidth: 24
                            implicitHeight: 24
                            HoverHandler { id: closeHover2 }
                            TapHandler { onSingleTapped: root.closeRequested() }
                            Icon {
                                anchors.centerIn: parent
                                width: 16
                                height: 16
                                name: "close"
                                color: closeHover2.hovered ? Theme.textPrimary : Theme.textFaint
                            }
                        }
                    }

                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.leftMargin: Theme.space
                        Layout.rightMargin: Theme.space
                        Layout.bottomMargin: Theme.space
                        contentWidth: width
                        contentHeight: socialForm.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: socialForm
                            width: parent.width
                            spacing: Theme.space

                            Text {
                                Layout.fillWidth: true
                                text: Tr.t("Your public profile will show links to social media accounts you add here.")
                                wrapMode: Text.WordWrap
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                color: Theme.textMuted
                            }

                            Repeater {
                                id: socialRepeater
                                model: root.socialTypes

                                ColumnLayout {
                                    id: socialDelegate
                                    required property string modelData
                                    property alias value: fieldInput.text
                                    Layout.fillWidth: true
                                    spacing: Theme.spaceXs

                                    Text {
                                        text: root.socialLabels[socialDelegate.modelData]
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSm
                                        font.weight: Font.DemiBold
                                        color: Theme.textSecondary
                                    }

                                    SettingsField {
                                        id: fieldInput
                                        Layout.fillWidth: true
                                        placeholder: root.socialLabels[socialDelegate.modelData]
                                        text: root.splitLinks(panelRoot.initialProfile.externalLinks || [])
                                                  .socials[socialDelegate.modelData] || ""
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
