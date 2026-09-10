// Transparency panel: draws what is actually happening between the decoder
// and the DAC. Simplified from sone's SignalPathPanel/FlowDiagramBody — one
// fixed chain instead of a MIX/OS-mixer node, since the callout badges above
// already cover exclusive/bit-perfect state.
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import me.unbk.klang

Item {
    id: root

    required property var player  // PlayerController, for the source label
    required property var path    // SignalPathController
    property bool open: false
    signal closeRequested()

    visible: root.open
    enabled: root.open

    Keys.onEscapePressed: root.closeRequested()

    // Also on completion: a caller that builds this on demand hands it `open`
    // as an initial value, which is no property change to react to. `path`
    // may not be assigned yet when that first change arrives, so probing
    // waits for both.
    function probe() {
        if (!root.open || !root.path)
            return
        root.path.attach()
        root.path.refresh()
    }

    onOpenChanged: root.probe()
    onPathChanged: root.probe()
    Component.onCompleted: root.probe()

    // Mirrors the 2 s heartbeat pipeline_probe.rs was designed for — cheap
    // enough to poll, and ALSA state can change under us (device unplugged,
    // another app grabbing exclusive access).
    Timer {
        interval: 2000
        running: root.open
        repeat: true
        onTriggered: root.path.refresh()
    }

    readonly property var sp: JSON.parse((root.path.path_json || "") || "{}")
    readonly property bool hasResample: !!(root.sp.resampledFrom && root.sp.resampledTo)
    readonly property real userVol: root.sp.userVolume || 1.0
    readonly property real normFactor: root.sp.normGainFactor || 1.0
    readonly property bool volAltered: Math.abs(root.userVol - 1.0) > 0.001
        || (!!root.sp.volumeNormalization && Math.abs(root.normFactor - 1.0) > 0.001)
    readonly property bool isPristine: root.sp.backend === "DirectAlsa"
        && !!root.sp.exclusiveMode && !!root.sp.bitPerfect
        && !root.hasResample && !root.sp.formatFallbackFrom && !root.volAltered
    readonly property string verdictWord: !root.sp.backend ? "IDLE" : (root.isPristine ? "PRISTINE" : "ALTERED")
    readonly property color verdictColor: !root.sp.backend ? Theme.textFaint
        : (root.isPristine ? Theme.success : Theme.warning)

    function rateLabel(hz) {
        if (!hz)
            return "—"
        return (hz % 1000 === 0 ? (hz / 1000) : (hz / 1000).toFixed(1)) + " kHz"
    }

    function formatLabel(fmt) {
        return fmt || "—"
    }

    function bitDepthLabel(fmt) {
        if (!fmt)
            return ""
        const digits = String(fmt).match(/\d+/)
        return digits ? digits[0] + "-bit" : ""
    }

    function volumeLabel() {
        return Math.round(Math.cbrt(root.userVol) * 100) + "%"
    }

    function headline() {
        const sp = root.sp
        if (!sp.backend)
            return "No track playing"
        if (root.isPristine)
            return "Every source bit reaches the DAC untouched"
        if (root.hasResample)
            return "Resampled " + root.rateLabel(sp.resampledFrom) + " → " + root.rateLabel(sp.resampledTo)
        if (sp.formatFallbackFrom)
            return "DAC refused " + sp.formatFallbackFrom + " — fell back to " + sp.formatFallbackTo
        if (root.volAltered)
            return "Volume and/or ReplayGain are scaling samples"
        if (!sp.bitPerfect)
            return "Bit-perfect mode is off — pipeline at unity, not guaranteed"
        return "Pipeline pass-through"
    }

    component Badge: Rectangle {
        required property string label
        implicitWidth: badgeText.implicitWidth + Theme.space
        implicitHeight: 20
        radius: Theme.radiusFull
        color: Theme.hlFaint

        Text {
            id: badgeText
            anchors.centerIn: parent
            text: parent.label
            font.family: Theme.fontFamilyMono
            font.pixelSize: Theme.fontSizeSm - 1
            color: Theme.textSecondary
        }
    }

    component FlowNode: Rectangle {
        id: node
        required property string title
        required property string primary
        property string secondary: ""
        property string tertiary: ""
        property bool altered: false

        Layout.preferredWidth: 132
        Layout.preferredHeight: 92
        radius: Theme.radiusSm
        color: Theme.surface
        border.color: node.altered ? Theme.warning : Theme.border
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.spaceSm
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: node.title
                font.family: Theme.fontFamilyMono
                font.pixelSize: Theme.fontSizeSm - 1
                color: Theme.textFaint
            }
            Text {
                Layout.fillWidth: true
                text: node.primary
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.weight: Font.DemiBold
                color: Theme.textPrimary
            }
            Text {
                Layout.fillWidth: true
                visible: node.secondary.length > 0
                text: node.secondary
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                color: Theme.textSecondary
            }
            Text {
                Layout.fillWidth: true
                visible: node.tertiary.length > 0
                text: node.tertiary
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                color: Theme.textFaint
            }
        }
    }

    // A connector between two nodes; colour is the only thing that tells
    // "altered" apart from "pass-through" here (sone shows a badge per
    // alteration instead — dropped to keep this to the chain the task asked
    // for).
    component FlowArrow: Item {
        id: arrow
        required property color lineColor
        Layout.fillWidth: true
        Layout.preferredHeight: 16
        Layout.alignment: Qt.AlignVCenter

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: arrow.lineColor
                strokeWidth: 2
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg {
                    path: {
                        const w = Math.max(arrow.width, 16)
                        const h = arrow.height / 2
                        return `M 2 ${h} L ${w - 10} ${h} M ${w - 14} ${h - 6} L ${w - 2} ${h} L ${w - 14} ${h + 6}`
                    }
                }
            }
        }
    }

    ModalShield {
        blocksPage: true
        scrim: Qt.alpha(Theme.overlay, 0.55)
        onDismissed: root.closeRequested()
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: 720
        height: content.implicitHeight + Theme.spaceLg * 2
        radius: Theme.radiusLg
        color: Theme.elevated
        border.color: Theme.border
        border.width: 1

        // Claims clicks landing on the panel so they don't fall through to
        // the scrim behind it.
        // Keeps clicks on the panel from also reaching the scrim.
        ModalShield {}

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spaceLg
            spacing: Theme.space

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceSm

                Rectangle {
                    implicitWidth: 10
                    implicitHeight: 10
                    radius: 5
                    color: root.verdictColor
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        text: root.verdictWord
                        font.family: Theme.fontFamilyMono
                        font.pixelSize: Theme.fontSize
                        font.weight: Font.DemiBold
                        font.letterSpacing: 2
                        color: root.verdictColor
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.headline()
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        color: Theme.textMuted
                    }
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

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceSm

                Badge { label: Tr.t("EXCLUSIVE"); visible: !!root.sp.exclusiveMode }
                Badge { label: Tr.t("BIT-PERFECT"); visible: !!root.sp.bitPerfect }
                Badge { label: (root.sp.backend || "").toUpperCase(); visible: !!root.sp.backend }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spaceSm
                spacing: Theme.spaceSm

                FlowNode {
                    title: Tr.t("SOURCE")
                    primary: root.player.quality.length > 0 ? root.player.quality : "idle"
                    secondary: root.player.track_id !== 0 ? root.player.title : "no track"
                }
                FlowArrow { lineColor: Theme.hlStrong }
                FlowNode {
                    title: Tr.t("DECODER")
                    primary: root.formatLabel(root.sp.decodedFormat)
                    secondary: root.rateLabel(root.sp.decodedRate) + " · " + root.bitDepthLabel(root.sp.decodedFormat)
                    tertiary: root.sp.decodedChannels ? root.sp.decodedChannels + "ch" : ""
                }
                FlowArrow {
                    visible: root.hasResample
                    lineColor: Theme.warning
                }
                FlowNode {
                    visible: root.hasResample
                    title: Tr.t("RESAMPLER")
                    primary: root.rateLabel(root.sp.resampledFrom) + " → " + root.rateLabel(root.sp.resampledTo)
                    altered: true
                }
                FlowArrow { lineColor: (root.hasResample || root.volAltered) ? Theme.warning : Theme.hlStrong }
                FlowNode {
                    title: Tr.t("VOLUME")
                    primary: root.volAltered ? root.volumeLabel() : "unity"
                    secondary: root.sp.volumeNormalization ? "ReplayGain on" : "ReplayGain off"
                    altered: root.volAltered
                }
                FlowArrow { lineColor: root.volAltered ? Theme.warning : Theme.hlStrong }
                FlowNode {
                    title: Tr.t("ALSA DEVICE")
                    primary: root.formatLabel(root.sp.outputFormat)
                    secondary: root.rateLabel(root.sp.outputRate) + " · " + root.bitDepthLabel(root.sp.outputFormat)
                    tertiary: root.sp.dac ? root.sp.dac.cardName : (root.sp.outputDevice || "")
                }
            }
        }
    }
}
