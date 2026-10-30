FROM debian:13@sha256:4c25275446ca371766b8b093c696782eabce06263fccacb8d5d813b3dc44b308

# Prepare-only host candidate. This image has no app or native input launcher.
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl
RUN printf '%s\n' \
    'deb [check-valid-until=no signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] https://snapshot.debian.org/archive/debian/20261027T000000Z/ trixie main' \
    'deb [check-valid-until=no signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] https://snapshot.debian.org/archive/debian-security/20261027T000000Z/ trixie-security main' > /tmp/gpui-frozen-sources.list \
    && apt-get -o Dir::Etc::sourcelist=/tmp/gpui-frozen-sources.list -o Dir::Etc::sourceparts=- update \
    && printf '%s  %s\n' \
      '0584fba32e13e0ab8285fb16c27adea1ec03a73669c18702821094fd6ca86675' '/var/lib/apt/lists/snapshot.debian.org_archive_debian_20261027T000000Z_dists_trixie_InRelease' \
      'dfab8e28ea58bbf3bc3840bbd099d3e52ed44f72e447220e0b1b7c12ab0c0baf' '/var/lib/apt/lists/snapshot.debian.org_archive_debian-security_20261027T000000Z_dists_trixie-security_InRelease' | sha256sum -c - \
    && apt-get -o Dir::Etc::sourcelist=/tmp/gpui-frozen-sources.list -o Dir::Etc::sourceparts=- install -y --allow-downgrades --no-install-recommends ca-certificates git curl build-essential pkg-config python3 python3-pil dbus-daemon libnotify4 libgtk-3-0t64 libgtk2.0-0t64 libgspell-1-3 weston gir1.2-gtk-3.0 gir1.2-ibus-1.0 libunwind8 libgl1 x11-xkb-utils libegl1 libgles2 libgl1-mesa-dri libgbm1 libx11-6 libxtst6 libxfont2 libxrender1 libxext6 libxfixes3 libxau6 libxdmcp6 libpixman-1-0 libepoxy0 libdrm2 libudev1 libinput10 libxcb1 libxcursor1 libxkbcommon0 libwayland-client0 libwayland-server0 libwayland-cursor0 libwayland-egl1 imagemagick tesseract-ocr tesseract-ocr-eng patch xz-utils passwd util-linux \
    && rm -rf /var/lib/apt/lists/*
