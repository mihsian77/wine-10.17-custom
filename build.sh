#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Wine 10.17 Custom - 原生多语言汉化版构建脚本
# 基于 royel21/wine-10.17-custom 修改
# 修改点：启用gettext(NLS)翻译编译、版本号校正、双格式打包(wcp.xz+whp)、
#         prefixPack中文环境定制、GitHub Actions友好
# ==============================================================================

# Parse optional arguments
CLEAN_BUILD=false
INSTALL_DEPS=false

for arg in "$@"; do
  case $arg in
    --clean) CLEAN_BUILD=true ;;
    --deps)  INSTALL_DEPS=true ;;
  esac
done

# ==============================================================================
# CONFIGURATION & PATHS
# ==============================================================================
WINE_SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${WINE_SRC_DIR}/wine"
INSTALL_PREFIX="/tmp/wine_build"
DIST_DIR="${WINE_SRC_DIR}/dist"
WINEVER="10.17"
PKG_NAME="Wine-${WINEVER}-x86_64-zh"

echo "================================================================="
echo "==> Starting Wine ${WINEVER} WOW64 Build (NLS multi-language)..."
echo "================================================================="

# 1. Clear Conflict Environment Variables
unset PKG_CONFIG_PATH PKG_CONFIG_SYSROOT_DIR

# 2. Install Build Dependencies (Only when --deps is passed)
if [ "${INSTALL_DEPS}" = true ]; then
  echo "==> Installing Wine host & cross-compiler dependencies (incl. gettext)..."
  sudo apt-get update && sudo apt-get install -y \
    build-essential bison flex pkg-config \
    gcc-mingw-w64-i686 g++-mingw-w64-i686 \
    gcc-mingw-w64-x86-64 g++-mingw-w64-x86-64 mingw-w64 \
    gettext \
    libfreetype-dev libfontconfig1-dev libgl1-mesa-dev libglu1-mesa-dev \
    libvulkan-dev libsdl2-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
    libgstreamer-plugins-good1.0-dev libgstreamer-plugins-bad1.0-dev \
    libasound2-dev libpulse-dev libgnutls28-dev libmpg123-dev \
    libopenal-dev libpng-dev libjpeg-dev libtiff-dev libwebp-dev liblcms2-dev \
    libxml2-dev libxslt1-dev libx11-dev libxcursor-dev libxi-dev \
    libxrandr-dev libxrender-dev tar xz-utils zstd libkrb5-dev libgssapi-krb5-2 krb5-config
fi

# 3. Setup Directories
if [ "${CLEAN_BUILD}" = true ]; then
  echo "==> [--clean passed] Cleaning build and install directories..."
  rm -rf "${BUILD_DIR}" "${INSTALL_PREFIX}"
fi

mkdir -p "${BUILD_DIR}" "${INSTALL_PREFIX}" "${DIST_DIR}"
cd "${BUILD_DIR}"

# 4. Run ./configure ONLY if Makefile does not exist
# 注意：已移除 --without-gettext / --with-gettextpo=no，启用NLS多语言翻译编译
if [ ! -f "Makefile" ]; then
  echo "==> Running Wine ./configure (gettext NLS enabled)..."
  ../configure --prefix="${INSTALL_PREFIX}" \
    --enable-archs=i386,x86_64 \
    --enable-win64 \
    --with-mingw \
    --with-freetype \
    --with-fontconfig \
    --with-gstreamer \
    --with-vulkan \
    --with-opengl \
    --with-sdl \
    --with-gnutls \
    --with-xrandr \
    --with-xrender \
    --with-gssapi \
    --with-krb5 \
    --enable-tools \
    --disable-tests \
    --disable-win16 \
    --without-unwind \
    --without-dbus \
    --without-inotify \
    --without-netapi \
    --without-xshape \
    --without-xxf86vm \
    --without-xshm \
    --without-xcomposite \
    --without-xfixes \
    --without-xinerama \
    --without-capi \
    --without-coreaudio \
    --without-cups \
    --without-gphoto \
    --without-sane \
    --without-oss \
    --without-pcap \
    --without-pcsclite \
    --without-sane \
    --without-udev \
    --without-usb \
    --without-v4l2 \
    --without-wayland \
    --without-ffmpeg \
    --without-opencl \
    --without-vosk
fi

# 5. Incremental Compilation Across All CPU Cores
NPROC=$(nproc)
echo "==> Compiling Wine using ${NPROC} threads..."
make -j"${NPROC}"

# 6. Install Binaries
echo "==> Installing binaries to ${INSTALL_PREFIX}..."
make install STRIP=true

# 7. Aggressive Pruning & Stripping (Reduces package to ~100-130MB)
echo "==> Pruning static libraries, def files, and manuals..."
find "${INSTALL_PREFIX}" -type f \( -name "*.a" -o -name "*.def" \) -delete
rm -rf "${INSTALL_PREFIX}/share/man"
rm -rf "${INSTALL_PREFIX}/share/doc"

echo "==> Stripping Linux host binaries..."
find "${INSTALL_PREFIX}" -name "*.so*" -exec strip --strip-unneeded {} + 2>/dev/null || true

echo "==> Stripping Windows MinGW PE binaries..."
find "${INSTALL_PREFIX}" -name "*.dll" -exec x86_64-w64-mingw32-strip --strip-unneeded {} + 2>/dev/null || true
find "${INSTALL_PREFIX}" -name "*.exe" -exec x86_64-w64-mingw32-strip --strip-unneeded {} + 2>/dev/null || true
find "${INSTALL_PREFIX}" -name "*.dll" -exec i686-w64-mingw32-strip --strip-unneeded {} + 2>/dev/null || true
find "${INSTALL_PREFIX}" -name "*.exe" -exec i686-w64-mingw32-strip --strip-unneeded {} + 2>/dev/null || true

# 8. Verification Steps
echo "==> Verifying PE architecture output..."
if [ -f "${INSTALL_PREFIX}/lib/wine/i386-windows/ntdll.dll" ] && [ -f "${INSTALL_PREFIX}/lib/wine/x86_64-windows/ntdll.dll" ]; then
  echo "SUCCESS: Both i386-windows and x86_64-windows PE modules verified!"
else
  echo "ERROR: Missing required PE ntdll.dll binaries."
  exit 1
fi

# 9. Customize prefixPack (中文环境: ACP=936, locale=0804, Noto字体, 字体替换)
echo "==> Customizing prefixPack for Chinese locale..."
CUSTOM_PREFIX="${BUILD_DIR}/prefixPack-custom.tzst"
if [ -x "${WINE_SRC_DIR}/patch_prefix.sh" ]; then
  PATCH_ARGS=("${WINE_SRC_DIR}/prefixPack.tzst" "${CUSTOM_PREFIX}")
  [ -n "${FONT_DIR:-}" ] && PATCH_ARGS+=("${FONT_DIR}")
  bash "${WINE_SRC_DIR}/patch_prefix.sh" "${PATCH_ARGS[@]}"
  PREFIX_PACK="${CUSTOM_PREFIX}"
else
  echo "WARNING: patch_prefix.sh not found, using original prefixPack (English env)"
  PREFIX_PACK="${WINE_SRC_DIR}/prefixPack.tzst"
fi

# 10. Inject profile.json and prefixPack
echo "==> Injecting profile.json and prefixPack..."

cat > "${INSTALL_PREFIX}/profile.json" <<EOF
{
    "type": "Wine",
    "versionName": "${WINEVER}-x86_64-zh",
    "versionCode": 0,
    "description": "Wine ${WINEVER} x86_64 - Native multi-language (zh_CN/zh_TW + 49 locales) Chinese localized build",
    "files": [],
    "wine": {
        "binPath": "bin",
        "libPath": "lib",
        "prefixPack": "prefixPack.tzst"
    }
}
EOF

cp -v "${PREFIX_PACK}" "${INSTALL_PREFIX}/prefixPack.tzst"

# 11. Package into dual formats: .wcp.xz (ludashi) and .whp (pulse)
echo "==> Packaging into dual formats..."
cd "${INSTALL_PREFIX}"

# 统一用xz压缩（ludashi先试XZ、pulse按magic识别XZ/ZSTD，两者都吃xz）
TAR_XZ="${DIST_DIR}/${PKG_NAME}.tar.xz"
tar --exclude='include' -cJf "${TAR_XZ}" .

# ludashi_plus 格式
cp -v "${TAR_XZ}" "${DIST_DIR}/${PKG_NAME}.wcp.xz"
# winlator-pulse 格式（同内容，仅扩展名）
cp -v "${TAR_XZ}" "${DIST_DIR}/${PKG_NAME}.whp"
rm -f "${TAR_XZ}"

echo "================================================================="
echo "BUILD COMPLETE!"
echo "Packages in: ${DIST_DIR}/"
ls -lh "${DIST_DIR}/"
echo "================================================================="
