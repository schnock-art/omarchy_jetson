FROM quickshell:phase1-hypr-audio
ADD --checksum=sha256:0ec29a68b539ece7078fc714cebff0c0accb2f4948f8f7963d9f5e86633b12d9 https://raw.githubusercontent.com/ryanoasis/nerd-fonts/v3.4.0/patched-fonts/JetBrainsMono/Ligatures/Regular/JetBrainsMonoNerdFont-Regular.ttf /usr/local/share/fonts/JetBrainsMonoNerdFont-Regular.ttf
RUN chmod 644 /usr/local/share/fonts/JetBrainsMonoNerdFont-Regular.ttf && fc-cache -f
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3-gi gir1.2-glib-2.0 \
 && apt-get clean
