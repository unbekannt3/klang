//! Palette derived from accent + background, ported from sone's theme.ts.
//!
//! Unlike the other controllers this one does no I/O and needs no
//! `klang_core::runtime` round-trip: `klang_core::theme::derive_theme` is
//! pure, synchronous HSL math, so `apply_preset`/`apply_custom` compute the
//! palette and push it straight onto the properties QML binds to.

use cxx_qt_lib::QString;
use klang_core::theme::{self, DerivedTheme};
use std::pin::Pin;

/// Preset shown before the user (or a saved theme file) picks anything.
const DEFAULT_PRESET: &str = "Violet Night";

/// The name `deriveTheme`'s caller uses for a theme that isn't one of the
/// named presets. Mirrors the `"Custom"` display name in `src/lib/theme.ts`
/// (`resolveThemeFile`'s `CUSTOM_PRESET` branch).
const CUSTOM_PRESET_NAME: &str = "Custom";

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(QString, preset_name)]
        #[qproperty(QString, custom_accent)]
        #[qproperty(QString, custom_background)]
        // Backgrounds
        #[qproperty(QString, bg_base)]
        #[qproperty(QString, bg_surface)]
        #[qproperty(QString, bg_surface_hover)]
        #[qproperty(QString, bg_elevated)]
        #[qproperty(QString, bg_sidebar)]
        #[qproperty(QString, bg_overlay)]
        #[qproperty(QString, bg_inset)]
        #[qproperty(QString, bg_inset_hover)]
        #[qproperty(QString, bg_button)]
        #[qproperty(QString, bg_button_hover)]
        // Accent
        #[qproperty(QString, accent)]
        #[qproperty(QString, accent_hover)]
        // Named `accent_foreground` here (not `on_accent`, unlike the core
        // `DerivedTheme::on_accent` field it mirrors): cxx-qt auto-generates
        // an `on_<signal>` connect-helper for every signal, so a property
        // literally called `on_accent` collides with the helper generated
        // for the `accent` property's own `accent_changed` notify signal
        // (`E0592 duplicate definitions with name on_accent_changed`). Do
        // not rename this back to `on_accent`.
        #[qproperty(QString, accent_foreground)]
        // Text
        #[qproperty(QString, text_primary)]
        #[qproperty(QString, text_secondary)]
        #[qproperty(QString, text_muted)]
        #[qproperty(QString, text_faint)]
        #[qproperty(QString, text_disabled)]
        #[qproperty(QString, border_subtle)]
        #[qproperty(QString, border_strong)]
        // Highlights (adaptive overlays)
        #[qproperty(QString, hl_faint)]
        #[qproperty(QString, hl_med)]
        #[qproperty(QString, hl_strong)]
        // Slider / progress
        #[qproperty(QString, slider_track)]
        #[qproperty(QString, slider_fill)]
        #[qproperty(QString, slider_border)]
        // Semantic (fixed)
        #[qproperty(QString, success)]
        #[qproperty(QString, error)]
        #[qproperty(QString, warning)]
        type ThemeController = super::ThemeControllerRust;

        /// Switch to a built-in preset by exact (case-sensitive) name. A
        /// name that isn't one of `PRESET_THEMES` leaves the current theme
        /// untouched.
        /// Load the saved theme. Call once at start-up.
        #[qinvokable]
        fn restore(self: Pin<&mut ThemeController>);

        #[qinvokable]
        fn apply_preset(self: Pin<&mut ThemeController>, name: &QString);

        /// Derive and apply a custom theme from an accent + base-background
        /// hex pair. Either color failing to parse as `#rgb`/`#rrggbb`
        /// leaves the current theme untouched.
        #[qinvokable]
        fn apply_custom(self: Pin<&mut ThemeController>, accent: &QString, bg_base: &QString);

        /// The built-in preset names, as a JSON array of strings.
        #[qinvokable]
        fn preset_names(self: &ThemeController) -> QString;
    }
}

pub struct ThemeControllerRust {
    preset_name: QString,
    custom_accent: QString,
    custom_background: QString,
    bg_base: QString,
    bg_surface: QString,
    bg_surface_hover: QString,
    bg_elevated: QString,
    bg_sidebar: QString,
    bg_overlay: QString,
    bg_inset: QString,
    bg_inset_hover: QString,
    bg_button: QString,
    bg_button_hover: QString,
    accent: QString,
    accent_hover: QString,
    /// Mirrors `DerivedTheme::on_accent`; see the qproperty comment above for
    /// why this isn't named `on_accent` here.
    accent_foreground: QString,
    text_primary: QString,
    text_secondary: QString,
    text_muted: QString,
    text_faint: QString,
    text_disabled: QString,
    border_subtle: QString,
    border_strong: QString,
    hl_faint: QString,
    hl_med: QString,
    hl_strong: QString,
    slider_track: QString,
    slider_fill: QString,
    slider_border: QString,
    success: QString,
    error: QString,
    warning: QString,
}

impl Default for ThemeControllerRust {
    fn default() -> Self {
        let (accent, bg_base) =
            theme::find_preset(DEFAULT_PRESET).expect("Violet Night is a built-in preset");
        let dt = theme::derive_theme(accent, bg_base);
        fields_from_derived(DEFAULT_PRESET, &dt)
    }
}

/// Convert a TS-style color value (plain `#rrggbb`/`#rgb` hex, or an
fn to_qml_color(value: &str) -> String {
    if let Some(hex) = value.strip_prefix('#') {
        return format!("#{}", hex.to_uppercase());
    }
    if let Some(inner) = value
        .strip_prefix("rgba(")
        .and_then(|s| s.strip_suffix(')'))
    {
        let parts: Vec<&str> = inner.split(',').map(|p| p.trim()).collect();
        if let [r, g, b, a] = parts[..] {
            let byte = |p: &str| -> u8 { p.parse::<f64>().unwrap_or(0.0).round().clamp(0.0, 255.0) as u8 };
            let alpha = |p: &str| -> u8 {
                (p.parse::<f64>().unwrap_or(1.0) * 255.0)
                    .round()
                    .clamp(0.0, 255.0) as u8
            };
            return format!(
                "#{:02X}{:02X}{:02X}{:02X}",
                alpha(a),
                byte(r),
                byte(g),
                byte(b)
            );
        }
    }
    // Should not be reached for well-formed DerivedTheme values.
    value.to_uppercase()
}

/// Build the raw property struct from a derived palette.
fn fields_from_derived(preset_name: &str, dt: &DerivedTheme) -> ThemeControllerRust {
    ThemeControllerRust {
        preset_name: QString::from(preset_name),
        // Seeded from the preset so the custom fields open on the current
        // colours rather than empty.
        custom_accent: QString::from(&dt.accent.to_uppercase()),
        custom_background: QString::from(&dt.bg_base.to_uppercase()),
        bg_base: QString::from(&to_qml_color(&dt.bg_base)),
        bg_surface: QString::from(&to_qml_color(&dt.bg_surface)),
        bg_surface_hover: QString::from(&to_qml_color(&dt.bg_surface_hover)),
        bg_elevated: QString::from(&to_qml_color(&dt.bg_elevated)),
        bg_sidebar: QString::from(&to_qml_color(&dt.bg_sidebar)),
        bg_overlay: QString::from(&to_qml_color(&dt.bg_overlay)),
        bg_inset: QString::from(&to_qml_color(&dt.bg_inset)),
        bg_inset_hover: QString::from(&to_qml_color(&dt.bg_inset_hover)),
        bg_button: QString::from(&to_qml_color(&dt.bg_button)),
        bg_button_hover: QString::from(&to_qml_color(&dt.bg_button_hover)),
        accent: QString::from(&to_qml_color(&dt.accent)),
        accent_hover: QString::from(&to_qml_color(&dt.accent_hover)),
        accent_foreground: QString::from(&to_qml_color(&dt.on_accent)),
        text_primary: QString::from(&to_qml_color(&dt.text_primary)),
        text_secondary: QString::from(&to_qml_color(&dt.text_secondary)),
        text_muted: QString::from(&to_qml_color(&dt.text_muted)),
        text_faint: QString::from(&to_qml_color(&dt.text_faint)),
        text_disabled: QString::from(&to_qml_color(&dt.text_disabled)),
        border_subtle: QString::from(&to_qml_color(&dt.border_subtle)),
        border_strong: QString::from(&to_qml_color(&dt.border_strong)),
        hl_faint: QString::from(&to_qml_color(&dt.hl_faint)),
        hl_med: QString::from(&to_qml_color(&dt.hl_med)),
        hl_strong: QString::from(&to_qml_color(&dt.hl_strong)),
        slider_track: QString::from(&to_qml_color(&dt.slider_track)),
        slider_fill: QString::from(&to_qml_color(&dt.slider_fill)),
        slider_border: QString::from(&to_qml_color(&dt.slider_border)),
        success: QString::from(&to_qml_color(&dt.success)),
        error: QString::from(&to_qml_color(&dt.error)),
        warning: QString::from(&to_qml_color(&dt.warning)),
    }
}

/// Push every field of a derived palette onto the live QObject's properties,
/// so Qt emits the right `NOTIFY` signals for QML bindings to pick up.
fn apply_derived(mut ctrl: Pin<&mut qobject::ThemeController>, preset_name: &str, dt: &DerivedTheme) {
    let f = fields_from_derived(preset_name, dt);
    ctrl.as_mut().set_preset_name(f.preset_name);
    // Keep the custom fields showing the colours actually in use, so switching
    // to a preset and then tweaking it starts from that preset.
    ctrl.as_mut().set_custom_accent(f.custom_accent);
    ctrl.as_mut().set_custom_background(f.custom_background);
    ctrl.as_mut().set_bg_base(f.bg_base);
    ctrl.as_mut().set_bg_surface(f.bg_surface);
    ctrl.as_mut().set_bg_surface_hover(f.bg_surface_hover);
    ctrl.as_mut().set_bg_elevated(f.bg_elevated);
    ctrl.as_mut().set_bg_sidebar(f.bg_sidebar);
    ctrl.as_mut().set_bg_overlay(f.bg_overlay);
    ctrl.as_mut().set_bg_inset(f.bg_inset);
    ctrl.as_mut().set_bg_inset_hover(f.bg_inset_hover);
    ctrl.as_mut().set_bg_button(f.bg_button);
    ctrl.as_mut().set_bg_button_hover(f.bg_button_hover);
    ctrl.as_mut().set_accent(f.accent);
    ctrl.as_mut().set_accent_hover(f.accent_hover);
    ctrl.as_mut().set_accent_foreground(f.accent_foreground);
    ctrl.as_mut().set_text_primary(f.text_primary);
    ctrl.as_mut().set_text_secondary(f.text_secondary);
    ctrl.as_mut().set_text_muted(f.text_muted);
    ctrl.as_mut().set_text_faint(f.text_faint);
    ctrl.as_mut().set_text_disabled(f.text_disabled);
    ctrl.as_mut().set_border_subtle(f.border_subtle);
    ctrl.as_mut().set_border_strong(f.border_strong);
    ctrl.as_mut().set_hl_faint(f.hl_faint);
    ctrl.as_mut().set_hl_med(f.hl_med);
    ctrl.as_mut().set_hl_strong(f.hl_strong);
    ctrl.as_mut().set_slider_track(f.slider_track);
    ctrl.as_mut().set_slider_fill(f.slider_fill);
    ctrl.as_mut().set_slider_border(f.slider_border);
    ctrl.as_mut().set_success(f.success);
    ctrl.as_mut().set_error(f.error);
    ctrl.as_mut().set_warning(f.warning);
}

impl qobject::ThemeController {
    pub fn apply_preset(mut self: Pin<&mut Self>, name: &QString) {
        let name = name.to_string();
        match theme::find_preset(&name) {
            Some((accent, bg_base)) => {
                let dt = theme::derive_theme(accent, bg_base);
                apply_derived(self.as_mut(), &name, &dt);
                self.persist();
            }
            None => log::warn!("theme: unknown preset {name:?}, leaving theme unchanged"),
        }
    }

    /// Load the saved theme, falling back to the default preset.
    pub fn restore(mut self: Pin<&mut Self>) {
        let saved = match klang_core::theme_config::theme_file_get() {
            Ok(Some(file)) => file,
            Ok(None) => return,
            Err(e) => {
                log::warn!("theme: {e}, using the default");
                return;
            }
        };
        self.as_mut()
            .set_custom_accent(QString::from(&saved.custom.accent));
        self.as_mut()
            .set_custom_background(QString::from(&saved.custom.background));
        if saved.preset == CUSTOM_PRESET_NAME {
            let accent = QString::from(&saved.custom.accent);
            let background = QString::from(&saved.custom.background);
            self.apply_custom(&accent, &background);
        } else {
            let name = QString::from(&saved.preset);
            self.apply_preset(&name);
        }
    }

    fn persist(self: Pin<&mut Self>) {
        let file = klang_core::theme_config::ThemeFile {
            version: Some(klang_core::theme_config::THEME_FILE_VERSION),
            preset: self.preset_name().to_string(),
            custom: klang_core::theme_config::ThemeCustom {
                accent: self.custom_accent().to_string(),
                background: self.custom_background().to_string(),
            },
        };
        if let Err(e) = klang_core::theme_config::theme_file_set(file) {
            log::warn!("theme: could not save: {e}");
        }
    }

    pub fn apply_custom(mut self: Pin<&mut Self>, accent: &QString, bg_base: &QString) {
        let accent = match theme::normalize_hex(&accent.to_string()) {
            Some(a) => a,
            None => {
                log::warn!("theme: invalid custom accent color, leaving theme unchanged");
                return;
            }
        };
        let bg_base = match theme::normalize_hex(&bg_base.to_string()) {
            Some(b) => b,
            None => {
                log::warn!("theme: invalid custom background color, leaving theme unchanged");
                return;
            }
        };
        let dt = theme::derive_theme(&accent, &bg_base);
        apply_derived(self.as_mut(), CUSTOM_PRESET_NAME, &dt);
        self.as_mut().set_custom_accent(QString::from(&accent));
        self.as_mut().set_custom_background(QString::from(&bg_base));
        self.persist();
    }

    /// Every preset with the colours a swatch needs, plus whether its
    /// background is light — the swatch paints that background, so its label
    /// cannot take its colour from the active theme.
    pub fn preset_names(self: &Self) -> QString {
        let rows: Vec<serde_json::Value> = theme::PRESET_THEMES
            .iter()
            .map(|(name, accent, background)| {
                let derived = theme::derive_theme(accent, background);
                serde_json::json!({
                    "name": name,
                    "accent": accent,
                    "background": background,
                    "light": derived.text_primary.to_lowercase() != "#ffffff",
                })
            })
            .collect();
        let json = serde_json::to_string(&rows).unwrap_or_else(|_| "[]".to_string());
        QString::from(&json)
    }
}
