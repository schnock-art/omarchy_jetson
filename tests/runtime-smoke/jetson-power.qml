import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "omarchy.power"
  ipcTarget: "omarchy.power"
  readonly property string powerMode: Quickshell.env("JETSON_POWER_MODE") || "Unavailable"
  Component.onCompleted: console.log("JETSON_POWER_PANEL_LOADED", powerMode)

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "PWR"
    slotSize: Style.bar.iconSlot * 2
    tooltipText: "Jetson power mode"
    onPressed: root.toggle()
  }
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(details.implicitHeight + Style.space(32))
    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
    }
    Column {
      id: details
      width: parent.width - Style.space(32)
      x: Style.space(16)
      y: Style.space(16)
      spacing: Style.space(12)
      Text { text: "JETSON POWER"; color: Color.foreground; font.pixelSize: 20 }
      Text {
        width: parent.width
        text: root.powerMode
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: Color.foreground
        font.pixelSize: 18
      }
      Text {
        width: parent.width
        text: "NVIDIA mode queried at session start.\nConfigured power mode, not measured draw.\nMode changes are not enabled here."
        wrapMode: Text.WordWrap
        color: Color.foreground
        font.pixelSize: 14
      }
    }
  }
}
