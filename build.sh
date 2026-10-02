#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Wine 10.17 Custom - 原生多语言汉化版构建脚本
# 参照 Waim908/wine-winlator 的 wcp/whp 打包结构
# ==============================================================================

CLEAN_BUILD=false
INSTALL_DEPS=false

for arg in "$@"; do
  case $arg in
    --clean) CLEAN_BUILD=true ;;
    --deps)  INSTALL_DEPS=true ;;
  esac
done

WINE_SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${WINE_SRC_DIR}/wine"
INSTALL_PREFIX="/tmp/wine_build"
DIST_DIR="${WINE_SRC_DIR}/dist"
WINEVER="10.17"
PKG_BASENAME="wine-${WINEVER}"

echo "================================================================="
echo "==> Starting Wine ${WINEVER} WOW64 Build (NLS multi-language)..."
echo "================================================================="

unset PKG_CONFIG_PATH PKG_CONFIG_SYSROOT_DIR

if [ "${INSTALL_DEPS}" = true ]; then
  echo "==> Installing dependencies (incl. gettext)..."
  sudo apt-get update && sudo apt-get install -y \
    build-essential bison flex pkg-config \
    gcc-mingw-w64-i686 g++-mingw-w64-i686 \
    gcc-mingw-w64-x86-64 g++-mingw-w64-x86-64 mingw-w64 \
    gettext zstd xz-utils \
    libfreetype-dev libfontconfig1-dev libgl1-mesa-dev libglu1-mesa-dev \
    libvulkan-dev libsdl2-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
    libgstreamer-plugins-good1.0-dev libgstreamer-plugins-bad1.0-dev \
    libasound2-dev libpulse-dev libgnutls28-dev libmpg123-dev \
    libopenal-dev libpng-dev libjpeg-dev libtiff-dev libwebp-dev liblcms2-dev \
    libxml2-dev libxslt1-dev libx11-dev libxcursor-dev libxi-dev \
    libxrandr-dev libxrender-dev libkrb5-dev libgssapi-krb5-2 krb5-config
fi

if [ "${CLEAN_BUILD}" = true ]; then
  rm -rf "${BUILD_DIR}" "${INSTALL_PREFIX}"
fi

mkdir -p "${BUILD_DIR}" "${INSTALL_PREFIX}" "${DIST_DIR}"
cd "${BUILD_DIR}"

# configure (gettext NLS enabled)
if [ ! -f "Makefile" ]; then
  echo "==> Running Wine ./configure (NLS enabled)..."
  ../configure --prefix="${INSTALL_PREFIX}" \
    --enable-archs=i386,x86_64 \
    --enable-win64 \
    --with-mingw \
    --with-freetype --with-fontconfig --with-gstreamer \
    --with-vulkan --with-opengl --with-sdl --with-gnutls \
    --with-xrandr --with-xrender --with-gssapi --with-krb5 \
    --enable-tools --disable-tests --disable-win16 \
    --without-unwind --without-dbus --without-inotify --without-netapi \
    --without-xshape --without-xxf86vm --without-xshm --without-xcomposite \
    --without-xfixes --without-xinerama --without-capi --without-coreaudio \
    --without-cups --without-gphoto --without-sane --without-oss \
    --without-pcap --without-pcsclite --without-udev --without-usb \
    --without-v4l2 --without-wayland --without-ffmpeg --without-opencl \
    --without-vosk
fi

NPROC=$(nproc)
echo "==> Compiling Wine (${NPROC} threads)..."
make -j"${NPROC}"

echo "==> Installing..."
make install STRIP=true

# Prune
echo "==> Pruning..."
find "${INSTALL_PREFIX}" -type f \( -name "*.a" -o -name "*.def" \) -delete
rm -rf "${INSTALL_PREFIX}/share/man" "${INSTALL_PREFIX}/share/doc"
rm -rf "${INSTALL_PREFIX}/include"

echo "==> Stripping..."
find "${INSTALL_PREFIX}" -name "*.so*" -exec strip --strip-unneeded {} + 2>/dev/null || true
find "${INSTALL_PREFIX}" -name "*.dll" -exec x86_64-w64-mingw32-strip --strip-unneeded {} + 2>/dev/null || true
find "${INSTALL_PREFIX}" -name "*.exe" -exec x86_64-w64-mingw32-strip --strip-unneeded {} + 2>/dev/null || true
find "${INSTALL_PREFIX}" -name "*.dll" -exec i686-w64-mingw32-strip --strip-unneeded {} + 2>/dev/null || true
find "${INSTALL_PREFIX}" -name "*.exe" -exec i686-w64-mingw32-strip --strip-unneeded {} + 2>/dev/null || true

# Verify
echo "==> Verifying PE output..."
[ -f "${INSTALL_PREFIX}/lib/wine/i386-windows/ntdll.dll" ] || { echo "ERROR: missing i386 ntdll"; exit 1; }
[ -f "${INSTALL_PREFIX}/lib/wine/x86_64-windows/ntdll.dll" ] || { echo "ERROR: missing x86_64 ntdll"; exit 1; }
echo "SUCCESS: PE modules verified"

# ==============================================================================
# Customize prefixPack (中文环境)
# ==============================================================================
echo "==> Customizing prefixPack..."
PREFIX_TAR="${BUILD_DIR}/prefix-custom.tar"
if [ -x "${WINE_SRC_DIR}/patch_prefix.sh" ]; then
  PATCH_ARGS=("${WINE_SRC_DIR}/prefixPack.tzst" "${PREFIX_TAR}")
  [ -n "${FONT_DIR:-}" ] && PATCH_ARGS+=("${FONT_DIR}")
  bash "${WINE_SRC_DIR}/patch_prefix.sh" "${PATCH_ARGS[@]}"
else
  echo "WARNING: patch_prefix.sh not found, using original"
  if file "${WINE_SRC_DIR}/prefixPack.tzst" | grep -qi zstd; then
    zstd -d "${WINE_SRC_DIR}/prefixPack.tzst" -o "${PREFIX_TAR}" --force
  else
    cp "${WINE_SRC_DIR}/prefixPack.tzst" "${PREFIX_TAR}"
  fi
fi

# ==============================================================================
# Package WCP format (for ludashi_plus / bionic)
# 结构: 根目录 bin/ lib/ share/ profile.json prefixPack.txz
# 外层: zstd --ultra -22
# ==============================================================================
echo "==> Packaging WCP format..."
WCP_TMP="${BUILD_DIR}/wcp-tmp"
rm -rf "${WCP_TMP}"
mkdir -p "${WCP_TMP}"

cp -r "${INSTALL_PREFIX}/bin" "${WCP_TMP}/"
cp -r "${INSTALL_PREFIX}/lib" "${WCP_TMP}/"
[ -d "${INSTALL_PREFIX}/share" ] && cp -r "${INSTALL_PREFIX}/share" "${WCP_TMP}/"

# prefixPack.txz (xz压缩)
xz -T0 -9e -c "${PREFIX_TAR}" > "${WCP_TMP}/prefixPack.txz"

# profile.json
cat > "${WCP_TMP}/profile.json" <<EOF
{
  "type": "Wine",
  "versionName": "${WINEVER}-amd64",
  "versionCode": 1,
  "description": "Wine ${WINEVER} amd64 - NLS multi-language Chinese localized build",
  "files": [],
  "wine": {
    "binPath": "bin",
    "libPath": "lib",
    "prefixPack": "prefixPack.txz"
  }
}
EOF

cd "${WCP_TMP}"
tar -I "zstd -T0 --ultra -22" -cf "${DIST_DIR}/${PKG_BASENAME}-amd64.wcp" .
echo "  WCP: ${DIST_DIR}/${PKG_BASENAME}-amd64.wcp ($(du -h "${DIST_DIR}/${PKG_BASENAME}-amd64.wcp" | cut -f1))"

# ==============================================================================
# Package WHP format (for winlator-pulse)
# 结构: wine-$ver-/ (bin/lib/share) + container-pattern-$ver.tzst
# 外层: xz -9e
# ==============================================================================
echo "==> Packaging WHP format..."
WHP_TMP="${BUILD_DIR}/whp-tmp"
rm -rf "${WHP_TMP}"
mkdir -p "${WHP_TMP}"

# wine-$ver-/ 子目录
WINE_DIR="${WHP_TMP}/${PKG_BASENAME}-"
mkdir -p "${WINE_DIR}"
cp -r "${INSTALL_PREFIX}/bin" "${WINE_DIR}/"
cp -r "${INSTALL_PREFIX}/lib" "${WINE_DIR}/"
[ -d "${INSTALL_PREFIX}/share" ] && cp -r "${INSTALL_PREFIX}/share" "${WINE_DIR}/"

# container-pattern-$ver.tzst (zstd压缩的prefixPack)
zstd -T0 -9 -c "${PREFIX_TAR}" > "${WHP_TMP}/container-pattern-${WINEVER}.tzst"

cd "${WHP_TMP}"
tar -I "xz -T0 -9e" -cf "${DIST_DIR}/${PKG_BASENAME}.whp" "${PKG_BASENAME}-" "container-pattern-${WINEVER}.tzst"
echo "  WHP: ${DIST_DIR}/${PKG_BASENAME}.whp ($(du -h "${DIST_DIR}/${PKG_BASENAME}.whp" | cut -f1))"

echo "================================================================="
echo "BUILD COMPLETE!"
ls -lh "${DIST_DIR}/"
echo "================================================================="
