# Quickshell

Quattro’s shell is a single long-running Quickshell process. Its QML code contains the bar, panels, notifications, overlays, lock/polkit UI, services, plugin discovery, and IPC. Plugins are manifest-described QML repositories loaded from the user configuration directory.

The design is promising for a Workshop shell: the participant model could be represented as a bar widget or panel, while a separate service could expose model/GPU state. The plugin API also offers a natural place for future Quickshell-native integrations.

Portability risks are the Qt/Quickshell version, QML modules, Wayland layer-shell support, font/icon paths, shell commands, compositor IPC, and assumptions about D-Bus services. Quickshell compilation and a trivial test surface should precede any attempt to run the full shell.

The shell’s unsandboxed plugin model is also a security consideration: future Workshop plugins must be treated as trusted code.
