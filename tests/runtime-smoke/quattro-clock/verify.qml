import QtQuick
import Quickshell
import "Model.js" as Model

ShellRoot {
    ClockFace { id: clockFace }
    Timer {
        interval: 100
        running: true
        onTriggered: {
            if (!clockFace.displayText.length) throw new Error("Empty clock label")
            const initial = clockFace.activeFormat
            clockFace.cycleFormat()
            if (clockFace.activeFormat === initial) throw new Error("Format did not cycle")
            if (Model.isoWeekLiteral(2021, 0, 1) !== "53") throw new Error("ISO week boundary failed")
            console.log("QUATTRO_CLOCK_CHECK_OK", clockFace.displayText)
            Qt.quit()
        }
    }
}
