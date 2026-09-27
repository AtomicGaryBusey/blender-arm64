# Build environment for Blender 5.2.2 on NVIDIA DGX Spark (GB10, aarch64, sm_121).
#
# This image is ONLY a toolchain. Sources and build trees are bind-mounted from the host
# (~/blender-arm64/_work) and all compilation runs as the unprivileged user `builder`
# via `docker run --user`, never as root. See build.sh.
#
# Base image: CUDA 13.0.3 devel (nvcc 13.0.88, headers, driver stubs) pinned by the
# arm64 manifest digest. CUDA must stay 13.0.x: OptiX kernels ship as PTX that the
# R580 driver JIT-compiles, and PTX from a newer toolkit would not load.
#   tag:  nvcr.io/nvidia/cuda:13.0.3-devel-ubuntu24.04  (linux/arm64)
FROM nvcr.io/nvidia/cuda@sha256:2396393dc8a031a6faf810894ec8e40c8d80e2a1177cfda0c2bf81acac9aa240

LABEL org.zebeth.blender-gb10="1" \
      org.opencontainers.image.title="blender-gb10-builder" \
      org.opencontainers.image.description="Toolchain for reproducible Blender 5.2.2 builds for DGX Spark" \
      org.opencontainers.image.source="https://github.com/AtomicGaryBusey/blender-arm64"

ARG DEBIAN_FRONTEND=noninteractive
ARG BUILDER_UID=1000
ARG BUILDER_GID=1000

# Ubuntu packages come from the noble archive (dpkg-managed, inside the image only).
# snapshot.ubuntu.com does not serve ubuntu-ports (arm64), so the archive cannot be frozen
# at a timestamp. Instead the resolved package list is written to
# /etc/blender-gb10/dpkg-manifest.txt and build.sh compares it with the committed
# deps/dpkg-manifest.lock (warning, or error with BLENDER_GB10_STRICT_APT=1).
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates curl xz-utils bzip2 unzip zstd file patch make rsync \
      build-essential gcc g++ gcc-14 g++-14 \
      cmake ninja-build pkg-config \
      autoconf automake libtool help2man autogen autopoint gettext texinfo \
      patchelf tcl yasm bison flex libncurses-dev zlib1g-dev perl \
      python3 git \
      libx11-dev libxcursor-dev libxi-dev libxinerama-dev libxrandr-dev libxt-dev \
      libxxf86vm-dev libxkbcommon-dev libxfixes-dev libxext-dev libxrender-dev \
      libgl-dev libegl-dev libglu1-mesa-dev libdbus-1-dev libdecor-0-dev \
      libasound2-dev libpulse-dev libjack-jackd2-dev libpipewire-0.3-dev; \
    rm -rf /var/lib/apt/lists/*; \
    # Blender 5.2 requires GCC >= 14 (CMakeLists.txt FATAL_ERROR); make gcc-14 the default
    # compiler for every build system (image-local /usr/local/bin, not dpkg paths).
    for t in gcc g++ cpp gcc-ar gcc-nm gcc-ranlib; do ln -s "/usr/bin/${t}-14" "/usr/local/bin/${t}"; done; \
    ln -s /usr/bin/gcc-14 /usr/local/bin/cc; ln -s /usr/bin/g++-14 /usr/local/bin/c++; \
    mkdir -p /etc/blender-gb10; \
    dpkg-query -W -f='${Package}=${Version}\n' | sort > /etc/blender-gb10/dpkg-manifest.txt

# Unprivileged build user whose UID/GID match the host user so bind-mounted build
# trees stay owned by that user. The stock `ubuntu` user (uid 1000) is removed first.
RUN set -eux; \
    if id ubuntu >/dev/null 2>&1; then userdel -r ubuntu || true; fi; \
    if ! getent group "${BUILDER_GID}" >/dev/null; then groupadd -g "${BUILDER_GID}" builder; fi; \
    useradd -m -u "${BUILDER_UID}" -g "${BUILDER_GID}" -s /bin/bash builder

ENV PATH=/usr/local/cuda-13.0/bin:${PATH} \
    CUDA_HOME=/usr/local/cuda-13.0 \
    CUDAToolkit_ROOT=/usr/local/cuda-13.0 \
    LANG=C.UTF-8 LC_ALL=C.UTF-8 \
    CC=/usr/local/bin/gcc CXX=/usr/local/bin/g++
# SOURCE_DATE_EPOCH is not baked in: build.sh passes the pinned Blender commit time.

USER builder
WORKDIR /work
