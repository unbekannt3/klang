// Custom window chrome, so the titlebar carries the app's colours instead of
// Breeze's. The window is frameless; dragging and the window buttons go through
// QWindow's public slots, which QML can call directly.

import QtQuick
import QtQuick.Layouts
import me.unbk.klang

Rectangle {
    id: root

    required property var window

    implicitHeight: 38
    color: Theme.sidebar

    // The whole bar is the drag handle, except where a button sits on top.
    DragHandler {
        target: null
        grabPermissions: PointerHandler.CanTakeOverFromAnything
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
            Layout.leftMargin: Theme.space
            Layout.preferredWidth: 18
            Layout.preferredHeight: 18
            source: "qrc:/qt/qml/me/unbk/klang/qml/klang.png"
            sourceSize.width: 18
            sourceSize.height: 18
            smooth: true
        }

        Text {
            Layout.leftMargin: Theme.spaceSm
            text: "klang"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            font.weight: Font.DemiBold
            font.letterSpacing: 0.8
            color: Theme.textSecondary
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
