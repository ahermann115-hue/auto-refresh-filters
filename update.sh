#!/bin/bash
set -e

echo "=== ГЕНЕРАЦИЯ BLACKLIST ==="

# 1. Скачиваем
echo "📥 Загружаем OISD..."
curl -s "https://nsfw.oisd.nl" -o raw.txt

# 2. Очищаем ВСЁ лишнее за один проход
echo "🧹 Очищаем формат..."
# Эта команда убирает ВСЕ префиксы и суффиксы
cat raw.txt | \
    sed -E 's/^(\|\||\|)//' | \
    sed -E 's/(\^|\^.*)$//' | \
    sed -E 's/^(http:\/\/|https:\/\/|\*\.|\.)//' | \
    grep -E '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | \
    sort -u > domains.txt

count=$(wc -l < domains.txt)
echo "   Доменов: $count"

# 3. Whitelist
echo "🔍 Фильтруем whitelist..."
cat > whitelist.txt << EOF
autorefresh.se
EOF

grep -v -F -f whitelist.txt domains.txt > blacklist.txt
final=$(wc -l < blacklist.txt)
echo "✅ Готово: $final доменов"

# 4. Сохраняем
echo "# Создано: $(date)" > header.txt
echo "" >> header.txt
cat header.txt blacklist.txt > final.txt
mv final.txt blacklist.txt

rm -f raw.txt domains.txt whitelist.txt header.txt
echo "=== ФАЙЛ СОЗДАН ==="
