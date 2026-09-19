import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "omarchy.jetson-telemetry"
  ipcTarget: "omarchy.jetson-telemetry"
  // Panel is an Item, so a child that fills it does not contribute an implicit
  // size by itself. The bar otherwise assigns this widget a zero-width slot.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  manageIpc: false
  property var telemetry: ({})

  function refresh() {
    if (!telemetryProc.running) telemetryProc.running = true
  }

  function updateTelemetry(raw) {
    try {
      var parsed = JSON.parse(raw)
      if (parsed && parsed.ramTotalMb !== undefined) telemetry = parsed
    } catch (error) {
      console.warn("Jetson telemetry parse failed:", error)
    }
  }

  function percent(value) {
    return value === undefined ? "—" : Math.round(value) + "%"
  }

  function temperature(value) {
    return value === undefined ? "—" : Number(value).toFixed(1) + "°C"
  }

  function memory() {
    if (telemetry.ramTotalMb === undefined || telemetry.ramTotalMb <= 0) return "—"
    return Math.round(telemetry.ramUsedMb / 1024) + " / " + Math.round(telemetry.ramTotalMb / 1024) + " GB"
  }

  function watts() {
    return telemetry.vinMilliwatts === undefined ? "—" : (telemetry.vinMilliwatts / 1000).toFixed(1) + " W"
  }

  IpcHandler {
    target: "omarchy.jetson-telemetry"
    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
  }

  onOpenedChanged: if (opened) refresh()

  Process {
    id: telemetryProc
    command: ["cat", "/tmp/jetson-telemetry/telemetry.json"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateTelemetry(text) }
  }

  Timer { interval: 1000; running: root.opened; repeat: true; onTriggered: root.refresh() }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰍛"
    tooltipText: "Jetson telemetry"
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(330))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Style.space(14)

      Column {
        width: parent.width
        spacing: Style.space(2)
        Text {
          text: "JETSON TELEMETRY"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }
        Text {
          text: root.telemetry.powerMode || "Waiting for tegrastats…"
          color: root.bar.foreground
          opacity: 0.65
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      PanelSeparator { foreground: root.bar.foreground }

      Row {
        width: parent.width
        spacing: Style.space(20)
        Column {
          width: (parent.width - parent.spacing) / 2
          spacing: Style.spacing.labelGap
          InfoPair { label: "CPU average"; value: root.percent(root.telemetry.cpuPercent) }
          InfoPair { label: "GPU"; value: root.percent(root.telemetry.gpuPercent) }
          InfoPair { label: "RAM"; value: root.memory() }
        }
        Column {
          width: (parent.width - parent.spacing) / 2
          spacing: Style.spacing.labelGap
          InfoPair { label: "Junction"; value: root.temperature(root.telemetry.junctionC) }
          InfoPair { label: "GPU temp"; value: root.temperature(root.telemetry.gpuC) }
          InfoPair { label: "Input power"; value: root.watts() }
        }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""
    width: parent.width
    spacing: Style.space(8)
    Text {
      text: parent.label
      color: root.bar.foreground
      opacity: 0.6
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    Text {
      text: parent.value
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
