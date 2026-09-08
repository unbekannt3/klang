// Formatting helpers shared by every page.
pragma Singleton

import QtQuick

QtObject {
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
