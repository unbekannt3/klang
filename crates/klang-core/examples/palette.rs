//! Print a derived palette, to eyeball the theme port without launching the UI.
//!
//!     cargo run -p klang-core --example palette

fn main() {
    for (name, accent, bg) in klang_core::theme::PRESET_THEMES.iter() {
        let t = klang_core::theme::derive_theme(accent, bg);
        println!(
            "{name:<16} base={} surface={} elevated={} accent={} text={} muted={} border={}",
            t.bg_base, t.bg_surface, t.bg_elevated, t.accent, t.text_primary, t.text_muted,
            t.border_subtle
        );
    }
}
