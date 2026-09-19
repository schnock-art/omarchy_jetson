import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "omarchy.jetson-workloads"
  ipcTarget: "omarchy.jetson-workloads"
  manageIpc: false
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  property var jobs: []

  function refresh() { if (!registryProc.running) registryProc.running = true }
  function updateRegistry(raw) {
    try { jobs = JSON.parse(raw).jobs || [] }
    catch (error) { console.warn("Workload registry parse failed:", error) }
  }

  IpcHandler {
    target: "omarchy.jetson-workloads"
    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
  }

  Process {
    id: registryProc
    command: ["cat", "/tmp/jetson-workloads/registry.json"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateRegistry(text) }
  }
  onOpenedChanged: if (opened) refresh()
  Timer { interval: 3000; running: root.opened; repeat: true; onTriggered: root.refresh() }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰙨"
    tooltipText: "Jetson workloads"
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)
    Column {
      id: column
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Style.space(12)
      Text { text: "LAB WORKLOADS"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.title; font.bold: true }
      Text { text: "Read-only registry of explicitly launched jobs"; color: root.bar.foreground; opacity: 0.65; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall }
      PanelSeparator { foreground: root.bar.foreground }
      Text { visible: root.jobs.length === 0; text: "No registered workloads."; color: root.bar.foreground; opacity: 0.7; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall }
      Repeater {
        model: root.jobs.slice(0, 3)
        Column {
          required property var modelData
          width: parent.width
          spacing: Style.space(2)
          Text { text: modelData.name + " · " + modelData.state; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true }
          Text { text: "Owner " + modelData.owner + " · " + modelData.startedAt; color: root.bar.foreground; opacity: 0.65; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
          Text { text: modelData.logPath || ""; color: root.bar.foreground; opacity: 0.5; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideMiddle; width: parent.width }
        }
      }
    }
  }
}
