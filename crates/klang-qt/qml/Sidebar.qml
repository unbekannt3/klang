// Left navigation rail. 220 px, matching tidal.com.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import me.unbk.klang

Rectangle {
    id: root

    /// Route key of the visible page.
    property string current: "home"
    /// JSON string or array of {uuid, title, numberOfTracks} from PlaylistsController.
    property var playlists: []

    signal navigate(string route)
    signal openPlaylist(string uuid, string title)

    implicitWidth: Theme.sidebarWidth
    color: Theme.sidebar

    function playlistRows() {
        if (typeof playlists === "string")
            return JSON.parse(playlists || "[]")
        return playlists || []
    }

    component NavItem: QQC2.ItemDelegate {
        id: item
        required property string route
        required property string label
        required property string iconName

        Layout.fillWidth: true
        height: 40
        hoverEnabled: true

        background: Rectangle {
            radius: Theme.radiusSm
            color: root.current === item.route ? Theme.hlMed
                 : item.hovered ? Theme.hlFaint
                 : "transparent"
        }

        contentItem: RowLayout {
            spacing: Theme.spaceSm

            Icon {
                Layout.leftMargin: Theme.spaceSm
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                name: item.iconName
                color: root.current === item.route ? Theme.textPrimary : Theme.textMuted
            }

            Text {
                Layout.fillWidth: true
                text: item.label
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.weight: root.current === item.route ? Font.DemiBold : Font.Normal
                color: root.current === item.route ? Theme.textPrimary : Theme.textSecondary
            }
        }

        onClicked: root.navigate(item.route)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spaceSm
        spacing: Theme.spaceSm

        // Wordmark
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spaceSm
            Layout.leftMargin: Theme.spaceSm
            Layout.bottomMargin: Theme.spaceSm
            spacing: Theme.spaceSm

            Image {
                source: "qrc:/qt/qml/me/unbk/klang/qml/klang.png"
                sourceSize.width: 24
                sourceSize.height: 24
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                smooth: true
            }

            Text {
                text: "klang"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeLg
                font.weight: Font.Bold
                font.letterSpacing: 1
                color: Theme.textPrimary
            }
        }

        NavItem { route: "home";      label: "Home";         iconName: "home" }
        NavItem { route: "explore";   label: "Explore";      iconName: "explore" }
        NavItem { route: "favorites"; label: "Loved Tracks"; iconName: "heart" }

        NavItem { route: "settings";  label: "Settings";     iconName: "settings" }

        // Divider
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spaceSm
            Layout.bottomMargin: Theme.spaceXs
            height: 1
            color: Theme.border
        }

        Text {
            Layout.leftMargin: Theme.spaceSm
            text: "PLAYLISTS"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm - 1
            font.weight: Font.DemiBold
            font.letterSpacing: 1.2
            color: Theme.textFaint
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            id: playlistView
            clip: true
            model: root.playlistRows()
            reuseItems: true
            spacing: 1

            HoverHandler { id: playlistHover }

            WheelScroller {
                view: playlistView
                rowHeight: 34
            }

            QQC2.ScrollBar.vertical: ThemedScrollBar {
                listHovered: playlistHover.hovered
            }

            delegate: QQC2.ItemDelegate {
                id: pl
                required property var modelData
                width: ListView.view.width
                height: 34
                hoverEnabled: true

                background: Rectangle {
                    radius: Theme.radiusSm
                    color: pl.hovered ? Theme.hlFaint : "transparent"
                }

                contentItem: Text {
                    leftPadding: Theme.spaceSm
                    text: pl.modelData.title
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    color: Theme.textSecondary
                }

                onClicked: root.openPlaylist(modelData.uuid, modelData.title)
            }
        }
    }

    // Hairline against the content area.
    Rectangle {
        anchors.right: parent.right
        width: 1
        height: parent.height
        color: Theme.border
    }
}
