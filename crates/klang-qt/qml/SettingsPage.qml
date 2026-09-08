import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import me.unbk.klang

Item {
    id: root

    Rectangle { anchors.fill: parent; color: Theme.base }

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: column.implicitHeight + Theme.spaceXl * 2
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        WheelScroller { view: flick; rowHeight: Theme.rowHeight }

        QQC2.ScrollBar.vertical: ThemedScrollBar { listHovered: pageHover.hovered }

        ColumnLayout {
            id: column
            x: Theme.spaceXl
            y: Theme.spaceXl
            width: Math.min(flick.width - Theme.spaceXl * 2, 720)
            spacing: Theme.spaceXl

            Text {
                text: "Settings"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeDisplay
                font.weight: Font.Bold
                color: Theme.textPrimary
            }

            Text {
                text: "Themes"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeHeading
                font.weight: Font.Bold
                color: Theme.textPrimary
            }

            ThemePicker { Layout.fillWidth: true }
        }
    }

    HoverHandler { id: pageHover }
}
