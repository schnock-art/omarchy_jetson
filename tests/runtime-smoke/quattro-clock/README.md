# Quattro clock logic experiment

`Model.js` is copied unchanged from `omacom/omarchy` commit `2fbac0c8e88eca704af1650ce721a494bd11a3d0`, path `shell/plugins/panels/clock/Model.js`. Its MIT license is included. The local upstream checkout was clean at extraction.

`ClockFace.qml` is a Jetson test adapter, not upstream's complete `BarWidget.qml`. It reuses upstream format selection, seconds detection, and ISO-week formatting with Quickshell's SystemClock. Right-click cycles formats in memory only. Calendar, theme services, IPC, shell.json persistence, timezone picker, and plugin registry integration remain future work.
