# Audio integration checkpoint

Build the client image with:

```sh
sudo docker build -t quickshell:phase1-hypr-audio containers/quickshell-audio
```

`--quattro` now checks both the session bus and the Quickshell PipeWire module
before stopping GDM. The audio probe reads the default sink using an offscreen
Qt platform, exits nonzero if it is unavailable, and times out after 15 seconds.
It does not play or record audio or change volume. Only the PipeWire socket is
mounted, at `/tmp/host-pipewire`; `PIPEWIRE_REMOTE` selects it independently of
the isolated Wayland runtime. Socket access permits audio control and capture;
the read-only mount does not restrict protocol operations.

Validated on 2026-09-18: the container's Quickshell module reported
`alsa_output.platform-sound.analog-stereo`, volume `0.399993896484375`, unmuted.
Host `wpctl status` independently reported analog stereo at 40%, with HDMI
also available. The image adds PipeWire configuration, modules and tools using
container packages; no host packages or services were changed.

## Physical-session check

After preserving/removing the previous stopped test containers, start from the
physical TTY:

```sh
./scripts/run-hyprland-drm.sh --stop-gdm --quattro
```

Open the audio panel. Check that it shows the output, adjust volume slightly,
then toggle mute and restore both settings. Over SSH, observe the host state:

```sh
XDG_RUNTIME_DIR=/run/user/2002 wpctl get-volume @DEFAULT_AUDIO_SINK@
```

Use Super+Shift+E to exit. Report whether the panel showed the device and
whether its controls changed the host state. Audible playback is a separate
check requiring connected speakers/headphones and a chosen test sound.

The upstream `omarchy-audio-output-sink` helper is not yet installed; Quattro
falls back to its native default sink, which is appropriate for this directly
connected ALSA output. DSP/virtual-sink resolution is not validated. Network,
Bluetooth, power and authentication integration remain separate work. The
system bus is not exposed in this batch.
