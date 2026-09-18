import QtQuick
import Quickshell
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.UPower

ShellRoot {
    // Force initialization before the observation timer fires.
    readonly property var networkDevices: Networking.devices.values
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool onBattery: UPower.onBattery
    Timer {
        interval: 6000
        running: true
        onTriggered: {
            console.log("SYSTEM_PROBE", "networkDevices", networkDevices.length,
                        "bluetoothAdapter", adapter ? adapter.name : "none",
                        "onBattery", onBattery);
            if (Networking.backend !== NetworkBackendType.NetworkManager ||
                networkDevices.length === 0 || !adapter) {
                console.error("SYSTEM_PROBE_FAILED");
                Qt.exit(1);
            } else {
                console.log("SYSTEM_PROBE_OK");
                Qt.quit();
            }
        }
    }
}
