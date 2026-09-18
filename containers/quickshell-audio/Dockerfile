FROM quickshell:phase1-hypr-services

# Client configuration, protocol modules and diagnostics only. Host PipeWire
# and WirePlumber continue to own the audio devices.
RUN apt-get update \
 && apt-get install -y --no-install-recommends pipewire-bin libpipewire-0.3-common libspa-0.2-modules \
 && apt-get clean
