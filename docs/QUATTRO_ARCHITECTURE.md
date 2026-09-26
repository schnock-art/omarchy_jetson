# Quattro architecture

Quattro replaces the older collection of desktop processes with one long-running `omarchy-shell` Quickshell instance. Hyprland autostart launches it; the shell hosts the bar, panels, menus, overlays, notifications, OSD, lock/polkit surfaces, and services as plugins.

The shell has a QML entry point, plugin and bar-widget registries, first-party plugins, a user plugin directory, and a persisted `~/.config/omarchy/shell.json`. Shell IPC exposes operations such as ping, summon, toggle, rescan, reload, and plugin listing. Third-party plugins are git checkouts and run unsandboxed inside the shell.

This architecture is attractive for the Workshop because participant indicators, GPU telemetry, model status, and notifications could eventually be ordinary plugins. It also means the shell is not a standalone “theme”: it depends on a compositor, Wayland surfaces, session startup, fonts/icons, utilities, and a working IPC path.

The strongest reusable boundary appears to be the shell/plugin model and IPC contract. The weakest boundary is the surrounding Omarchy command/configuration and Arch packaging layer.

## Agent capability domains

Agent authority is role-specific and explicitly granted. Isolation constrains an
agent to authority appropriate for its role; the Local Builder sandbox is not
the capability model for every present or future Quattro agent. Different
agents may occupy different trust/capability domains.

| Role | Intended authority | Boundary and status |
| --- | --- | --- |
| Repository Builder | Low-trust autonomous repository implementation in one dedicated worktree | The [Local Builder plan](LOCAL_BUILDER_PLAN.md) requires its Bubblewrap/AppArmor boundary: no network access, sudo, Docker, host filesystem authority, or generic QML command/prompt path, plus bounded execution and human diff review. This is the only role currently being designed for implementation. |
| Desktop / User Agent | Explicitly granted normal-user environmental access: user files/workspaces, desktop applications and automation, themes/configuration, user services, approved network access, and local-model services | This role may operate as the desktop user and therefore does not inherit the Repository Builder's worktree-only sandbox by default. It receives no root authority automatically. Its precise grants, consent, audit, and recovery design remain future work. |
| System Agent | Reviewed host-administration operations such as package/service/configuration, hardware/power, and selected platform maintenance | This must use a separately designed privileged capability broker or equivalent—not passwordless sudo or arbitrary root shell. A structured/versioned request is classified by policy, may require human approval, runs one narrow operation, and returns structured evidence. It is deferred. |

The presentation plane remains separate from authority for every role. Quattro
and QML may render sanitized state and request predeclared actions, but never
become a generic privileged command, arbitrary prompt, or arbitrary argument
channel. The deferred System Agent flow is conceptually:

```text
agent request -> versioned capability request -> policy/risk classification
              -> optional human approval -> narrow privileged operation
              -> structured result and evidence
```

This is an architectural reservation, not an implementation or a schema.
Risk classification must distinguish, for example, an approved service restart
from changes to GDM, the NVIDIA/JetPack stack, kernel, firmware, or boot
configuration. Those high-risk operations retain explicit human approval,
recovery, and evidence requirements.

## Session integration boundary

The accepted `lab-vt` backend separates session-neutral lifecycle policy,
fixed host-service ownership, and physical display mechanics. A future GDM
backend must reuse the first two and replace only the VT/GDM mechanism.

The S2 capability probe selects a conditional architecture: an unprivileged
GDM wrapper identifies its active logind session while a narrow root-owned
service starts the two fixed containers with the assigned seat devices. The
wrapper does not receive Docker access, and the service does not accept caller
commands, image names, paths, mounts, or device arguments.

The reversible GDM experiment passed and restored the original host policy, so
the S3 service may now be implemented and fixture-tested. Its versioned
fixed-operation contract, peer authorization, and state machine are documented
in [GDM_SESSION_SERVICE.md](GDM_SESSION_SERVICE.md). Do not install the service
or a GDM session entry until the fixed runtime adapter and S3 security gate
pass. The physical `lab-vt` backend remains the recovery path.
