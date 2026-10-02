#!/usr/bin/env bash
# ==============================================================================
# patch_prefix.sh - 定制 Wine prefixPack 为中文环境
# 用途：解包原版prefixPack.tzst → 修改注册表(locale/代码页/字体替换) →
#       注入Noto Sans CJK SC字体 → 重新打包为tzst
# 用法：patch_prefix.sh <输入prefixPack.tzst> <输出prefixPack.tzst> [字体目录]
# 修改原因：原版prefixPack是纯英文环境(ACP=1252, locale=0409, 无中文字体)，
#           导致中文乱码/方框/中文路径异常
# 影响范围：仅prefixPack内的.wine注册表和Fonts，不影响bin/lib
# 回滚方法：使用原版prefixPack.tzst替换
# ==============================================================================
set -euo pipefail

INPUT="${1:?用法: patch_prefix.sh <输入> <输出> [字体目录]}"
OUTPUT="${2:?缺少输出路径}"
FONT_DIR="${3:-}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [prefix] 解包 ${INPUT}..."
mkdir -p "${WORK}/root"
if command -v zstd >/dev/null 2>&1; then
  zstd -d "${INPUT}" -o "${WORK}/prefix.tar" --force
else
  python3 -c "
import zstandard
d=zstandard.ZstdDecompressor()
with open('${INPUT}','rb') as f: data=d.decompress(f.read(), max_output_size=500*1024*1024)
open('${WORK}/prefix.tar','wb').write(data)
"
fi
tar -xf "${WORK}/prefix.tar" -C "${WORK}/root"

SYSREG="${WORK}/root/.wine/system.reg"
USERREG="${WORK}/root/.wine/user.reg"
FONTSDIR="${WORK}/root/.wine/drive_c/windows/Fonts"
mkdir -p "${FONTSDIR}"

echo "==> [prefix] 修改 system.reg 代码页/区域/字体替换..."
# ACP/OEMCP: 1252/437 → 936 (GBK简体中文)
sed -i 's/"ACP"="1252"/"ACP"="936"/' "$SYSREG"
sed -i 's/"OEMCP"="437"/"OEMCP"="936"/' "$SYSREG"
# 默认UI语言/安装语言: 0409(en-US) → 0804(zh-CN)
sed -i 's/"Default"="0409"/"Default"="0804"/' "$SYSREG"
sed -i 's/"InstallLanguage"="0409"/"InstallLanguage"="0804"/' "$SYSREG"
# Locale段默认值: 00000409 → 00000804 (仅匹配Locale段内的@=行)
python3 - "$SYSREG" <<'PYEOF'
import sys, re
p = sys.argv[1]
with open(p, encoding='utf-8') as f:
    content = f.read()
# 在 [..Nls\Locale] 段内把 @="00000409" 改为 @="00000804"
def fix_locale(m):
    block = m.group(0)
    block = block.replace('@="00000409"', '@="00000804"', 1)
    return block
content = re.sub(r'\[System\\\\[^\]]*Nls\\\\Locale\][^\[]*', fix_locale, content, count=1, flags=re.DOTALL)
with open(p, 'w', encoding='utf-8') as f:
    f.write(content)
PYEOF
# 字体替换: MS Shell Dlg / MS Shell Dlg 2 → Noto Sans CJK SC
sed -i 's/"MS Shell Dlg"="Tahoma"/"MS Shell Dlg"="Noto Sans CJK SC"/' "$SYSREG"
sed -i 's/"MS Shell Dlg 2"="Tahoma"/"MS Shell Dlg 2"="Noto Sans CJK SC"/' "$SYSREG"

echo "==> [prefix] 修改 user.reg 区域设置..."
# user.reg: Locale 00000409 → 00000804, LocaleName en-US → zh-CN, sLanguage ENU → CHS
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
if [ "$FONT_COUNT" -eq 0 ]; then
  echo "WARNING: 未找到中文字体文件，Fonts目录将为空（UI可能方框）"
  echo "  请在Actions中下载Noto Sans CJK SC到字体目录"
fi

echo "==> [prefix] 重新打包为 ${OUTPUT}..."
mkdir -p "$(dirname "$OUTPUT")"
cd "${WORK}/root"
if command -v zstd >/dev/null 2>&1; then
  tar -cf - . | zstd -T0 --ultra -16 -o "${OUTPUT}"
else
  tar -cf "${WORK}/prefix-out.tar" .
  python3 -c "
import zstandard
c=zstandard.ZstdCompressor(level=16, threads=-1)
with open('${WORK}/prefix-out.tar','rb') as f, open('${OUTPUT}','wb') as out:
    c.copy_stream(f, out)
"
fi

echo "==> [prefix] 完成: ${OUTPUT} ($(du -h "$OUTPUT" | cut -f1))"
echo "    字体注入数: ${FONT_COUNT}"
