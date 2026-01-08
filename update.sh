#!/bin/bash
set -e  # Останавливаемся при ошибке

echo "=== ГЕНЕРАЦИЯ BLACKLIST ==="
echo "Начало: $(date)"
echo "Текущая директория: $(pwd)"

# 1. Скачиваем OISD
echo "📥 Загружаем OISD список..."
curl -s "https://nsfw.oisd.nl" -o oisd_raw.txt || {
    echo "❌ ОШИБКА: Не удалось скачать OISD!"
    exit 1
}

# Проверяем, что файл не пустой
FILE_LINES=$(wc -l < oisd_raw.txt)
echo "   Скачано строк: $FILE_LINES"

if [ "$FILE_LINES" -lt 1000 ]; then
    echo "❌ ОШИБКА: Слишком мало данных (меньше 1000 строк)!"
    echo "   Первые 10 строк файла:"
    head -10 oisd_raw.txt
    exit 1
fi

# 2. Очищаем AdBlock формат
echo "🧹 Очищаем формат AdBlock..."
# Убираем || в начале, ^ в конце, префиксы http://
sed -e 's/^\|\|//' \
    -e 's/\^$//' \
    -e 's/^|http:\/\///' \
    -e 's/^|https:\/\///' \
    oisd_raw.txt > oisd_clean.txt

# 3. Убираем мусор (комментарии, пустые строки)
echo "🗑️ Убираем комментарии и пустые строки..."
grep -v '^$' oisd_clean.txt | \
    grep -v '^!' | \
    grep -v '^#' | \
    sort | \
    uniq > oisd_domains.txt

DOMAIN_COUNT=$(wc -l < oisd_domains.txt)
echo "   Уникальных доменов: $DOMAIN_COUNT"

# 4. Показываем примеры
echo "   Примеры доменов (первые 5):"
head -5 oisd_domains.txt

# 5. Создаём WHITELIST
echo "📝 Создаём whitelist..."
cat > whitelist.txt << 'EOF'
autorefresh.se
# Добавь сюда свои сайты которые не нужно блокировать
# Каждый домен на новой строке, без http://
# example.com
# google.com

# ЗАГЛУШКА (удали когда добавишь свои сайты):
# this-domain-does-not-exist-12345.com
EOF

# 6. Очищаем whitelist от комментариев
echo "🔍 Подготавливаем whitelist..."
grep -v '^#' whitelist.txt | grep -v '^$' > clean_whitelist.txt

WHITELIST_COUNT=$(wc -l < clean_whitelist.txt)
echo "   Доменов в whitelist: $WHITELIST_COUNT"

if [ "$WHITELIST_COUNT" -eq 0 ]; then
    echo "   ⚠️ Whitelist пуст, создаю blacklist БЕЗ фильтрации"
    cp oisd_domains.txt blacklist.txt
else
    echo "   Фильтрую через whitelist..."
    grep -v -F -f clean_whitelist.txt oisd_domains.txt > blacklist.txt
    FILTERED_COUNT=$((DOMAIN_COUNT - $(wc -l < blacklist.txt)))
    echo "   Исключено доменов: $FILTERED_COUNT"
fi

# 7. Статистика
FINAL_COUNT=$(wc -l < blacklist.txt)
echo "✅ Готово: $FINAL_COUNT доменов в blacklist"

# 8. Проверяем результат
if [ "$FINAL_COUNT" -eq 0 ]; then
    echo "❌ КРИТИЧЕСКАЯ ОШИБКА: blacklist пуст!"
    echo "   Отладка:"
    echo "   - OISD исходных строк: $FILE_LINES"
    echo "   - Уникальных доменов: $DOMAIN_COUNT"
    echo "   - Строк в whitelist: $WHITELIST_COUNT"
    echo "   Проверка whitelist:"
    cat clean_whitelist.txt
    exit 1
elif [ "$FINAL_COUNT" -lt 1000 ]; then
    echo "⚠️  ВНИМАНИЕ: Мало доменов ($FINAL_COUNT), возможно проблема с фильтрацией"
else
    echo "   Первые 3 домена в blacklist:"
    head -3 blacklist.txt | sed 's/^/   /'
fi

# 9. Создаём финальный blacklist с заголовком
echo "📄 Создаю финальный файл..."
{
    echo "# Adblock фильтр"
    echo "# Создан: $(date)"
    echo "# Источник: https://nsfw.oisd.nl"
    echo "# Whitelist: $WHITELIST_COUNT доменов"
    echo "# Всего доменов: $FINAL_COUNT"
    echo ""
    # Добавляем префиксы AdBlock
    sed 's/^/||/' blacklist.txt | sed 's/$/^/'
} > final_blacklist.txt

mv final_blacklist.txt blacklist.txt

echo "   Финальный размер: $(wc -l < blacklist.txt) строк"
echo "   Первая строка: $(head -1 blacklist.txt)"

# 10. Очистка временных файлов
echo "🧹 Убираю временные файлы..."
rm -f oisd_raw.txt oisd_clean.txt oisd_domains.txt clean_whitelist.txt

echo "=== BLACKLIST УСПЕШНО СОЗДАН! ==="
echo "📁 Файл: blacklist.txt ($FINAL_COUNT доменов)"
echo "🕒 Завершено: $(date)"
