//! Playback queue: order, position, shuffle and repeat.
//!
//! Kept out of QML because it is state, not view — the same queue drives MPRIS
//! and the gapless prefetch, neither of which involves the UI.

use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, PartialEq, Eq, Debug, Default, Serialize, Deserialize)]
pub enum Repeat {
    #[default]
    Off,
    All,
    One,
}

impl Repeat {
    pub fn next(self) -> Self {
        match self {
            Repeat::Off => Repeat::All,
            Repeat::All => Repeat::One,
            Repeat::One => Repeat::Off,
        }
    }

    pub fn as_i32(self) -> i32 {
        match self {
            Repeat::Off => 0,
            Repeat::All => 1,
            Repeat::One => 2,
        }
    }

}

/// One entry. `cover` is a TIDAL image UUID, passed through to the UI.
#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
pub struct Entry {
    pub id: i64,
    pub title: String,
    pub artist: String,
    pub duration: f32,
    #[serde(default)]
    pub album: String,
    #[serde(default)]
    pub cover: String,
    /// So the player bar and the queue can link to the artist and the album.
    #[serde(default)]
    pub artist_id: i64,
    #[serde(default)]
    pub album_id: i64,
    /// Radio mix for this track, when TIDAL supplies one. Autoplay reads it
    /// off the last track to keep going past the end of the queue.
    #[serde(default)]
    pub track_mix: String,
}

/// The queue is two lists: tracks queued by hand play before the context
/// (an album, a playlist) the user started from, and are consumed as they play.
/// Derives serde so the whole struct can be persisted verbatim (see
/// `player.rs`'s `QueueSnapshot`) — every field is already serde-friendly.
#[derive(Default, Clone, Serialize, Deserialize)]
pub struct Queue {
    manual: Vec<Entry>,
    context: Vec<Entry>,
    /// Index into `context` of the playing track, once past the manual ones.
    position: usize,
    current: Option<Entry>,
    /// Playback order over `context` when shuffling; empty when not.
    shuffle_order: Vec<usize>,
    repeat: Repeat,
    /// Where the context came from, e.g. "playlist:uuid". Gapless is skipped
    /// across a source change.
    source: String,
    /// What has already played, most recent last.
    history: Vec<Entry>,
}

/// Keep the history bounded; the UI only ever shows a screenful.
const HISTORY_LIMIT: usize = 100;

impl Queue {
    pub fn current(&self) -> Option<&Entry> {
        self.current.as_ref()
    }

    pub fn repeat(&self) -> Repeat {
        self.repeat
    }

    pub fn is_shuffled(&self) -> bool {
        !self.shuffle_order.is_empty()
    }

    pub fn source(&self) -> &str {
        &self.source
    }

    pub fn manual(&self) -> &[Entry] {
        &self.manual
    }

    /// Played tracks, oldest first.
    pub fn history(&self) -> &[Entry] {
        &self.history
    }

    /// Record what is playing before moving off it.
    fn push_history(&mut self) {
        if let Some(current) = self.current.clone() {
            if self.history.last() != Some(&current) {
                self.history.push(current);
                if self.history.len() > HISTORY_LIMIT {
                    self.history.remove(0);
                }
            }
        }
    }

    /// Upcoming context entries in playback order, manual ones excluded.
    ///
    /// `position` indexes the context, not the playback order, so under
    /// shuffle it has to be resolved to its slot first — the same way `jump`
    /// and `gapless_next` do. Skipping by the raw index cut entries off the
    /// front of the list and left every row pointing at the wrong track.
    pub fn upcoming(&self) -> Vec<&Entry> {
        let order = self.order();
        let next = match order.iter().position(|&i| i == self.position) {
            Some(slot) => slot + 1,
            None => 0,
        };
        order
            .into_iter()
            .skip(next)
            .filter_map(|i| self.context.get(i))
            .collect()
    }

    /// Context indices in playback order.
    fn order(&self) -> Vec<usize> {
        if self.shuffle_order.is_empty() {
            (0..self.context.len()).collect()
        } else {
            self.shuffle_order.clone()
        }
    }

    /// Replace the context and start at `index`.
    pub fn set_context(&mut self, entries: Vec<Entry>, index: usize, source: String) {
        self.context = entries;
        self.source = source;
        self.position = index.min(self.context.len().saturating_sub(1));
        if self.is_shuffled() {
            self.reshuffle_from(self.position);
        }
        self.current = self.entry_at_position();
    }

    /// Append tracks the source has since loaded, keeping what is playing.
    ///
    /// A paginated collection only has its first page in hand when playback
    /// starts, so the rest arrives here. Entries already in the context are
    /// skipped, which makes this safe to call on every page.
    pub fn extend_context(&mut self, entries: Vec<Entry>) -> usize {
        let known: std::collections::HashSet<i64> =
            self.context.iter().map(|e| e.id).collect();
        let fresh: Vec<Entry> = entries
            .into_iter()
            .filter(|e| !known.contains(&e.id))
            .collect();
        if fresh.is_empty() {
            return 0;
        }
        let added = fresh.len();
        let first_new = self.context.len();
        self.context.extend(fresh);
        if self.is_shuffled() {
            // Shuffled into what is left rather than appended in order, but
            // never ahead of the track playing now.
            use rand::seq::SliceRandom;
            let played = self
                .shuffle_order
                .iter()
                .position(|&i| i == self.position)
                .map(|slot| slot + 1)
                .unwrap_or(0);
            let mut rest: Vec<usize> = self.shuffle_order[played..].to_vec();
            rest.extend(first_new..self.context.len());
            rest.shuffle(&mut rand::rng());
            self.shuffle_order.truncate(played);
            self.shuffle_order.extend(rest);
        }
        added
    }

    /// Play next, ahead of the context.
    pub fn play_next(&mut self, entry: Entry) {
        self.manual.insert(0, entry);
    }

    pub fn enqueue(&mut self, entry: Entry) {
        self.manual.push(entry);
    }

    pub fn remove_manual(&mut self, index: usize) {
        if index < self.manual.len() {
            self.manual.remove(index);
        }
    }

    pub fn clear_manual(&mut self) {
        self.manual.clear();
    }

    /// Advance. `natural` marks a track that ended on its own, where repeat-one
    /// replays it; pressing next always moves on.
    pub fn advance(&mut self, natural: bool) -> Option<Entry> {
        if natural && self.repeat == Repeat::One {
            return self.current.clone();
        }
        self.push_history();
        if !self.manual.is_empty() {
            self.current = Some(self.manual.remove(0));
            return self.current.clone();
        }

        let order = self.order();
        let slot = order.iter().position(|&i| i == self.position);
        match slot {
            Some(s) if s + 1 < order.len() => {
                self.position = order[s + 1];
            }
            _ if self.repeat == Repeat::All && !order.is_empty() => {
                self.position = order[0];
            }
            _ => {
                self.current = None;
                return None;
            }
        }
        self.current = self.entry_at_position();
        self.current.clone()
    }

    /// Step back through the context. Manual entries are not restored — they
    /// were consumed.
    pub fn previous(&mut self) -> Option<Entry> {
        // Stepping back consumes the history entry it returns to, and moves the
        // context position with it so a later advance carries on from there.
        if let Some(previous) = self.history.pop() {
            if let Some(index) = self.context.iter().position(|e| e.id == previous.id) {
                self.position = index;
            }
            self.current = Some(previous);
            return self.current.clone();
        }
        let order = self.order();
        let slot = order.iter().position(|&i| i == self.position)?;
        if slot == 0 {
            if self.repeat != Repeat::All || order.is_empty() {
                return self.current.clone();
            }
            self.position = *order.last()?;
        } else {
            self.position = order[slot - 1];
        }
        self.current = self.entry_at_position();
        self.current.clone()
    }

    /// Jump to an upcoming entry, counted from the next one. `manual` selects
    /// which list the index is in; the context list is walked in playback
    /// order, so this is shuffle-correct. To start at a known position in the
    /// context, use [`Queue::set_context`] instead.
    pub fn jump(&mut self, index: usize, manual: bool) -> Option<Entry> {
        if manual {
            // History is only recorded once the jump is going to happen —
            // otherwise a rejected index leaves the playing track in it, and
            // "previous" then goes back to the song already playing.
            if index >= self.manual.len() {
                return None;
            }
            self.push_history();
            // Everything skipped over is dropped, as TIDAL does.
            self.manual.drain(..index);
            self.current = Some(self.manual.remove(0));
            return self.current.clone();
        }
        // `index` counts within `upcoming()`, which is in playback order, so it
        // must be resolved through that order rather than used as a raw index.
        let order = self.order();
        let slot = order.iter().position(|&i| i == self.position)?;
        let target = *order.get(slot + 1 + index)?;
        self.push_history();
        self.position = target;
        self.current = self.entry_at_position();
        self.current.clone()
    }

    pub fn set_repeat(&mut self, repeat: Repeat) {
        self.repeat = repeat;
    }

    pub fn toggle_repeat(&mut self) -> Repeat {
        self.repeat = self.repeat.next();
        self.repeat
    }

    /// Turning shuffle on keeps the current track first, then randomises the
    /// rest; turning it off restores catalogue order at the same track.
    pub fn set_shuffle(&mut self, on: bool) {
        if on == self.is_shuffled() {
            return;
        }
        if on {
            self.reshuffle_from(self.position);
        } else {
            self.shuffle_order.clear();
        }
    }

    fn reshuffle_from(&mut self, first: usize) {
        use rand::seq::SliceRandom;
        let mut rest: Vec<usize> = (0..self.context.len()).filter(|&i| i != first).collect();
        rest.shuffle(&mut rand::rng());
        self.shuffle_order = std::iter::once(first).chain(rest).collect();
    }

    fn entry_at_position(&self) -> Option<Entry> {
        self.context.get(self.position).cloned()
    }

    /// What to arm for a gapless transition, or None when the boundary must go
    /// through track-finished instead: repeat-one replays, and the manual list
    /// is only known to be next while it is non-empty.
    pub fn gapless_next(&self) -> Option<&Entry> {
        if self.repeat == Repeat::One {
            return None;
        }
        if let Some(first) = self.manual.first() {
            return Some(first);
        }
        let order = self.order();
        let slot = order.iter().position(|&i| i == self.position)?;
        let next = if slot + 1 < order.len() {
            order[slot + 1]
        } else if self.repeat == Repeat::All && !order.is_empty() {
            order[0]
        } else {
            return None;
        };
        self.context.get(next)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entries(n: usize) -> Vec<Entry> {
        (0..n)
            .map(|i| Entry {
                id: i as i64,
                title: format!("Track {i}"),
                artist: "Artist".into(),
                duration: 180.0,
                album: "Album".into(),
                ..Default::default()
            })
            .collect()
    }

    fn queue_of(n: usize) -> Queue {
        let mut q = Queue::default();
        q.set_context(entries(n), 0, "album:1".into());
        q
    }

    #[test]
    fn extend_context_appends_only_what_is_new() {
        let mut q = Queue::default();
        q.set_context(entries(3), 0, "favorites".into());
        // The same page again plus two more, as a second fetch would hand back.
        let mut second = entries(3);
        second.extend(
            (3..5).map(|i| Entry { id: i, title: format!("Track {i}"), ..Default::default() }),
        );
        assert_eq!(q.extend_context(second), 2);
        assert_eq!(q.upcoming().len(), 4);
        assert_eq!(q.upcoming().last().unwrap().id, 4);
    }

    #[test]
    fn extend_context_keeps_the_playing_track() {
        let mut q = Queue::default();
        q.set_context(entries(3), 1, "favorites".into());
        let playing = q.current().map(|e| e.id);
        q.extend_context((3..8).map(|i| Entry { id: i, ..Default::default() }).collect());
        assert_eq!(q.current().map(|e| e.id), playing);
        // Shuffled, the new tracks land after the one playing, never before.
        q.set_shuffle(true);
        q.extend_context((8..12).map(|i| Entry { id: i, ..Default::default() }).collect());
        assert_eq!(q.current().map(|e| e.id), playing);
        // Three plus five plus four, less the one playing.
        assert_eq!(q.upcoming().len(), 11);
    }

    #[test]
    fn advances_through_the_context() {
        let mut q = queue_of(3);
        assert_eq!(q.current().unwrap().id, 0);
        assert_eq!(q.advance(true).unwrap().id, 1);
        assert_eq!(q.advance(true).unwrap().id, 2);
        assert!(q.advance(true).is_none());
    }

    #[test]
    fn manual_entries_play_before_the_context() {
        let mut q = queue_of(3);
        q.enqueue(Entry { id: 99, title: "Queued".into(), artist: "A".into(), duration: 1.0, ..Default::default() });
        assert_eq!(q.advance(true).unwrap().id, 99);
        // The context resumes where it was, not one further on.
        assert_eq!(q.advance(true).unwrap().id, 1);
    }

    #[test]
    fn play_next_jumps_the_manual_queue() {
        let mut q = queue_of(2);
        q.enqueue(Entry { id: 10, title: "Later".into(), artist: "A".into(), duration: 1.0, ..Default::default() });
        q.play_next(Entry { id: 20, title: "Sooner".into(), artist: "A".into(), duration: 1.0, ..Default::default() });
        assert_eq!(q.advance(true).unwrap().id, 20);
        assert_eq!(q.advance(true).unwrap().id, 10);
    }

    #[test]
    fn repeat_one_replays_only_on_a_natural_end() {
        let mut q = queue_of(3);
        q.set_repeat(Repeat::One);
        assert_eq!(q.advance(true).unwrap().id, 0);
        assert_eq!(q.advance(false).unwrap().id, 1);
    }

    #[test]
    fn repeat_all_wraps_both_ways() {
        let mut q = queue_of(2);
        q.set_repeat(Repeat::All);
        q.advance(true);
        assert_eq!(q.advance(true).unwrap().id, 0);
        assert_eq!(q.previous().unwrap().id, 1);
    }

    #[test]
    fn previous_holds_at_the_start_without_repeat() {
        let mut q = queue_of(3);
        assert_eq!(q.previous().unwrap().id, 0);
    }

    #[test]
    fn shuffle_keeps_the_current_track_first() {
        let mut q = Queue::default();
        q.set_context(entries(20), 7, "album:1".into());
        q.set_shuffle(true);
        assert_eq!(q.current().unwrap().id, 7);
        // Every track still appears exactly once.
        let mut seen: Vec<i64> = std::iter::once(7).collect();
        while let Some(e) = q.advance(true) {
            seen.push(e.id);
        }
        seen.sort_unstable();
        assert_eq!(seen, (0..20).collect::<Vec<_>>());
    }

    #[test]
    fn unshuffling_restores_catalogue_order() {
        let mut q = Queue::default();
        q.set_context(entries(10), 4, "album:1".into());
        q.set_shuffle(true);
        q.set_shuffle(false);
        assert_eq!(q.advance(true).unwrap().id, 5);
    }

    #[test]
    fn jumping_the_manual_queue_drops_what_was_skipped() {
        let mut q = queue_of(1);
        for id in [10, 11, 12] {
            q.enqueue(Entry { id, title: "Q".into(), artist: "A".into(), duration: 1.0, ..Default::default() });
        }
        assert_eq!(q.jump(2, true).unwrap().id, 12);
        assert!(q.manual().is_empty());
    }

    #[test]
    fn gapless_skips_repeat_one_and_the_end_of_the_queue() {
        let mut q = queue_of(2);
        assert_eq!(q.gapless_next().unwrap().id, 1);
        q.set_repeat(Repeat::One);
        assert!(q.gapless_next().is_none());
        q.set_repeat(Repeat::Off);
        q.advance(true);
        assert!(q.gapless_next().is_none());
    }

    #[test]
    fn jumping_upcoming_follows_playback_order() {
        let mut q = queue_of(6);
        let expected = q.upcoming()[2].id;
        assert_eq!(q.jump(2, false).unwrap().id, expected);

        // Under shuffle the raw index and the playback order disagree, which is
        // the case that used to pick the wrong track.
        let mut q = queue_of(20);
        q.set_shuffle(true);
        let expected = q.upcoming()[3].id;
        assert_eq!(q.jump(3, false).unwrap().id, expected);
    }

    /// The regression the old `upcoming()` had: it skipped by the context
    /// index, which only equals the playback slot when the queue starts at
    /// zero or is unshuffled.
    #[test]
    fn upcoming_is_complete_when_shuffled_from_a_later_track() {
        let mut q = Queue::default();
        q.set_context(entries(20), 7, "album:1".into());
        q.set_shuffle(true);

        assert_eq!(q.upcoming().len(), 19);
        let expected = q.upcoming()[0].id;
        assert_eq!(q.jump(0, false).unwrap().id, expected);
    }

    #[test]
    fn a_rejected_jump_leaves_history_alone() {
        let mut q = queue_of(3);
        q.advance(true);
        let before = q.history().len();
        assert!(q.jump(99, false).is_none());
        assert_eq!(q.history().len(), before);
    }

    #[test]
    fn history_records_what_played() {
        let mut q = queue_of(4);
        q.advance(true);
        q.advance(true);
        let ids: Vec<i64> = q.history().iter().map(|e| e.id).collect();
        assert_eq!(ids, vec![0, 1]);
    }

    #[test]
    fn previous_walks_back_through_history() {
        let mut q = queue_of(4);
        q.advance(true);
        q.advance(true);
        assert_eq!(q.current().unwrap().id, 2);
        assert_eq!(q.previous().unwrap().id, 1);
        assert_eq!(q.previous().unwrap().id, 0);
        // History is exhausted; the context takes over and holds at the start.
        assert_eq!(q.previous().unwrap().id, 0);
    }

    #[test]
    fn repeat_one_does_not_fill_history() {
        let mut q = queue_of(3);
        q.set_repeat(Repeat::One);
        q.advance(true);
        q.advance(true);
        assert!(q.history().is_empty());
    }

    #[test]
    fn upcoming_reports_what_is_left() {
        let mut q = queue_of(4);
        q.jump(0, false);
        let ids: Vec<i64> = q.upcoming().iter().map(|e| e.id).collect();
        assert_eq!(ids, vec![2, 3]);
    }

    #[test]
    fn queue_round_trips_through_json() {
        let mut q = queue_of(4);
        q.advance(true);
        q.enqueue(Entry { id: 50, title: "Queued".into(), artist: "A".into(), duration: 1.0, ..Default::default() });
        q.set_shuffle(true);
        q.set_repeat(Repeat::All);

        let json = serde_json::to_string(&q).unwrap();
        let restored: Queue = serde_json::from_str(&json).unwrap();

        assert_eq!(restored.current(), q.current());
        assert_eq!(restored.repeat(), q.repeat());
        assert_eq!(restored.is_shuffled(), q.is_shuffled());
        assert_eq!(restored.manual(), q.manual());
        assert_eq!(restored.history(), q.history());
        assert_eq!(restored.upcoming(), q.upcoming());
    }
}
