// Design tokens. Colours come from ThemeController (sone's derivation: the
// palette falls out of accent + background). Geometry and type are TIDAL's,
// taken from tidal.com's own design tokens.
pragma Singleton

import QtQuick
import me.unbk.klang

QtObject {
    id: theme

    property ThemeController controller: ThemeController {}

    // ---- surfaces -------------------------------------------------------
    readonly property color base: controller.bg_base
    readonly property color surface: controller.bg_surface
    readonly property color surfaceHover: controller.bg_surface_hover
    readonly property color elevated: controller.bg_elevated
    readonly property color sidebar: controller.bg_sidebar
    readonly property color overlay: controller.bg_overlay
    readonly property color inset: controller.bg_inset
    readonly property color insetHover: controller.bg_inset_hover
    readonly property color button: controller.bg_button
    readonly property color buttonHover: controller.bg_button_hover

    // ---- accent ---------------------------------------------------------
    readonly property color accent: controller.accent
    readonly property color accentHover: controller.accent_hover
    readonly property color onAccent: controller.accent_foreground

    // ---- text -----------------------------------------------------------
    readonly property color textPrimary: controller.text_primary
    readonly property color textSecondary: controller.text_secondary
    readonly property color textMuted: controller.text_muted
    readonly property color textFaint: controller.text_faint
    readonly property color textDisabled: controller.text_disabled

    // ---- lines and overlays ---------------------------------------------
    readonly property color border: controller.border_subtle
    readonly property color hlFaint: controller.hl_faint
    readonly property color hlMed: controller.hl_med
    readonly property color hlStrong: controller.hl_strong

    // ---- sliders --------------------------------------------------------
    readonly property color sliderTrack: controller.slider_track
    readonly property color sliderFill: controller.slider_fill
    readonly property color sliderBorder: controller.slider_border

    // ---- semantic -------------------------------------------------------
    readonly property color success: controller.success
    readonly property color error: controller.error
    readonly property color warning: controller.warning

    // ---- geometry, from tidal.com --------------------------------------
    readonly property int radiusXs: 4
    readonly property int radiusSm: 8
    readonly property int radius: 12
    readonly property int radiusLg: 16
    readonly property int radiusFull: 1000

    readonly property int sidebarWidth: 220
    readonly property int playerBarHeight: 88
    readonly property int cardSize: 174
    readonly property int rowHeight: 56
    readonly property int coverThumb: 40

    readonly property int spaceXs: 4
    readonly property int spaceSm: 8
    readonly property int space: 16
    readonly property int spaceLg: 24
    readonly property int spaceXl: 32

    // ---- type -----------------------------------------------------------
    // Square Sans Text is TIDAL's and will not resolve on a stock Fedora.
    readonly property string fontFamily: "Square Sans Text, Inter, Noto Sans, DejaVu Sans, sans-serif"
    /// For values that are copied rather than read: tokens, URLs, ports.
    readonly property string fontFamilyMono: "JetBrains Mono, Fira Code, DejaVu Sans Mono, monospace"
    readonly property string monoFamily: "monospace"

    readonly property int fontSizeSm: 12
    readonly property int fontSize: 14
    readonly property int fontSizeLg: 16
    readonly property int fontSizeHeading: 22
    readonly property int fontSizeDisplay: 42

    // Animations run only while the window has focus: a hover fade or a
    // spinner left running in the background keeps the GPU awake for a window
    // nobody is looking at (sone issue #191). Zero-length animations still
    // reach their end value, so bindings stay correct either way.
    readonly property bool animated: Qt.application.active
    readonly property int durationFast: animated ? 120 : 0
    readonly property int duration: animated ? 180 : 0
}
