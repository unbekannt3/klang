// Custom window chrome, so the titlebar carries the app's colours instead of
// Breeze's. The window is frameless; dragging and the window buttons go through
// QWindow's public slots, which QML can call directly.

import QtQuick
import QtQuick.Layouts
import me.unbk.klang

Rectangle {
    id: root

    required property var window
    property bool canGoBack: false
    property string searchQuery: ""

    signal backRequested()
    signal searchSubmitted(string query)

    implicitHeight: 38
    color: Theme.sidebar

    // The whole bar is the drag handle, except where a button sits on top.
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
        property string glyph: ""
        /// Close gets the destructive hover colour.
        property bool destructive: false
        signal activated()

        implicitWidth: 40
        implicitHeight: root.height
        color: hover.hovered ? (destructive ? Theme.error : Theme.hlMed) : "transparent"

        HoverHandler { id: hover }
        TapHandler { onSingleTapped: btn.activated() }

        Text {
            anchors.centerIn: parent
            text: btn.glyph
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
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
            glyph: "‹"
            enabled: root.canGoBack
            opacity: root.canGoBack ? 1 : 0.3
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

            Text {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spaceSm
                anchors.verticalCenter: parent.verticalCenter
                text: "⌕"
                font.pixelSize: Theme.fontSize
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
                onAccepted: root.searchSubmitted(text)

                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: !search.text && !search.activeFocus
                    text: "Search"
                    font: search.font
                    color: Theme.textFaint
                }
            }
        }

        Item { Layout.fillWidth: true }

        WindowButton {
            glyph: "–"
            onActivated: root.window.showMinimized()
        }

        WindowButton {
            glyph: root.window.visibility === Window.Maximized ? "❐" : "□"
            onActivated: root.window.visibility === Window.Maximized
                         ? root.window.showNormal()
                         : root.window.showMaximized()
        }

        WindowButton {
            glyph: "✕"
            destructive: true
            onActivated: root.window.close()
        }
    }

    // Hairline under the bar.
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.border
    }
}
