#!/bin/bash
# update.sh - Создаёт blacklist для приложения

echo "=== Генерация blacklist ==="

# 1. Скачиваем OISD
echo "📥 Загружаем OISD..."
curl -s "https://nsfw.oisd.nl" -o oisd_raw.txt

# 2. Очищаем AdBlock формат
echo "🧹 Очищаем формат..."
# Убираем || в начале и ^ в конце
sed -e 's/^\|\|//' -e 's/\^$//' -e 's/^|http:\/\///' -e 's/^|https:\/\///' oisd_raw.txt > oisd_clean.txt

# 3. Убираем мусор
echo "🗑️ Убираем мусор..."
grep -v '^$' oisd_clean.txt | grep -v '^!' | grep -v '^#' | sort | uniq > oisd_domains.txt

# 4. Whitelist (добавь свои сайты)
echo "📝 Добавляем whitelist..."

cat > whitelist.txt << EOF
autorefresh.se
# Добавь сюда свои сайты которые не нужно блокировать
EOF

# 5. Удаляем whitelist из blacklist
echo "🔍 Фильтруем whitelist..."
grep -v -f whitelist.txt oisd_domains.txt > blacklist.txt

# 6. Статистика
count=$(wc -l < blacklist.txt)
echo "✅ Готово: $count доменов в blacklist"

# 7. Очистка временных файлов
rm -f oisd_raw.txt oisd_clean.txt oisd_domains.txt

echo "=== Blacklist создан ==="
