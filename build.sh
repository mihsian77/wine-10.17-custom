#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Wine 10.17 Custom - 原生多语言汉化版构建脚本 v3
# 关键改进：分阶段编译（native tools+NLS先编译，确保wrc正确加载po翻译）
# 打包：wcp(根目录bin/lib/share+prefixPack.txz) + whp(wine-ver/+container-pattern.tzst)
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
echo "==> Wine ${WINEVER} WOW64 Build v3 (分阶段编译 + NLS全语言)..."
echo "================================================================="

unset PKG_CONFIG_PATH PKG_CONFIG_SYSROOT_DIR

if [ "${INSTALL_DEPS}" = true ]; then
  echo "==> Installing dependencies (incl. gettext)..."
  sudo apt-get update && sudo apt-get install -y \
    build-essential bison flex pkg-config \
    gcc-multilib g++-multilib \
    gcc-mingw-w64-i686 g++-mingw-w64-i686 \
    gcc-mingw-w64-x86-64 g++-mingw-w64-x86-64 mingw-w64 \
    gettext zstd xz-utils \
    libfreetype-dev libfontconfig1-dev libgl1-mesa-dev libglu1-mesa-dev \
    libvulkan-dev libsdl2-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
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

# ==============================================================================
# 阶段0: configure
# ==============================================================================

# ==============================================================================
# GStreamer 兼容性补丁（Ubuntu 22.04 的 GStreamer 1.20 没有 GstBufferMapInfo）
# GstBufferMapInfo 是 GStreamer 1.24+ 对 GstMapInfo 的别名，功能完全一致
# ==============================================================================
echo "==> 应用 GStreamer 1.20 兼容性补丁..."
grep -rl "GstBufferMapInfo" "${WINE_SRC_DIR}/dlls/winegstreamer/" 2>/dev/null | while read f; do
  sed -i 's/GstBufferMapInfo/GstMapInfo/g' "$f"
  echo "  已修复: $(realpath --relative-to="${WINE_SRC_DIR}" "$f")"
done

if [ ! -f "Makefile" ]; then
  echo "==> [阶段0] Running Wine ./configure (NLS enabled)..."
  ../configure --prefix="${INSTALL_PREFIX}" \
    --enable-archs=i386,x86_64 \
    --enable-win64 \
    --with-mingw \
    --enable-nls \
    --with-freetype --with-fontconfig --with-gstreamer \
    --with-vulkan --with-opengl --with-sdl --with-gnutls \
    --with-xrandr --with-xrender --with-gssapi --with-krb5 \
    --with-pulse --with-alsa --with-openal --with-mpg123 \
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

# ==============================================================================
# 阶段1: 编译 native Wine tools (wrc/winebuild等) + NLS
# 关键：wrc需要在编译PE资源前就绪，才能加载po/<lang>.mo嵌入翻译
# ==============================================================================
echo "==> [阶段1] 编译 native tools + NLS..."
make __tooldeps__ -j"${NPROC}"
echo "  native tools 完成"

# 编译 NLS（语言资源 .mo 文件）
if [ -d "nls" ]; then
  make -C nls -j"${NPROC}"
  echo "  NLS 编译完成"
  # 验证 NLS 输出
  if [ -f "nls/locale.nls" ]; then
    echo "  ✓ locale.nls 已生成"
  else
    echo "  ⚠️ locale.nls 未找到"
  fi
fi

# 验证 wrc 能找到 po 翻译
if [ -f "tools/wrc/wrc" ]; then
  echo "  ✓ wrc 已编译"
  # 检查 po 目录的 .mo 文件
  MO_COUNT=$(find ../po -name "*.mo" 2>/dev/null | wc -l)
  echo "  po 目录 .mo 文件数: ${MO_COUNT}"
fi

# ==============================================================================
# 阶段2: 全量编译（PE 模块，wrc加载NLS翻译嵌入资源）
# ==============================================================================
echo "==> [阶段2] 全量编译 Wine (${NPROC} threads)..."
make -j"${NPROC}"

echo "==> Installing..."
make install STRIP=true

# ==============================================================================
# 体积优化
# ==============================================================================
echo "==> 体积优化..."
# 删除静态库和def文件
find "${INSTALL_PREFIX}" -type f \( -name "*.a" -o -name "*.def" \) -delete
# 删除文档和man
rm -rf "${INSTALL_PREFIX}/share/man" "${INSTALL_PREFIX}/share/doc"
# 删除include（运行时不需要）
rm -rf "${INSTALL_PREFIX}/include"

# 激进 strip：--strip-all 比 --strip-unneeded 更彻底
echo "  Stripping ELF .so..."
find "${INSTALL_PREFIX}" -name "*.so*" -exec strip --strip-all {} + 2>/dev/null || true
echo "  Stripping PE x86_64..."
find "${INSTALL_PREFIX}" -path "*x86_64-windows*" \( -name "*.dll" -o -name "*.exe" \) -exec x86_64-w64-mingw32-strip --strip-all {} + 2>/dev/null || true
echo "  Stripping PE i386..."
find "${INSTALL_PREFIX}" -path "*i386-windows*" \( -name "*.dll" -o -name "*.exe" \) -exec i686-w64-mingw32-strip --strip-all {} + 2>/dev/null || true

# 验证
echo "==> Verifying PE output..."
[ -f "${INSTALL_PREFIX}/lib/wine/i386-windows/ntdll.dll" ] || { echo "ERROR: missing i386 ntdll"; exit 1; }
[ -f "${INSTALL_PREFIX}/lib/wine/x86_64-windows/ntdll.dll" ] || { echo "ERROR: missing x86_64 ntdll"; exit 1; }
echo "SUCCESS: PE modules verified"

# 验证 NLS 嵌入：检查 PE 文件中的语言资源
echo "==> 验证 NLS 翻译嵌入..."
if command -v wrestool &>/dev/null; then
  for dll in "${INSTALL_PREFIX}/lib/wine/x86_64-windows/shell32.dll" "${INSTALL_PREFIX}/lib/wine/x86_64-windows/explorer.exe"; do
    [ -f "$dll" ] || continue
    LANG_COUNT=$(wrestool -l "$dll" 2>/dev/null | grep -c "STRING" || true)
    echo "  $(basename $dll): STRING资源组数=${LANG_COUNT}"
  done
else
  echo "  (wrestool未安装，跳过PE资源验证)"
fi

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
# glibc兼容性检查（确认wine二进制依赖的glibc版本）
# ==============================================================================
echo "==> glibc兼容性检查..."
echo "  编译环境glibc版本: $(ldd --version | head -1)"
for bin in wine wine64 winecfg wineserver; do
  if [ -f "${INSTALL_PREFIX}/bin/${bin}" ]; then
    GLIBC_VER=$(objdump -T "${INSTALL_PREFIX}/bin/${bin}" 2>/dev/null | grep -oP 'GLIBC_[0-9.]+' | sort -V | tail -1)
    echo "  ${bin}: 最高依赖 ${GLIBC_VER}"
  fi
done
echo "  注意：Winlator rootfs glibc版本必须 >= 上述版本"

# ==============================================================================
# Package WCP format
# ==============================================================================
echo "==> Packaging WCP format..."
WCP_TMP="${BUILD_DIR}/wcp-tmp"
rm -rf "${WCP_TMP}"
mkdir -p "${WCP_TMP}"

cp -r "${INSTALL_PREFIX}/bin" "${WCP_TMP}/"
cp -r "${INSTALL_PREFIX}/lib" "${WCP_TMP}/"
[ -d "${INSTALL_PREFIX}/share" ] && cp -r "${INSTALL_PREFIX}/share" "${WCP_TMP}/"

xz -T0 -9e -c "${PREFIX_TAR}" > "${WCP_TMP}/prefixPack.txz"

cat > "${WCP_TMP}/profile.json" <<EOF
{
  "type": "Wine",
  "versionName": "${WINEVER}-amd64",
  "versionCode": 1,
  "description": "Wine ${WINEVER} amd64 - NLS multi-language Chinese localized (分阶段编译)",
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
# Package WHP format
# 注意：不包含container-pattern，让winlator-pulse自己用winecfg生成
# 这样可以测试wine二进制本身能否在目标环境运行
# ==============================================================================
echo "==> Packaging WHP format (no container-pattern, let app generate)..."
WHP_TMP="${BUILD_DIR}/whp-tmp"
rm -rf "${WHP_TMP}"
mkdir -p "${WHP_TMP}"

WINE_DIR="${WHP_TMP}/${PKG_BASENAME}-"
mkdir -p "${WINE_DIR}"
cp -r "${INSTALL_PREFIX}/bin" "${WINE_DIR}/"
cp -r "${INSTALL_PREFIX}/lib" "${WINE_DIR}/"
[ -d "${INSTALL_PREFIX}/share" ] && cp -r "${INSTALL_PREFIX}/share" "${WINE_DIR}/"

cd "${WHP_TMP}"
tar -I "xz -T0 -9e" -cf "${DIST_DIR}/${PKG_BASENAME}.whp" "${PKG_BASENAME}-"
echo "  WHP: ${DIST_DIR}/${PKG_BASENAME}.whp ($(du -h "${DIST_DIR}/${PKG_BASENAME}.whp" | cut -f1))"

echo "================================================================="
echo "BUILD COMPLETE (v3 分阶段编译)!"
ls -lh "${DIST_DIR}/"
echo "================================================================="
