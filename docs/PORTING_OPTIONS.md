# Porting options

## A — Full Arch/Omarchy port

Highest fidelity, highest risk. It would require a Jetson-compatible Arch environment and careful preservation of the Tegra stack. It conflicts with the current safety objective and offers little value over reusing the user-space shell.

## B — Quattro experience on Ubuntu (preferred)

Keep Ubuntu/L4T/JetPack and adapt Quickshell, compositor/session integration, commands, and dependencies. This best matches the stated goal and keeps CUDA/TensorRT native.

## C — Workshop shell inspired by Quattro

Reuse shell/plugin ideas and selected QML/components while using a Jetson-native compositor/session and Workshop services. This is the fallback if Hyprland or Omarchy’s surrounding assumptions prove too costly.

Current recommendation: investigate B first, with C as an explicit escape hatch. Do not pursue A unless a separate recovery strategy and strong evidence justify it.
