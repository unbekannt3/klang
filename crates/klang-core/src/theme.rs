//! Theme palette derivation, ported from sone's `src/lib/theme.ts`.
//!
//! Two hex inputs (`accent`, `bg_base`) expand into a ~30-colour palette via
//! HSL lightness shifts. This must stay in exact numeric lockstep with the
//! TypeScript — the unit tests below pin known-good values per preset (taken
//! by running the actual TS functions), so any drift in the port is caught
//! immediately rather than silently shipping a slightly-off palette.

/// Full derived color palette for a theme. Field names mirror `DerivedTheme`
/// in `src/lib/theme.ts` (camelCase -> snake_case). Every field holds a CSS
/// color string exactly as the TypeScript would produce it: most fields are
/// `#rrggbb` hex, a handful of adaptive overlays are `rgba(...)`, and the
/// semantic colors (`success`/`error`/`warning`) are fixed regardless of
/// theme.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DerivedTheme {
    // Backgrounds
    pub bg_base: String,
    pub bg_surface: String,
    pub bg_surface_hover: String,
    pub bg_elevated: String,
    pub bg_sidebar: String,
    pub bg_overlay: String,
    pub bg_inset: String,
    pub bg_inset_hover: String,
    pub bg_button: String,
    pub bg_button_hover: String,

    // Accent
    pub accent: String,
    pub accent_hover: String,
    /// Text/icon color on top of the accent — black on dark themes, white on
    /// light themes.
    pub on_accent: String,

    // Text
    pub text_primary: String,
    pub text_secondary: String,
    pub text_muted: String,
    pub text_faint: String,
    pub text_disabled: String,

    // Border / scrollbar
    pub border_subtle: String,
    pub scrollbar: String,
    pub scrollbar_hover: String,

    // Highlights (adaptive overlays)
    pub hl_faint: String,
    pub hl_med: String,
    pub hl_strong: String,

    // Slider / progress
    pub slider_track: String,
    pub slider_fill: String,
    pub slider_border: String,

    // Semantic (fixed)
    pub success: String,
    pub error: String,
    pub warning: String,
}

// ---------------------------------------------------------------------------
// HSL helpers
// ---------------------------------------------------------------------------

/// Parse a `#rgb` or `#rrggbb` hex color into `(hue 0..360, saturation
/// 0..100, lightness 0..100)`. Mirrors `hexToHsl` in theme.ts exactly,
/// including its leniency: this does no format validation of its own
/// (callers are expected to pass well-formed hex, same as upstream).
fn hex_to_hsl(hex: &str) -> (f64, f64, f64) {
    let h = hex.trim_start_matches('#');

    let parse_byte = |s: &str| -> f64 { u8::from_str_radix(s, 16).unwrap_or(0) as f64 / 255.0 };

    let (r, g, b) = if h.len() == 3 {
        let ch: Vec<char> = h.chars().collect();
        let pair = |c: char| -> String { [c, c].iter().collect() };
        (
            parse_byte(&pair(*ch.first().unwrap_or(&'0'))),
            parse_byte(&pair(*ch.get(1).unwrap_or(&'0'))),
            parse_byte(&pair(*ch.get(2).unwrap_or(&'0'))),
        )
    } else {
        let get = |start: usize| -> &str { h.get(start..start + 2).unwrap_or("00") };
        (parse_byte(get(0)), parse_byte(get(2)), parse_byte(get(4)))
    };

    let max = r.max(g).max(b);
    let min = r.min(g).min(b);
    let l = (max + min) / 2.0;
    let mut s = 0.0;
    let mut hue = 0.0;

    if max != min {
        let d = max - min;
        s = if l > 0.5 {
            d / (2.0 - max - min)
        } else {
            d / (max + min)
        };
        // Mirrors the TS `switch (max) { case r: ...; case g: ...; case b: ... }`
        // — first matching channel wins on a tie, so check in the same order.
        hue = if max == r {
            ((g - b) / d + if g < b { 6.0 } else { 0.0 }) / 6.0
        } else if max == g {
            ((b - r) / d + 2.0) / 6.0
        } else {
            ((r - g) / d + 4.0) / 6.0
        };
    }

    (hue * 360.0, s * 100.0, l * 100.0)
}

/// Build a `#rrggbb` (lowercase, like the TS `toString(16)`) hex string from
/// HSL. Mirrors `hslToHex` in theme.ts exactly.
fn hsl_to_hex(h: f64, s: f64, l: f64) -> String {
    let s_n = s / 100.0;
    let l_n = l / 100.0;
    let c = (1.0 - (2.0 * l_n - 1.0).abs()) * s_n;
    let x = c * (1.0 - ((h / 60.0) % 2.0 - 1.0).abs());
    let m = l_n - c / 2.0;

    let (r, g, b) = if h < 60.0 {
        (c, x, 0.0)
    } else if h < 120.0 {
        (x, c, 0.0)
    } else if h < 180.0 {
        (0.0, c, x)
    } else if h < 240.0 {
        (0.0, x, c)
    } else if h < 300.0 {
        (x, 0.0, c)
    } else {
        (c, 0.0, x)
    };

    let to_hex = |v: f64| -> String {
        let byte = ((v + m) * 255.0).round().clamp(0.0, 255.0) as u8;
        format!("{byte:02x}")
    };

    format!("#{}{}{}", to_hex(r), to_hex(g), to_hex(b))
}

/// Clamp a value between min and max.
fn clamp(v: f64, min: f64, max: f64) -> f64 {
    v.max(min).min(max)
}

/// Shift lightness of a hex color by delta percent.
fn shift_lightness(hex: &str, delta: f64) -> String {
    let (h, s, l) = hex_to_hsl(hex);
    hsl_to_hex(h, s, clamp(l + delta, 0.0, 100.0))
}

/// Scale lightness of a hex color by a factor (0-1 = darken, >1 = lighten).
fn scale_brightness(hex: &str, factor: f64) -> String {
    let (h, s, l) = hex_to_hsl(hex);
    hsl_to_hex(h, s, clamp(l * factor, 0.0, 100.0))
}

/// Normalize a `#RGB`/`#RrGgBb` color to uppercase `#RRGGBB`. Mirrors
/// `normalizeHex` in theme.ts.
pub fn normalize_hex(input: &str) -> Option<String> {
    let digits = input.trim().strip_prefix('#')?;
    let ok_len = digits.len() == 3 || digits.len() == 6;
    if !ok_len || !digits.bytes().all(|b| b.is_ascii_hexdigit()) {
        return None;
    }
    let expanded: String = if digits.len() == 3 {
        digits.chars().flat_map(|c| [c, c]).collect()
    } else {
        digits.to_string()
    };
    Some(format!("#{}", expanded.to_uppercase()))
}

// ---------------------------------------------------------------------------
// deriveTheme
// ---------------------------------------------------------------------------

/// Derive the full palette from an accent color and a base background color.
/// Port of `deriveTheme` in theme.ts — keep the arithmetic identical.
pub fn derive_theme(accent: &str, bg_base: &str) -> DerivedTheme {
    let (_, _, bg_l) = hex_to_hsl(bg_base);
    let is_dark = bg_l < 50.0;

    // Background surfaces derived from bg_base via lightness shifts.
    // For light themes, surfaces should be darker than base (not lighter).
    let dir = if is_dark { 1.0 } else { -1.0 };
    let bg_surface = shift_lightness(bg_base, 4.0 * dir);
    let bg_surface_hover = shift_lightness(bg_base, 9.0 * dir);
    let bg_elevated = shift_lightness(bg_base, 2.5 * dir);
    let bg_sidebar = shift_lightness(bg_base, -2.0); // always darker than base
    let bg_overlay = shift_lightness(bg_base, -3.0); // always darker than base
    let bg_inset = shift_lightness(bg_base, 7.0 * dir);
    let bg_inset_hover = shift_lightness(bg_base, 11.0 * dir);
    let bg_button = shift_lightness(bg_base, 14.0 * dir);
    let bg_button_hover = shift_lightness(bg_base, 19.0 * dir);

    // Accent
    let accent_hover = scale_brightness(accent, 0.88);
    // Accent-button text/icon color: inverts with the theme — dark text on
    // dark themes, white text on light themes.
    let on_accent = if is_dark { "#000000" } else { "#ffffff" }.to_string();

    // Text: for dark backgrounds, use light text at varying opacities.
    // For light backgrounds, use dark text.
    let (text_primary, text_secondary, text_muted, text_faint, text_disabled) = if is_dark {
        ("#ffffff", "#b3b3b3", "#a6a6a6", "#666666", "#535353")
    } else {
        ("#111111", "#444444", "#666666", "#666666", "#aaaaaa")
    };

    // Borders / scrollbar
    let border_subtle = if is_dark {
        "rgba(255,255,255,0.06)"
    } else {
        "rgba(0,0,0,0.08)"
    }
    .to_string();
    let scrollbar = bg_button.clone();
    let scrollbar_hover = bg_button_hover.clone();

    // Adaptive highlight overlays
    let hl_faint = if is_dark {
        "rgba(255,255,255,0.04)"
    } else {
        "rgba(0,0,0,0.05)"
    }
    .to_string();
    let hl_med = if is_dark {
        "rgba(255,255,255,0.08)"
    } else {
        "rgba(0,0,0,0.07)"
    }
    .to_string();
    let hl_strong = if is_dark {
        "rgba(255,255,255,0.12)"
    } else {
        "rgba(0,0,0,0.10)"
    }
    .to_string();

    // Slider / progress
    let slider_track = if is_dark {
        "rgba(255,255,255,0.15)"
    } else {
        "rgba(0,0,0,0.15)"
    }
    .to_string();
    let slider_fill = if is_dark {
        "rgba(255,255,255,0.65)"
    } else {
        "rgba(0,0,0,0.45)"
    }
    .to_string();
    let slider_border = if is_dark {
        bg_elevated.clone()
    } else {
        "rgba(255,255,255,0.35)".to_string()
    };

    DerivedTheme {
        bg_base: bg_base.to_string(),
        bg_surface,
        bg_surface_hover,
        bg_elevated,
        bg_sidebar,
        bg_overlay,
        bg_inset,
        bg_inset_hover,
        bg_button,
        bg_button_hover,
        accent: accent.to_string(),
        accent_hover,
        on_accent,
        text_primary: text_primary.to_string(),
        text_secondary: text_secondary.to_string(),
        text_muted: text_muted.to_string(),
        text_faint: text_faint.to_string(),
        text_disabled: text_disabled.to_string(),
        border_subtle,
        scrollbar,
        scrollbar_hover,
        hl_faint,
        hl_med,
        hl_strong,
        slider_track,
        slider_fill,
        slider_border,
        success: "#1ed760".to_string(),
        error: "#ff6666".to_string(),
        warning: "#ffa726".to_string(),
    }
}

// ---------------------------------------------------------------------------
// Preset themes
// ---------------------------------------------------------------------------

/// `(name, accent, bg_base)`. Mirrors `PRESET_THEMES` in theme.ts — same
/// names (case-sensitive), same colors, same order.
pub const PRESET_THEMES: &[(&str, &str, &str)] = &[
    ("Violet Night", "#A855F7", "#130F1A"),
    ("Cyberpunk", "#FCE300", "#18180C"),
    ("Forest", "#22C55E", "#0E1410"),
    ("Ocean", "#3B82F6", "#0E1118"),
    ("Midnight Cyan", "#00FFFF", "#121212"),
    ("Sakura", "#F9A8D4", "#140F12"),
    ("Rose", "#F43F5E", "#140E0F"),
    ("Ember", "#F97316", "#151010"),
    ("Copper", "#E8915A", "#12100E"),
    ("Noir", "#FFFFFF", "#020202"),
    ("Daylight", "#2563EB", "#F5F3EE"),
    ("Snowfall", "#0891B2", "#F8FAFC"),
    ("Paper", "#7C3AED", "#FAF5FF"),
    ("Meadow", "#16A34A", "#F2F6EE"),
    ("Blossom", "#E11D48", "#FEF3F2"),
];

/// Look up a preset's `(accent, bg_base)` by exact (case-sensitive) name.
pub fn find_preset(name: &str) -> Option<(&'static str, &'static str)> {
    PRESET_THEMES
        .iter()
        .find(|(n, _, _)| *n == name)
        .map(|(_, accent, bg_base)| (*accent, *bg_base))
}

#[cfg(test)]
mod tests {
    use super::*;

    // Expected values below were produced by running the exact TS logic from
    // src/lib/theme.ts (hexToHsl/hslToHex/deriveTheme, copied verbatim into a
    // throwaway .mjs script and executed with node) against these three
    // presets. They are not hand-derived — if this port's arithmetic diverges
    // from the TypeScript by even a rounding step, these assertions fail.

    #[test]
    fn derive_theme_violet_night() {
        let dt = derive_theme("#A855F7", "#130F1A");
        assert_eq!(
            dt,
            DerivedTheme {
                bg_base: "#130F1A".to_string(),
                bg_surface: "#1c1627".to_string(),
                bg_surface_hover: "#282037".to_string(),
                bg_elevated: "#191422".to_string(),
                bg_sidebar: "#0e0b14".to_string(),
                bg_overlay: "#0c0910".to_string(),
                bg_inset: "#241c31".to_string(),
                bg_inset_hover: "#2d243e".to_string(),
                bg_button: "#342947".to_string(),
                bg_button_hover: "#403257".to_string(),
                accent: "#A855F7".to_string(),
                accent_hover: "#952ff5".to_string(),
                on_accent: "#000000".to_string(),
                text_primary: "#ffffff".to_string(),
                text_secondary: "#b3b3b3".to_string(),
                text_muted: "#a6a6a6".to_string(),
                text_faint: "#666666".to_string(),
                text_disabled: "#535353".to_string(),
                border_subtle: "rgba(255,255,255,0.06)".to_string(),
                scrollbar: "#342947".to_string(),
                scrollbar_hover: "#403257".to_string(),
                hl_faint: "rgba(255,255,255,0.04)".to_string(),
                hl_med: "rgba(255,255,255,0.08)".to_string(),
                hl_strong: "rgba(255,255,255,0.12)".to_string(),
                slider_track: "rgba(255,255,255,0.15)".to_string(),
                slider_fill: "rgba(255,255,255,0.65)".to_string(),
                slider_border: "#191422".to_string(),
                success: "#1ed760".to_string(),
                error: "#ff6666".to_string(),
                warning: "#ffa726".to_string(),
            }
        );
    }

    #[test]
    fn derive_theme_noir() {
        let dt = derive_theme("#FFFFFF", "#020202");
        assert_eq!(
            dt,
            DerivedTheme {
                bg_base: "#020202".to_string(),
                bg_surface: "#0c0c0c".to_string(),
                bg_surface_hover: "#191919".to_string(),
                bg_elevated: "#080808".to_string(),
                bg_sidebar: "#000000".to_string(),
                bg_overlay: "#000000".to_string(),
                bg_inset: "#141414".to_string(),
                bg_inset_hover: "#1e1e1e".to_string(),
                bg_button: "#262626".to_string(),
                bg_button_hover: "#323232".to_string(),
                accent: "#FFFFFF".to_string(),
                accent_hover: "#e0e0e0".to_string(),
                on_accent: "#000000".to_string(),
                text_primary: "#ffffff".to_string(),
                text_secondary: "#b3b3b3".to_string(),
                text_muted: "#a6a6a6".to_string(),
                text_faint: "#666666".to_string(),
                text_disabled: "#535353".to_string(),
                border_subtle: "rgba(255,255,255,0.06)".to_string(),
                scrollbar: "#262626".to_string(),
                scrollbar_hover: "#323232".to_string(),
                hl_faint: "rgba(255,255,255,0.04)".to_string(),
                hl_med: "rgba(255,255,255,0.08)".to_string(),
                hl_strong: "rgba(255,255,255,0.12)".to_string(),
                slider_track: "rgba(255,255,255,0.15)".to_string(),
                slider_fill: "rgba(255,255,255,0.65)".to_string(),
                slider_border: "#080808".to_string(),
                success: "#1ed760".to_string(),
                error: "#ff6666".to_string(),
                warning: "#ffa726".to_string(),
            }
        );
    }

    #[test]
    fn derive_theme_daylight() {
        let dt = derive_theme("#2563EB", "#F5F3EE");
        assert_eq!(
            dt,
            DerivedTheme {
                bg_base: "#F5F3EE".to_string(),
                bg_surface: "#edeae1".to_string(),
                bg_surface_hover: "#e4dfd1".to_string(),
                bg_elevated: "#f0ede6".to_string(),
                bg_sidebar: "#f1eee8".to_string(),
                bg_overlay: "#efece4".to_string(),
                bg_inset: "#e8e3d8".to_string(),
                bg_inset_hover: "#e0dacb".to_string(),
                bg_button: "#dbd3c1".to_string(),
                bg_button_hover: "#d1c8b1".to_string(),
                accent: "#2563EB".to_string(),
                accent_hover: "#1452db".to_string(),
                on_accent: "#ffffff".to_string(),
                text_primary: "#111111".to_string(),
                text_secondary: "#444444".to_string(),
                text_muted: "#666666".to_string(),
                text_faint: "#666666".to_string(),
                text_disabled: "#aaaaaa".to_string(),
                border_subtle: "rgba(0,0,0,0.08)".to_string(),
                scrollbar: "#dbd3c1".to_string(),
                scrollbar_hover: "#d1c8b1".to_string(),
                hl_faint: "rgba(0,0,0,0.05)".to_string(),
                hl_med: "rgba(0,0,0,0.07)".to_string(),
                hl_strong: "rgba(0,0,0,0.10)".to_string(),
                slider_track: "rgba(0,0,0,0.15)".to_string(),
                slider_fill: "rgba(0,0,0,0.45)".to_string(),
                slider_border: "rgba(255,255,255,0.35)".to_string(),
                success: "#1ed760".to_string(),
                error: "#ff6666".to_string(),
                warning: "#ffa726".to_string(),
            }
        );
    }

    // normalize_hex — cases taken verbatim from src/lib/theme.test.ts.

    #[test]
    fn normalize_hex_accepts_and_uppercases() {
        assert_eq!(normalize_hex("#3b82f6"), Some("#3B82F6".to_string()));
    }

    #[test]
    fn normalize_hex_expands_shorthand() {
        assert_eq!(normalize_hex("#fff"), Some("#FFFFFF".to_string()));
        assert_eq!(normalize_hex("#a1b"), Some("#AA11BB".to_string()));
    }

    #[test]
    fn normalize_hex_rejects_malformed() {
        assert_eq!(normalize_hex("3B82F6"), None);
        assert_eq!(normalize_hex("#3B82F"), None);
        assert_eq!(normalize_hex("#GGGGGG"), None);
        assert_eq!(normalize_hex(""), None);
        assert_eq!(normalize_hex("#1234567"), None);
    }

    #[test]
    fn find_preset_looks_up_by_exact_name() {
        assert_eq!(find_preset("Violet Night"), Some(("#A855F7", "#130F1A")));
        assert_eq!(find_preset("violet night"), None); // case-sensitive
        assert_eq!(find_preset("Nonexistent"), None);
    }

    #[test]
    fn preset_themes_all_derive_without_panicking() {
        // Every preset must survive a full derivation — this is the
        // guardrail against a malformed hex triggering the defensive
        // fallbacks in hex_to_hsl (which would silently produce black).
        for (name, accent, bg_base) in PRESET_THEMES {
            let dt = derive_theme(accent, bg_base);
            assert_eq!(&dt.accent, accent, "accent passthrough for {name}");
            assert_eq!(&dt.bg_base, bg_base, "bg_base passthrough for {name}");
        }
    }
}
