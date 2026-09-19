# Jetson Quattro lab instructions

## Before physical display tests

Always run the repository syntax gate before any command that can stop GDM,
hand the VT to Hyprland, or start the physical Quattro session:

```sh
cd /home/looco/repos/omarchy_jetson
./scripts/check-syntax.sh
```

`start-quattro-lab.sh` and `run-hyprland-drm.sh` run this gate themselves before
their physical-test work. If it fails, do not continue to the display handoff;
fix the reported script or manifest first.

## Safety boundaries

- Keep GDM as the normal desktop and do not create an autostart session.
- Use the physical local VT for display handoff; use SSH for observation and
  recovery.
- Preserve archived run evidence under `artifacts/quattro-runs/`.
- Treat `/home/looco/omarchy` as read-only source material.
- Do not install generic NVIDIA drivers, alter firmware/kernel/JetPack, or
  introduce Arch package management.
