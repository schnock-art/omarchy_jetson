FROM hyprland:phase2-clang

# These IDs match the current Jetson host. The launcher passes the input/video/
# render group IDs explicitly too, so device access is based on host numeric IDs.
RUN groupadd --gid 2002 hyprland \
 && useradd --uid 2002 --gid 2002 --create-home --shell /bin/sh hyprland \
 && groupadd --force --gid 44 video \
 && groupadd --force --gid 993 render \
 && groupadd --force --gid 996 input \
 && usermod --append --groups video,render,input hyprland

COPY hyprland-seatd-entrypoint /usr/local/bin/hyprland-seatd-entrypoint
COPY hyprland-unprivileged /usr/local/bin/hyprland-unprivileged
RUN chmod 0755 /usr/local/bin/hyprland-seatd-entrypoint /usr/local/bin/hyprland-unprivileged

ENTRYPOINT ["/usr/local/bin/hyprland-seatd-entrypoint"]
