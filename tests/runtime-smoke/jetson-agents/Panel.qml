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
  property var actionStatus: ({})
  property var mvpStatus: ({})
  property bool confirmRefresh: false
  property bool confirmMvp: false
  property string pendingRequestId: ""
  readonly property var codex: root.status.codex || ({})

  function refresh() { if (!statusProc.running) statusProc.running = true }
  function age(timestamp) {
    if (!timestamp) return "unknown"
    var elapsed = Date.now() - new Date(timestamp).getTime()
    if (!isFinite(elapsed) || elapsed < 0) return "unknown"
    var seconds = Math.floor(elapsed / 1000)
    if (seconds < 90) return seconds + "s ago"
    var minutes = Math.floor(seconds / 60)
    if (minutes < 90) return minutes + "m ago"
    return Math.floor(minutes / 60) + "h ago"
  }
  function limitSummary() {
    if (!root.codex.limits || root.codex.limits.length === 0) return "No live limit window"
    var limit = root.codex.limits[0]
    return String(limit.label || "Limit") + ": " + Math.round(Number(limit.percent || 0) * 100) + "% used"
  }
  function updateStatus(raw) {
    try {
      status = JSON.parse(raw)
      console.log("JETSON_AGENT_STATUS", status.usageRecords || 0,
                  status.codex && status.codex.todayPrompts !== undefined
                    ? status.codex.todayPrompts : "no-codex-record")
    }
    catch (error) { console.warn("Agent status parse failed:", error) }
  }
  function updateActionStatus(raw) {
    try {
      var parsed = JSON.parse(raw)
      if (parsed.action === "ready" || parsed.action === "refresh-codex-status-v1" || parsed.action === "run-mvp-acceptance-v1") actionStatus = parsed
    }
    catch (error) { console.warn("Agent action status parse failed:", error) }
  }
  function updateMvpStatus(raw) {
    try { mvpStatus = JSON.parse(raw) }
    catch (error) { console.warn("MVP agent status parse failed:", error) }
  }
  function refreshCodexUsage() {
    pendingRequestId = "codex-" + Date.now()
    if (!refreshProc.running) refreshProc.running = true
    confirmRefresh = false
  }
  function runMvpAcceptance() {
    pendingRequestId = "mvp-" + Date.now()
    if (!mvpProc.running) mvpProc.running = true
    confirmMvp = false
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
  Process {
    id: actionStatusProc
    command: ["cat", "/tmp/jetson-actions/action-status.json"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateActionStatus(text) }
  }
  Process {
    id: mvpStatusProc
    command: ["cat", "/tmp/jetson-actions/mvp-status.json"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateMvpStatus(text) }
  }
  Process {
    id: refreshProc
    command: ["sh", "-c", "printf '%s\\n' '{\"schemaVersion\":1,\"requestId\":\"" + root.pendingRequestId + "\",\"action\":\"refresh-codex-status-v1\"}' > /tmp/jetson-actions/action-request"]
  }
  Process {
    id: mvpProc
    command: ["sh", "-c", "printf '%s\\n' '{\"schemaVersion\":1,\"requestId\":\"" + root.pendingRequestId + "\",\"action\":\"run-mvp-acceptance-v1\"}' > /tmp/jetson-actions/action-request"]
  }
  Timer { interval: 5000; running: true; repeat: true; triggeredOnStart: true; onTriggered: { root.refresh(); if (!actionStatusProc.running) actionStatusProc.running = true; if (!mvpStatusProc.running) mvpStatusProc.running = true } }

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
      PanelSeparator { foreground: root.bar.foreground }
      Text { text: "CODEX"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true }
      InfoPair { label: "Codex today"; value: root.codex.todayPrompts === undefined ? "—" : String(root.codex.todayPrompts) + " prompts" }
      InfoPair { label: "Codex total"; value: root.codex.totalPrompts === undefined ? "—" : String(root.codex.totalPrompts) + " prompts" }
      InfoPair { label: "Sessions"; value: root.codex.totalSessions === undefined ? "—" : String(root.codex.totalSessions) }
      InfoPair { label: "Plan"; value: root.codex.tierLabel || "unavailable" }
      InfoPair { label: "Limit windows"; value: root.codex.limits === undefined ? "—" : String(root.codex.limits.length || 0) }
      InfoPair { label: "Primary limit"; value: root.limitSummary() }
      InfoPair { label: "Updated"; value: root.age(root.codex.updatedAt) }
      Rectangle {
        width: parent.width
        height: Style.space(34)
        color: root.confirmRefresh ? "#8a5a22" : "#3d4859"
        radius: Style.space(4)
        Text { anchors.centerIn: parent; text: root.confirmRefresh ? "Confirm: refresh Codex usage" : "Refresh Codex usage…"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true }
        MouseArea { anchors.fill: parent; onClicked: { if (root.confirmRefresh) root.refreshCodexUsage(); else root.confirmRefresh = true } }
      }
      Text { visible: root.confirmRefresh; width: parent.width; text: "This refreshes the existing read-only Codex usage snapshot. It does not launch an agent or expose credentials."; wrapMode: Text.WordWrap; color: root.bar.foreground; opacity: 0.65; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
      Rectangle {
        width: parent.width
        height: Style.space(34)
        color: root.confirmMvp ? "#8a5a22" : "#3d4859"
        radius: Style.space(4)
        Text { anchors.centerIn: parent; text: root.confirmMvp ? "Confirm: run MVP agent" : "Run MVP acceptance…"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true }
        MouseArea { anchors.fill: parent; onClicked: { if (root.confirmMvp) root.runMvpAcceptance(); else root.confirmMvp = true } }
      }
      Text { visible: root.confirmMvp; width: parent.width; text: "This approves a host-side agent for the current run. Exit Quattro normally after it shows waiting; Codex starts after the complete archive exists."; wrapMode: Text.WordWrap; color: root.bar.foreground; opacity: 0.65; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
      InfoPair { label: "MVP agent"; value: root.mvpStatus.state || "not-started" }
      Text { visible: !!root.mvpStatus.message; width: parent.width; text: root.mvpStatus.message; wrapMode: Text.WordWrap; color: root.bar.foreground; opacity: 0.75; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
      Text { visible: !!root.actionStatus.message; width: parent.width; text: root.actionStatus.message; wrapMode: Text.WordWrap; color: root.bar.foreground; opacity: 0.75; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
      Text { visible: !!root.codex.usageStatusText; width: parent.width; text: root.codex.usageStatusText; wrapMode: Text.WordWrap; color: root.bar.foreground; opacity: 0.75; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall }
      Text { width: parent.width; text: "Provider credentials and general provider launching remain deferred. MVP acceptance runs through the host adapter."; wrapMode: Text.WordWrap; color: root.bar.foreground; opacity: 0.65; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall }
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
