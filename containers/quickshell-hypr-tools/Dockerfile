FROM quickshell:phase1-hypr

# Quattro calls hyprctl for workspace/style state. Copy only the isolated
# Hyprland prefix built for this experiment; the compositor itself remains in
# its separate DRM container.
COPY --from=hyprland:phase2-runtime /opt/hypr-clang /opt/hypr-clang
COPY --from=hyprland:phase2-runtime /usr/lib/aarch64-linux-gnu/libc++.so.1.0 /opt/hypr-clang/lib/
COPY --from=hyprland:phase2-runtime /usr/lib/aarch64-linux-gnu/libc++abi.so.1.0 /opt/hypr-clang/lib/
COPY --from=hyprland:phase2-runtime /usr/lib/aarch64-linux-gnu/libpixman-1.so.0.46.4 /opt/hypr-clang/lib/
RUN ln -s libc++.so.1.0 /opt/hypr-clang/lib/libc++.so.1 \
 && ln -s libc++abi.so.1.0 /opt/hypr-clang/lib/libc++abi.so.1 \
 && ln -s libpixman-1.so.0.46.4 /opt/hypr-clang/lib/libpixman-1.so.0

ENV PATH=/opt/hypr-clang/bin:${PATH}
ENV LD_LIBRARY_PATH=/opt/hypr-clang/lib
