// Formatting helpers shared by every page.
pragma Singleton

import QtQuick
import me.unbk.klang

QtObject {
    /// TIDAL's own badge text for an audio quality tier. Hi-Res is "MAX" on
    /// tidal.com; plain lossless is labelled by its codec.
    function qualityLabel(quality) {
        switch (quality) {
        case "HI_RES_LOSSLESS": return "MAX"
        case "HI_RES":          return "MAX"
        case "LOSSLESS":        return "FLAC"
        case "HIGH":            return "HIGH"
        case "LOW":             return "LOW"
        default:                return quality || ""
        }
    }

    /// Hi-Res gets TIDAL's gold; everything else stays neutral so the gold
    /// keeps meaning "this is the best tier".
    function qualityColor(quality) {
        return quality === "HI_RES_LOSSLESS" || quality === "HI_RES"
             ? Theme.hiRes : Theme.textSecondary
    }

    /// Seconds to m:ss, or h:mm:ss past an hour.
    function duration(secs) {
        if (!secs || secs < 0)
            return "0:00"
        const total = Math.floor(secs)
        const h = Math.floor(total / 3600)
        const m = Math.floor((total % 3600) / 60)
        const s = total % 60
        const pad = (n) => (n < 10 ? "0" + n : "" + n)
        return h > 0 ? h + ":" + pad(m) + ":" + pad(s)
                     : m + ":" + pad(s)
    }
}
