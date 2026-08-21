#!/usr/bin/env bash
# Пиксель-арт → GIF без потери пикселей. Переносить в tools/make_gif.sh.
#
# Почему не «просто ffmpeg -i in.avi out.gif»: дефолтный ресайз bicubic
# размажет пиксели, а дефолтный дизеринг добавит цвета вне нашей палитры
# из 32 цветов (research/34 §4.1, research/29 §3).
#
#   ./make_gif.sh take01.avi out.gif [fps] [scale]
#
# Требует ffmpeg. Проверено на ffmpeg 6.x; флаги стабильны с 4.x.

set -euo pipefail

IN="${1:?укажи входной файл}"
OUT="${2:?укажи выходной .gif}"
FPS="${3:-20}"        # 60 даёт втрое больший вес почти без выигрыша
SCALE="${4:-2}"       # целочисленный множитель: 640x360 -> 1280x720
COLORS="${5:-32}"     # ровно наша палитра

TMP_PALETTE="$(mktemp -t tidebound_palette.XXXXXX).png"
trap 'rm -f "$TMP_PALETTE"' EXIT

# flags=neighbor — это и есть «без сглаживания». Дефолт (bicubic) всё размоет.
FILTERS="fps=${FPS},scale=iw*${SCALE}:ih*${SCALE}:flags=neighbor"

echo "[1/2] палитра (${COLORS} цветов)..."
ffmpeg -v warning -i "$IN" \
  -vf "${FILTERS},palettegen=max_colors=${COLORS}:stats_mode=full" \
  -y "$TMP_PALETTE"

echo "[2/2] сборка GIF..."
# dither=none обязателен: дизеринг подмешает цвета, которых нет в палитре игры.
ffmpeg -v warning -i "$IN" -i "$TMP_PALETTE" \
  -lavfi "${FILTERS} [x]; [x][1:v] paletteuse=dither=none" \
  -y "$OUT"

SIZE_KB=$(( $(wc -c < "$OUT") / 1024 ))
echo "готово: $OUT — ${SIZE_KB} КБ, ${FPS} fps, x${SCALE}"

# Ориентиры веса (research/34 §4.2):
#   itch.io на странице  < 3000 КБ
#   Discord без буста    < 8000 КБ
#   Steam-анонс          < 5000 КБ
[ "$SIZE_KB" -gt 8000 ] && echo "⚠️  тяжело: уменьши fps, длительность или scale" || true
