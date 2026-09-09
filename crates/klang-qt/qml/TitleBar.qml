// A Wayland client cannot move itself, so dragging goes through
// QWindow::startSystemMove — a public slot, hence callable straight from QML.

import QtQuick
import QtQuick.Layouts
import me.unbk.klang

Rectangle {
    id: root

    required property var window
    property bool canGoBack: false
    property string searchQuery: ""
    property string avatarUrl: ""
    property string displayName: ""

    signal backRequested()
    signal searchSubmitted(string query)
    signal profileRequested()
    signal settingsRequested()
    signal logoutRequested()

    /// Put the caret in the search field, for the Ctrl+K shortcut.
    function focusSearch() {
        search.forceActiveFocus()
        search.selectAll()
    }

    implicitHeight: 38
    color: Theme.sidebar

    DragHandler {
        target: null
        onActiveChanged: if (active) root.window.startSystemMove()
    }

    TapHandler {
        onDoubleTapped: root.window.visibility === Window.Maximized
                        ? root.window.showNormal()
                        : root.window.showMaximized()
    }

    component WindowButton: Rectangle {
        id: btn
        property string iconName: ""
        property bool destructive: false
        property bool active: true
        signal activated()

        implicitWidth: 40
        implicitHeight: root.height
        opacity: btn.active ? 1 : 0.3
        color: hover.hovered && btn.active
               ? (destructive ? Theme.error : Theme.hlMed)
               : "transparent"

        HoverHandler { id: hover; enabled: btn.active }
        TapHandler { enabled: btn.active; onSingleTapped: btn.activated() }

        Icon {
            anchors.centerIn: parent
            width: 16
            height: 16
            name: btn.iconName
            color: hover.hovered && btn.destructive ? Theme.textPrimary : Theme.textSecondary
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Image {
            Layout.leftMargin: Theme.spaceSm
            Layout.preferredWidth: 18
            Layout.preferredHeight: 18
            source: "qrc:/qt/qml/me/unbk/klang/qml/klang.png"
            sourceSize.width: 18
            sourceSize.height: 18
            smooth: true
        }

        WindowButton {
            iconName: "back"
            active: root.canGoBack
            onActivated: root.backRequested()
        }

        Item { Layout.fillWidth: true }

        Rectangle {
            Layout.preferredWidth: Math.min(360, root.width * 0.32)
            Layout.preferredHeight: 26
            radius: Theme.radiusFull
            color: search.activeFocus ? Theme.elevated : Theme.inset
            border.color: search.activeFocus ? Theme.accent : "transparent"
            border.width: 1

            Icon {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spaceSm
                anchors.verticalCenter: parent.verticalCenter
                width: 14
                height: 14
                name: "search"
                color: Theme.textFaint
            }

            TextInput {
                id: search
                anchors.fill: parent
                anchors.leftMargin: Theme.space + Theme.spaceSm
                anchors.rightMargin: Theme.spaceSm
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                text: root.searchQuery
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                color: Theme.textPrimary
                selectionColor: Theme.accent
                selectedTextColor: Theme.onAccent
                onAccepted: {
                    debounce.stop()
                    root.searchSubmitted(text)
                }
                // Nothing else in the window takes focus on a click, so the
                // field would keep its focus ring for the rest of the session.
                Keys.onEscapePressed: search.focus = false
                // Search as you type, but only once typing pauses.
                onTextEdited: debounce.restart()

                Timer {
                    id: debounce
                    interval: 300
                    onTriggered: root.searchSubmitted(search.text)
                }

                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: !search.text && !search.activeFocus
                    text: Tr.t("Search")
                    font: search.font
                    color: Theme.textFaint
                }
            }
        }

        Item { Layout.fillWidth: true }

        UserMenu {
            Layout.rightMargin: Theme.spaceSm
            avatarUrl: root.avatarUrl
            displayName: root.displayName
            onProfileRequested: root.profileRequested()
            onSettingsRequested: root.settingsRequested()
            onLogoutRequested: root.logoutRequested()
        }

        WindowButton {
            iconName: "minimize"
            onActivated: root.window.showMinimized()
        }

        WindowButton {
            iconName: root.window.visibility === Window.Maximized ? "restore" : "maximize"
            onActivated: root.window.visibility === Window.Maximized
                         ? root.window.showNormal()
                         : root.window.showMaximized()
        }

        WindowButton {
            iconName: "close"
            destructive: true
            onActivated: root.window.close()
        }
    }


    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.border
    }
}
