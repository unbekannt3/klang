// Vector icons drawn to TIDAL's proportions: 24px grid, 1.6px strokes, round caps.
// Drawn rather than shipped so they stay crisp at any scale and carry no assets.

import QtQuick
import QtQuick.Shapes
import me.unbk.klang

Item {
    id: root

    required property string name
    property color color: Theme.textSecondary
    property real weight: 1.6

    implicitWidth: 24
    implicitHeight: 24

    readonly property real u: Math.min(width, height) / 24

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        layer.enabled: true
        layer.samples: 4

        // Filled glyphs: play, pause, skip, previous.
        ShapePath {
            fillColor: root.color
            strokeWidth: -1
            PathSvg {
                path: {
                    const u = root.u
                    const s = (d) => d.replace(/([\d.-]+)/g, (m) => (parseFloat(m) * u).toFixed(2))
                    switch (root.name) {
                    case "play":
                        return s("M 8 5 L 19 12 L 8 19 Z")
                    case "pause":
                        return s("M 7.5 5 L 10.5 5 L 10.5 19 L 7.5 19 Z M 13.5 5 L 16.5 5 L 16.5 19 L 13.5 19 Z")
                    case "next":
                        return s("M 6 5 L 15 12 L 6 19 Z M 16.5 5 L 19 5 L 19 19 L 16.5 19 Z")
                    case "previous":
                        return s("M 18 5 L 9 12 L 18 19 Z M 5 5 L 7.5 5 L 7.5 19 L 5 19 Z")
                    case "heart-filled":
                        return s("M 12 20 C 12 20 3 14.5 3 8.8 C 3 6.1 5.1 4 7.7 4 C 9.5 4 11.1 5 12 6.5 C 12.9 5 14.5 4 16.3 4 C 18.9 4 21 6.1 21 8.8 C 21 14.5 12 20 12 20 Z")
                    }
                    return ""
                }
            }
        }

        // Stroked glyphs.
        ShapePath {
            strokeColor: root.color
            strokeWidth: root.weight * root.u
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg {
                path: {
                    const u = root.u
                    const s = (d) => d.replace(/([\d.-]+)/g, (m) => (parseFloat(m) * u).toFixed(2))
                    switch (root.name) {
                    case "shuffle":
                        return s("M 4 7 L 8 7 L 16 17 L 20 17 M 4 17 L 8 17 L 11 13 M 15 9 L 16 7 L 20 7 M 17.5 4.5 L 20 7 L 17.5 9.5 M 17.5 14.5 L 20 17 L 17.5 19.5")
                    case "repeat":
                        return s("M 7 6 L 17 6 L 17 6 M 17 6 L 20 6 L 20 11 M 4 13 L 4 18 L 17 18 M 6.5 3.5 L 4 6 L 6.5 8.5 M 17.5 15.5 L 20 18 L 17.5 20.5 M 4 6 L 7 6 M 20 18 L 17 18")
                    case "heart":
                        return s("M 12 20 C 12 20 3 14.5 3 8.8 C 3 6.1 5.1 4 7.7 4 C 9.5 4 11.1 5 12 6.5 C 12.9 5 14.5 4 16.3 4 C 18.9 4 21 6.1 21 8.8 C 21 14.5 12 20 12 20 Z")
                    case "queue":
                        return s("M 4 7 L 15 7 M 4 12 L 15 12 M 4 17 L 11 17 M 18 10 L 18 19 M 18 10 L 21 9 L 21 18")
                    case "volume":
                        return s("M 4 9 L 7 9 L 11 5 L 11 19 L 7 15 L 4 15 Z M 15 9.5 C 16.2 10.8 16.2 13.2 15 14.5 M 18 7 C 20.3 9.5 20.3 14.5 18 17")
                    case "muted":
                        return s("M 4 9 L 7 9 L 11 5 L 11 19 L 7 15 L 4 15 Z M 15.5 9.5 L 20.5 14.5 M 20.5 9.5 L 15.5 14.5")
                    case "search":
                        return s("M 10.5 4 A 6.5 6.5 0 1 0 10.5 17 A 6.5 6.5 0 1 0 10.5 4 M 15.5 15.5 L 20 20")
                    case "home":
                        return s("M 4 11 L 12 4 L 20 11 M 6 10 L 6 20 L 18 20 L 18 10")
                    case "explore":
                        return s("M 12 3 A 9 9 0 1 0 12 21 A 9 9 0 1 0 12 3 M 15.5 8.5 L 13.5 13.5 L 8.5 15.5 L 10.5 10.5 Z")
                    case "back":
                        return s("M 15 5 L 8 12 L 15 19")
                    case "forward":
                        return s("M 9 5 L 16 12 L 9 19")
                    case "close":
                        return s("M 6 6 L 18 18 M 18 6 L 6 18")
                    case "minimize":
                        return s("M 6 12 L 18 12")
                    case "maximize":
                        return s("M 6 6 L 18 6 L 18 18 L 6 18 Z")
                    case "restore":
                        return s("M 8 8 L 8 5 L 19 5 L 19 16 L 16 16 M 5 8 L 16 8 L 16 19 L 5 19 Z")
                    case "more":
                        return s("M 6 12 L 6.01 12 M 12 12 L 12.01 12 M 18 12 L 18.01 12")
                    case "playlist":
                        return s("M 4 6 L 14 6 M 4 11 L 14 11 M 4 16 L 10 16 M 17 8 L 17 19 M 17 8 L 21 7 L 21 18")
                    }
                    return ""
                }
            }
        }
    }
}
