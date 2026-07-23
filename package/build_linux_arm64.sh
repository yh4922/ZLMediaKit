#!/usr/bin/env bash
# Build ZLMediaKit for linux/arm64 inside a container or on a native arm64 host.
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

# Detect package manager
if command -v apt-get >/dev/null 2>&1; then
  apt-get update
  apt-get install -y --no-install-recommends \
    git wget ca-certificates gcc g++ make perl python3 \
    tar gzip xz-utils pkg-config
elif command -v yum >/dev/null 2>&1; then
  yum install -y git wget gcc gcc-c++ make perl python3 tar gzip which
else
  echo "Unsupported package manager" >&2
  exit 1
fi

ARCH="$(uname -m)"
case "${ARCH}" in
  aarch64|arm64) CMAKE_ARCH="aarch64" ;;
  x86_64|amd64)  CMAKE_ARCH="x86_64" ;;
  *) echo "Unsupported arch: ${ARCH}" >&2; exit 1 ;;
esac

# Install prebuilt CMake
CMAKE_VER="3.29.5"
CMAKE_DIR="/opt/cmake-${CMAKE_VER}-linux-${CMAKE_ARCH}"
if [ ! -x "${CMAKE_DIR}/bin/cmake" ]; then
  wget -q "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VER}/cmake-${CMAKE_VER}-linux-${CMAKE_ARCH}.tar.gz" \
    -O "/tmp/cmake.tar.gz"
  tar -xzf /tmp/cmake.tar.gz -C /opt
fi
export PATH="${CMAKE_DIR}/bin:${PATH}"
cmake --version
gcc --version
uname -a

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT_DIR}"

INSTALL_DIR="${ROOT_DIR}/thirdparty_install"
mkdir -p "${INSTALL_DIR}"

# OpenSSL (static)
if [ ! -f "${INSTALL_DIR}/lib/libssl.a" ]; then
  cd "${ROOT_DIR}/3rdpart/openssl"
  make distclean >/dev/null 2>&1 || true
  ./config no-shared --prefix="${INSTALL_DIR}"
  make -j"$(nproc)"
  make install_sw
fi

# usrsctp
if [ ! -f /usr/local/lib/libusrsctp.a ] && [ ! -f /usr/local/lib/libusrsctp.so ]; then
  cd "${ROOT_DIR}/3rdpart/usrsctp"
  rm -rf build
  mkdir -p build && cd build
  cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON ..
  make -j"$(nproc)"
  make install
fi

# libsrtp
if [ ! -f /usr/local/lib/libsrtp2.a ] && [ ! -f /usr/local/lib/libsrtp2.so ]; then
  cd "${ROOT_DIR}/3rdpart/libsrtp"
  make distclean >/dev/null 2>&1 || true
  ./configure --enable-openssl --with-openssl-dir="${INSTALL_DIR}"
  make -j"$(nproc)"
  make install
fi

# ZLMediaKit
cd "${ROOT_DIR}"
rm -rf linux_build
mkdir -p linux_build
cd linux_build
cmake .. \
  -DOPENSSL_ROOT_DIR="${INSTALL_DIR}" \
  -DCMAKE_BUILD_TYPE=Release
make -j"$(nproc)"

echo "Build finished. Artifacts under: ${ROOT_DIR}/release"
ls -la "${ROOT_DIR}/release" || true
find "${ROOT_DIR}/release" -type f | head -50
