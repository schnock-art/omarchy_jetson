# S3 session-service security review

## Result

The repository implementation is **ready for a temporary privileged
installation test**. This is a code and fixture conclusion, not physical
acceptance. Nothing has been installed and the supported display path remains
the local-VT launcher.

## Authority review

| Boundary | Result |
| --- | --- |
| Caller identity | Unix `SO_PEERCRED`; request UID/GID fields do not exist |
| Session authority | Fixed logind lookup; owner, active/local state, class, GDM service, Wayland type, seat, TTY, and VT must agree |
| Request surface | Five exact JSON fields; 16 KiB bound; three versioned operations |
| Execution surface | No command, arguments, image, path, mount, device, environment, prompt, or Docker option in requests |
| Privileged code | Fixed root-owned libexec helper and lifecycle modules; writable copies are rejected |
| User code | Collectors/actions run only after `setpriv` drops to the validated UID/GID |
| Containers | Two fixed images, names, labels, mounts, device rules, capabilities, and `--network none` |
| Host data | Omarchy and runtime inputs are read-only; the existing action directory is the sole writable Quickshell host channel |
| Cleanup | Exact run label required before stop, capture, or removal; archive must succeed before removal |
| GDM/boot | No GDM stop/restart, default change, automatic login, boot hook, or session entry |

## Failure behavior

- Malformed, oversized, unknown-version, extra-field, and unknown-operation
  requests fail closed.
- Repeated request IDs return the stored terminal result only after ownership
  validation; reuse for another operation is rejected.
- A startup timeout signals the owned supervisor and returns without blocking
  the service indefinitely. Its trap continues exact cleanup and archival.
- Stop is bounded. If cleanup remains in progress, a later fixed stop/collect
  request can retry without broad process or container matching.
- Partial container startup is handled by label-aware cleanup. Foreign fixed-
  name containers are neither stopped nor archived.
- Failed archival preserves owned stopped resources rather than deleting the
  only diagnostic evidence.

## Accepted narrow privileges

The compositor still requires DRM, raw input, the assigned session TTY,
`/dev/tty0`, NVIDIA runtime/devices, and `SYS_TTY_CONFIG`. These are broad
device privileges but are confined to the fixed, network-isolated compositor
container and are the reason the service must remain narrow. Quickshell does
not receive raw input, tty0, the Docker socket, credentials, or a writable host
home.

## Remaining physical uncertainties

Fixtures cannot prove DRM master acquisition on the GDM-assigned VT, visible
rendering, keyboard/pointer delivery, PipeWire behavior in the minimal session,
or return to GDM. A temporary installation test must verify those explicitly.
Until then the implementation is “ready for physical test,” not physically
verified, and S4 remains blocked.
