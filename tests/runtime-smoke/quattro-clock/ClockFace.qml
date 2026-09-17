import QtQuick
import Quickshell
import "Model.js" as Model

Item {
    id: root
    property string activeFormat: "dddd HH:mm:ss"
    readonly property var formatRing: Model.clockFormatRing("dddd HH:mm:ss", "d MMMM 'W'ww yyyy", Model.clockFormats(false))
    readonly property string displayText: Qt.formatDateTime(clock.date, activeFormat.replace(/ww/g, Model.isoWeekLiteral(clock.date.getFullYear(), clock.date.getMonth(), clock.date.getDate())))
    implicitWidth: label.implicitWidth + 32
    implicitHeight: 56

    function cycleFormat() {
        activeFormat = Model.nextClockFormat(formatRing, activeFormat)
        console.log("QUATTRO_CLOCK_FORMAT", activeFormat)
    }

    SystemClock {
        id: clock
        precision: Model.clockNeedsSeconds(root.activeFormat) ? SystemClock.Seconds : SystemClock.Minutes
    }
    Text {
        id: label
        anchors.centerIn: parent
        text: root.displayText
        color: "#f5f7fa"
        font.pixelSize: 20
    }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: root.cycleFormat()
    }
    Component.onCompleted: console.log("QUATTRO_CLOCK_LOADED", displayText)
}
