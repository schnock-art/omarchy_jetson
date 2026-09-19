import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "omarchy.agents"
  ipcTarget: "omarchy.agents"
  manageIpc: false
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  property var status: ({})
  readonly property var codex: root.status.codex || ({})

  function refresh() { if (!statusProc.running) statusProc.running = true }
  function updateStatus(raw) {
    try {
      status = JSON.parse(raw)
      console.log("JETSON_AGENT_STATUS", status.usageRecords || 0,
                  status.codex && status.codex.todayPrompts !== undefined
                    ? status.codex.todayPrompts : "no-codex-record")
    }
    catch (error) { console.warn("Agent status parse failed:", error) }
  }

  IpcHandler {
    target: "omarchy.agents"
    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
  }

  onOpenedChanged: if (opened) refresh()
  Process {
    id: statusProc
    command: ["cat", "/tmp/jetson-agent-status/status.json"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateStatus(text) }
  }
  Timer { interval: 5000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰚩"
    tooltipText: "Agent integration"
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
      Text { text: "AGENT INTEGRATION"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.title; font.bold: true }
      PanelSeparator { foreground: root.bar.foreground }
      InfoPair { label: "Bridge"; value: root.status.bridge || "starting…" }
      InfoPair { label: "Usage records"; value: root.status.usageRecords === undefined ? "—" : String(root.status.usageRecords) }
      InfoPair { label: "Collectors"; value: root.status.collectors === undefined ? "—" : String(root.status.collectors) }
      InfoPair { label: "Updater"; value: root.status.updaterPresent === 1 ? "available" : "not exposed" }
      InfoPair { label: "Provider launch"; value: root.status.providerLaunch || "deferred" }
      InfoPair { label: "Codex today"; value: root.codex.todayPrompts === undefined ? "—" : String(root.codex.todayPrompts) + " prompts" }
      InfoPair { label: "Codex total"; value: root.codex.totalPrompts === undefined ? "—" : String(root.codex.totalPrompts) + " prompts" }
      InfoPair { label: "Limit windows"; value: root.codex.limits === undefined ? "—" : String(root.codex.limits.length || 0) }
      Text { width: parent.width; text: "Read-only bridge. Provider credentials and launching remain deferred."; wrapMode: Text.WordWrap; color: root.bar.foreground; opacity: 0.65; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""
    width: parent.width
    spacing: Style.space(8)
    Text { text: parent.label; color: root.bar.foreground; opacity: 0.6; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    Text { text: parent.value; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall }
  }
}
