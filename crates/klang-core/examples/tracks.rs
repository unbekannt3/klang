//! Print the first few loved tracks with the fields upstream was discarding.
//!
//!     cargo run -p klang-core --example tracks

use klang_core::{api, camelot, KlangCore};

fn main() {
    let core = KlangCore::headless();
    klang_core::runtime::block_on(async {
        if api::auth::load_saved_auth(core.state()).await.ok().flatten().is_none() {
            println!("not signed in — nothing to show");
            return;
        }
        let user_id = api::auth::get_session_user_id(core.state()).await.unwrap_or(0);
        let page = api::library::get_favorite_tracks(
            core.state(), core.handle(), user_id, 0, 8,
            "DATE".into(), "DESC".into(),
        )
        .await
        .expect("favourites");

        println!("{:<38} {:>5} {:>5}  {}", "TITLE", "BPM", "KEY", "ARTIST");
        for t in &page.items {
            let key = camelot::camelot(t.key.as_deref(), t.key_scale.as_deref())
                .unwrap_or_else(|| "–".into());
            let bpm = t.bpm.map(|b| b.to_string()).unwrap_or_else(|| "–".into());
            let artist = t.artist.as_ref().map(|a| a.name.as_str()).unwrap_or("");
            println!("{:<38.38} {:>5} {:>5}  {}", t.title, bpm, key, artist);
        }
    });
}
