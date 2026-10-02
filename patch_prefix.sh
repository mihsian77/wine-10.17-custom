#!/usr/bin/env bash
# ==============================================================================
# patch_prefix.sh - 定制 Wine prefixPack 为中文环境
# 输出未压缩tar，由调用方决定xz/zstd压缩格式
# 用法：patch_prefix.sh <输入prefixPack> <输出.tar> [字体目录]
# ==============================================================================
set -euo pipefail

INPUT="${1:?用法: patch_prefix.sh <输入> <输出.tar> [字体目录]}"
OUTPUT="${2:?缺少输出路径}"
FONT_DIR="${3:-}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [prefix] 解包 ${INPUT}..."
mkdir -p "${WORK}/root"
# 自动识别压缩格式
if file "${INPUT}" | grep -qi zstd; then
  zstd -d "${INPUT}" -o "${WORK}/prefix.tar" --force 2>/dev/null || \
  python3 -c "
import zstandard
d=zstandard.ZstdDecompressor()
with open('${INPUT}','rb') as f: data=d.decompress(f.read(), max_output_size=500*1024*1024)
open('${WORK}/prefix.tar','wb').write(data)
"
elif file "${INPUT}" | grep -qi xz; then
  xz -d "${INPUT}" -c > "${WORK}/prefix.tar"
else
  cp "${INPUT}" "${WORK}/prefix.tar"
fi
tar -xf "${WORK}/prefix.tar" -C "${WORK}/root"

SYSREG="${WORK}/root/.wine/system.reg"
USERREG="${WORK}/root/.wine/user.reg"
FONTSDIR="${WORK}/root/.wine/drive_c/windows/Fonts"
mkdir -p "${FONTSDIR}"

echo "==> [prefix] 修改 system.reg 代码页/区域/字体替换..."
sed -i 's/"ACP"="1252"/"ACP"="936"/' "$SYSREG"
sed -i 's/"OEMCP"="437"/"OEMCP"="936"/' "$SYSREG"
sed -i 's/"Default"="0409"/"Default"="0804"/' "$SYSREG"
sed -i 's/"InstallLanguage"="0409"/"InstallLanguage"="0804"/' "$SYSREG"
# Locale段默认值 00000409 → 00000804
python3 - "$SYSREG" <<'PYEOF'
import sys, re
p = sys.argv[1]
with open(p, encoding='utf-8') as f: content = f.read()
def fix_locale(m):
    block = m.group(0)
    block = block.replace('@="00000409"', '@="00000804"', 1)
    return block
content = re.sub(r'\[System\\\\[^\]]*Nls\\\\Locale\][^\[]*', fix_locale, content, count=1, flags=re.DOTALL)
with open(p, 'w', encoding='utf-8') as f: f.write(content)
PYEOF
sed -i 's/"MS Shell Dlg"="Tahoma"/"MS Shell Dlg"="Noto Sans CJK SC"/' "$SYSREG"
sed -i 's/"MS Shell Dlg 2"="Tahoma"/"MS Shell Dlg 2"="Noto Sans CJK SC"/' "$SYSREG"

echo "==> [prefix] 修改 user.reg 区域设置..."
sed -i 's/"Locale"="00000409"/"Locale"="00000804"/' "$USERREG"
sed -i 's/"LocaleName"="en-US"/"LocaleName"="zh-CN"/' "$USERREG"
sed -i 's/"sLanguage"="ENU"/"sLanguage"="CHS"/' "$USERREG"

echo "==> [prefix] 注入中文字体..."
FONT_COUNT=0
if [ -n "$FONT_DIR" ] && [ -d "$FONT_DIR" ]; then
  for f in "${FONT_DIR}"/*.otf "${FONT_DIR}"/*.ttf "${FONT_DIR}"/*.ttc; do
    [ -f "$f" ] || continue
    cp -v "$f" "${FONTSDIR}/"
    FONT_COUNT=$((FONT_COUNT+1))
  done
fi
echo "  字体注入数: ${FONT_COUNT}"

echo "==> [prefix] 打包为未压缩tar: ${OUTPUT}..."
mkdir -p "$(dirname "$OUTPUT")"
cd "${WORK}/root"
tar -cf "${OUTPUT}" .
echo "==> [prefix] 完成: ${OUTPUT}"
