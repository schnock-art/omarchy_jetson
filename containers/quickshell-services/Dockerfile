FROM quickshell:phase1-hypr-tools

# Rebuild the retained ARM64 Quickshell source with the optional desktop
# service integrations needed by Quattro's tray/audio/media/lock widgets.
RUN cmake -S /tmp/quickshell -B /tmp/quickshell-services-build -GNinja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCRASH_HANDLER=OFF \
      -DUSE_JEMALLOC=OFF \
      -DHYPRLAND=ON \
      -DSCREENCOPY=OFF \
      -DSERVICE_MPRIS=ON \
      -DSERVICE_PAM=ON \
      -DSERVICE_PIPEWIRE=ON \
      -DSERVICE_POLKIT=ON \
      -DSERVICE_STATUS_NOTIFIER=ON \
 && cmake --build /tmp/quickshell-services-build -j2

ENV PATH=/opt/hypr-clang/bin:${PATH}
ENV LD_LIBRARY_PATH=/opt/hypr-clang/lib
