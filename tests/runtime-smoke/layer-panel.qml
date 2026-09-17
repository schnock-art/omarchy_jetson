import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
    PanelWindow {
        id: panel
        anchors { top: true; left: true; right: true }
        implicitHeight: 56
        exclusiveZone: 56
        color: "#20242b"
        WlrLayershell.namespace: "jetson-layer-smoke"
        property int clicks: 0

        Text {
            anchors.centerIn: parent
            color: "#f5f7fa"
            font.pixelSize: 20
            text: "Jetson + Hyprland + Quickshell  |  Click this bar: " + panel.clicks
        }
        MouseArea {
            anchors.fill: parent
            onClicked: {
                panel.clicks++
                console.log("JETSON_LAYER_PANEL_CLICK", panel.clicks)
            }
        }
        Component.onCompleted: console.log("JETSON_LAYER_PANEL_LOADED")
    }
}
