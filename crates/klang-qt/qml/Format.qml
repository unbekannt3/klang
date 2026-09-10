// Formatting helpers shared by every page.
pragma Singleton

import QtQuick
import me.unbk.klang

QtObject {
    /// TIDAL's top tier, the one that earns the gold.
    function isHiRes(quality) {
        return quality === "HI_RES_LOSSLESS" || quality === "HI_RES"
    }

    /// TIDAL's own badge text for a quality tier. Hi-Res is "MAX" on
    /// tidal.com; plain lossless is labelled by its codec.
    function qualityLabel(quality) {
        switch (quality) {
        case "HI_RES_LOSSLESS": return "MAX"
        case "HI_RES":          return "MAX"
        case "LOSSLESS":        return "FLAC"
        case "HIGH":            return "HIGH"
        case "MEDIUM":          return "MEDIUM"
        case "LOW":             return "LOW"
        default:                return quality || ""
        }
    }

    /// The same tiers written out for a menu rather than shouted on a badge.
    /// Video streams only ever come as HIGH/MEDIUM/LOW.
    function qualityName(quality) {
        switch (quality) {
        case "HIGH":   return "High"
        case "MEDIUM": return "Medium"
        case "LOW":    return "Low"
        default:       return qualityLabel(quality)
        }
    }

    /// Hi-Res gets TIDAL's gold; everything else stays neutral so the gold
    /// keeps meaning "this is the best tier".
    function qualityColor(quality) {
        return isHiRes(quality) ? Theme.hiRes : Theme.textSecondary
    }

    /// Seconds to m:ss, or h:mm:ss past an hour.
    /// TIDAL writes an artist bio with its own link markup and literal
    /// <br/> tags: [wimpLink artistId="123"]Name[/wimpLink].

    /// The bio as prose — link labels kept, markup dropped.
    function bioPlain(text) {
        if (!text)
            return ""
        return text
            .replace(/\[wimpLink[^\]]*\]([\s\S]*?)\[\/wimpLink\]/g, "$1")
            .replace(/\[\/?[a-zA-Z][^\]]*\]/g, "")
            .replace(/<br\s*\/?>/gi, "\n")
    }

    /// The bio as rich text, with those links routable by the caller.
    function bioRich(text) {
        if (!text)
            return ""
        return text
            .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
            .replace(/&lt;br\s*\/?&gt;/gi, "<br>")
            .replace(/\[wimpLink artistId="(\d+)"\]([\s\S]*?)\[\/wimpLink\]/g,
                     '<a href="artist:$1">$2</a>')
            .replace(/\[wimpLink albumId="(\d+)"\]([\s\S]*?)\[\/wimpLink\]/g,
                     '<a href="album:$1">$2</a>')
            .replace(/\[\/?[a-zA-Z][^\]]*\]/g, "")
            .replace(/\n/g, "<br>")
    }

    /// tidal.com labels a video in whole minutes, not mm:ss.
    function minutes(secs) {
        if (!secs || secs < 0)
            return ""
        return Math.max(1, Math.round(secs / 60)) + " " + Tr.t("MIN.")
    }

    /// When a track joined the collection. Recent days read as words, the
    /// rest as the locale's short date — the column is 96px wide.
    function added(iso) {
        if (!iso)
            return ""
        const when = new Date(iso)
        if (isNaN(when.getTime()))
            return ""
        const midnight = new Date()
        midnight.setHours(0, 0, 0, 0)
        const days = Math.floor((midnight.getTime() - when.getTime()) / 86400000)
        if (days < 0)
            return Tr.t("Today")
        if (days < 1)
            return Tr.t("Yesterday")
        return when.toLocaleDateString(Qt.locale(), Locale.ShortFormat)
    }

    /// Unknown reads as unknown — "0:00" beside a running clock looks broken.
    function duration(secs) {
        if (!secs || secs < 0)
            return "–:––"
        const total = Math.floor(secs)
        const h = Math.floor(total / 3600)
        const m = Math.floor((total % 3600) / 60)
        const s = total % 60
        const pad = (n) => (n < 10 ? "0" + n : "" + n)
        return h > 0 ? h + ":" + pad(m) + ":" + pad(s)
                     : m + ":" + pad(s)
    }
}
