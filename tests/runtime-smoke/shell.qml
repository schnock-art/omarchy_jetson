import QtQuick
import Quickshell

ShellRoot {
    Component.onCompleted: {
        console.log("WORKSHOP_WAYLAND_SMOKE_OK")
        Qt.quit()
    }
}
