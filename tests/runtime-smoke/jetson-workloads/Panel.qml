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
  property var actionStatus: ({})
  property bool confirmSample: false

  function refresh() { if (!registryProc.running) registryProc.running = true }
  function updateRegistry(raw) {
    try { jobs = JSON.parse(raw).jobs || [] }
    catch (error) { console.warn("Workload registry parse failed:", error) }
  }
  function submitHarmlessSample() {
    if (!requestProc.running) requestProc.running = true
    confirmSample = false
  }
  function updateActionStatus(raw) {
    try { actionStatus = JSON.parse(raw) }
    catch (error) { console.warn("Workload action status parse failed:", error) }
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
  Process {
    id: actionStatusProc
    command: ["cat", "/tmp/jetson-actions/action-status.json"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateActionStatus(text) }
  }
  Process {
    id: requestProc
    command: ["sh", "-c", "printf '%s\\n' submit-harmless-sample-v1 > /tmp/jetson-actions/action-request"]
  }
  onOpenedChanged: if (opened) refresh()
  Timer { interval: 3000; running: root.opened; repeat: true; onTriggered: { root.refresh(); if (!actionStatusProc.running) actionStatusProc.running = true } }

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
      Text { text: "Registered jobs; only the fixed harmless sample can be submitted"; color: root.bar.foreground; opacity: 0.65; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; wrapMode: Text.WordWrap; width: parent.width }
      PanelSeparator { foreground: root.bar.foreground }
      Rectangle {
        width: parent.width
        height: Style.space(34)
        color: root.confirmSample ? "#8a5a22" : "#3d4859"
        radius: Style.space(4)
        Text {
          anchors.centerIn: parent
          text: root.confirmSample ? "Confirm: start harmless 15-second sample" : "Start harmless sample…"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }
        MouseArea {
          anchors.fill: parent
          onClicked: {
            if (root.confirmSample) root.submitHarmlessSample()
            else root.confirmSample = true
          }
        }
      }
      Text { visible: root.confirmSample; text: "This starts only the predeclared local 15-second sample. No agent, network request, or arbitrary command is launched."; color: root.bar.foreground; opacity: 0.65; wrapMode: Text.WordWrap; width: parent.width; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
      Text { visible: !!root.actionStatus.message; text: root.actionStatus.message; color: root.bar.foreground; opacity: 0.75; wrapMode: Text.WordWrap; width: parent.width; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
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
