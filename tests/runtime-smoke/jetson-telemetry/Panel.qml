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
  property var history: []
  readonly property int historyLimit: 60

  function refresh() {
    if (!telemetryProc.running) telemetryProc.running = true
  }

  function updateTelemetry(raw) {
    try {
      var parsed = JSON.parse(raw)
      if (parsed && parsed.ramTotalMb !== undefined) {
        telemetry = parsed
        var next = history.slice()
        next.push({ cpu: Number(parsed.cpuPercent || 0), gpu: Number(parsed.gpuPercent || 0), temperature: Number(parsed.junctionC || 0), watts: Number(parsed.vinMilliwatts || 0) / 1000 })
        if (next.length > historyLimit) next.shift()
        history = next
      }
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

  function peak(field) {
    var result = 0
    for (var i = 0; i < history.length; i++) result = Math.max(result, Number(history[i][field] || 0))
    return result
  }

  onHistoryChanged: historyCanvas.requestPaint()

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

      PanelSeparator { foreground: root.bar.foreground }

      Column {
        width: parent.width
        spacing: Style.space(6)
        Text {
          text: "LAST " + root.history.length + " SECONDS"
          color: root.bar.foreground
          opacity: 0.65
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }
        Canvas {
          id: historyCanvas
          width: parent.width
          height: Style.space(46)
          onPaint: {
            var context = getContext("2d")
            context.clearRect(0, 0, width, height)
            if (root.history.length < 2) return
            function line(field, color) {
              context.beginPath()
              for (var i = 0; i < root.history.length; i++) {
                var x = i * width / (root.historyLimit - 1)
                var y = height - Math.min(100, Number(root.history[i][field] || 0)) * height / 100
                if (i === 0) context.moveTo(x, y)
                else context.lineTo(x, y)
              }
              context.strokeStyle = color
              context.lineWidth = 2
              context.stroke()
            }
            line("cpu", root.bar.foreground)
            line("gpu", "#67c587")
          }
        }
        Row {
          width: parent.width
          spacing: Style.space(14)
          Text { text: "CPU peak " + Math.round(root.peak("cpu")) + "%"; color: root.bar.foreground; opacity: 0.7; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall }
          Text { text: "GPU peak " + Math.round(root.peak("gpu")) + "%"; color: root.bar.foreground; opacity: 0.7; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall }
          Text { text: "Junction peak " + root.peak("temperature").toFixed(1) + "°C"; color: root.bar.foreground; opacity: 0.7; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall }
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
