#!/bin/bash
set -e

echo "=== ГЕНЕРАЦИЯ BLOOM-FILTER ДЛЯ AUTOREFRESH (ПОЛНАЯ ВЕРСИЯ) ==="
echo "📝 Источник 1: StevenBlack/hosts (fakenews-gambling-porn) - без социальных сетей"
echo "📝 Источник 2: StevenBlack/hosts (базовый список) - включает Malware"
echo "📝 Источник 3: BlockList Project - Drugs, Weapons, Violence"
echo "🕐 Время: $(date)"
echo "📁 Рабочая директория: $(pwd)"
echo "🔄 Частота: Ежедневное обновление"
echo ""

# 0. УСТАНАВЛИВАЕМ ЗАВИСИМОСТИ PYTHON
echo "🐍 Проверяем Python зависимости..."
python3 -c "import mmh3, bitarray" 2>/dev/null || {
    echo "Устанавливаем mmh3 и bitarray..."
    pip install mmh3 bitarray --quiet 2>/dev/null || {
        echo "❌ Не удалось установить зависимости"
        exit 1
    }
}
echo "✅ Зависимости установлены"

# 1. Скачиваем ВСЕ списки
echo "📥 Загружаем список 1: Fakenews + Gambling + Porn (без социальных сетей)..."
curl -s "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling-porn/hosts" -o raw1.txt
echo "✅ Файл 1: $(wc -l < raw1.txt) строк"

echo "📥 Загружаем список 2: Базовый список (включает Malware)..."
curl -s "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts" -o raw2.txt
echo "✅ Файл 2: $(wc -l < raw2.txt) строк"

echo "📥 Загружаем список 3: BlockList Project - Наркотики..."
curl -s "https://blocklistproject.github.io/Lists/alt-version/drugs-nl.txt" -o raw3_drugs.txt
echo "✅ Файл 3 (наркотики): $(wc -l < raw3_drugs.txt) строк"

echo "📥 Загружаем список 4: BlockList Project - Оружие..."
curl -s "https://blocklistproject.github.io/Lists/alt-version/weapons-nl.txt" -o raw4_weapons.txt
echo "✅ Файл 4 (оружие): $(wc -l < raw4_weapons.txt) строк"

echo "📥 Загружаем список 5: BlockList Project - Насилие..."
curl -s "https://blocklistproject.github.io/Lists/alt-version/abuse-nl.txt" -o raw5_violence.txt
echo "✅ Файл 5 (насилие): $(wc -l < raw5_violence.txt) строк"

# 2. Объединяем ВСЕ файлы в один
echo "🔄 Объединяем все списки..."
cat raw1.txt raw2.txt raw3_drugs.txt raw4_weapons.txt raw5_violence.txt > raw_combined.txt
echo "✅ Объединенный файл: $(wc -l < raw_combined.txt) строк"

# 3. Сохраняем копии для истории
cp raw1.txt raw1_backup.txt
cp raw2.txt raw2_backup.txt
cp raw3_drugs.txt raw3_backup.txt
cp raw4_weapons.txt raw4_backup.txt
cp raw5_violence.txt raw5_backup.txt
cp raw_combined.txt raw_combined_backup.txt
echo "📁 Сохранены резервные копии всех списков"

# 4. Очищаем и форматируем домены (КОМБИНИРОВАННЫЙ МЕТОД)
echo "🧹 Очищаем формат hosts файла..."

# Метод 1: Для StevenBlack файлов (твой старый код)
echo "🔧 Обрабатываем StevenBlack формат..."
grep '^0\.0\.0\.0[[:space:]]' raw_combined.txt | \
    awk '{
        domain = $2
        sub(/#.*$/, "", domain)
        # Удаляем все "0." в начале
        while (sub(/^0\./, "", domain)) {}
        print domain
    }' | \
    grep '\.' > domains_stevenblack.txt

echo "✅ Доменов из StevenBlack: $(wc -l < domains_stevenblack.txt)"

# Метод 2: Для BlockList файлов
echo "🔧 Обрабатываем BlockList формат..."
# Обрабатываем каждый BlockList файл отдельно
for block_file in raw3_drugs.txt raw4_weapons.txt raw5_violence.txt; do
    if [ -f "$block_file" ]; then
        echo "  Обрабатываем $block_file..."
        cat "$block_file" | \
            grep -v '^#' | \
            grep -v '^$' | \
            awk '{
                # BlockList может быть в двух форматах:
                # 1. domain
                # 2. 0.0.0.0 domain
                if ($1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
                    domain = $2
                } else {
                    domain = $1
                }
                # Очищаем
                sub(/#.*$/, "", domain)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", domain)
                if (domain && domain ~ /\./) {
                    print domain
                }
            }' >> domains_blocklist.txt
    fi
done

if [ -f "domains_blocklist.txt" ]; then
    echo "✅ Доменов из BlockList: $(wc -l < domains_blocklist.txt)"
else
    echo "⚠️  BlockList файлы не найдены"
    touch domains_blocklist.txt
fi

# Объединяем все домены
cat domains_stevenblack.txt domains_blocklist.txt | \
    sort -u | \
    # Фильтруем мусор
    grep -v '^$' | \
    grep -v '^\.' | \
    grep -v '^0\.0\.0\.0$' | \
    grep -v '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | \
    grep '\.' > domains.txt

echo "✅ Уникальных доменов: $(wc -l < domains.txt)"

# Показываем статистику
echo ""
echo "📊 СТАТИСТИКА ОБРАБОТКИ:"
echo "  • StevenBlack: $(wc -l < domains_stevenblack.txt)"
echo "  • BlockList: $(wc -l < domains_blocklist.txt 2>/dev/null || echo 0)"
echo "  • Итого: $(wc -l < domains.txt)"

# Удаляем временные файлы
rm -f domains_stevenblack.txt domains_blocklist.txt

# 5. Нормализуем домены и применяем whitelist
echo "🧹 Нормализуем домены (удаляем начальные www.)..."
sed 's/^www\.//' domains.txt > domains_normalized.txt

echo "🔍 Применяем whitelist..."

# Создаем расширенный whitelist
cat > whitelist_expanded.txt << 'WHITELIST_EXP_EOF'
autorefresh.se
*.autorefresh.se
google.com
*.google.com
www.google.com
*.www.google.com
youtube.com
*.youtube.com
www.youtube.com
*.www.youtube.com
wikipedia.org
*.wikipedia.org
www.wikipedia.org
*.www.wikipedia.org
vk.com
*.vk.com
ok.ru
*.ok.ru
mail.ru
*.mail.ru
apple.com
*.apple.com
www.apple.com
*.www.apple.com
microsoft.com
*.microsoft.com
www.microsoft.com
*.www.microsoft.com
play.google.com
*.play.google.com
github.com
*.github.com
www.github.com
*.www.github.com
stackoverflow.com
*.stackoverflow.com
www.stackoverflow.com
*.www.stackoverflow.com
reddit.com
*.reddit.com
www.reddit.com
*.www.reddit.com
twitter.com
*.twitter.com
www.twitter.com
*.www.twitter.com
facebook.com
*.facebook.com
www.facebook.com
*.www.facebook.com
instagram.com
*.instagram.com
www.instagram.com
*.www.instagram.com
whatsapp.com
*.whatsapp.com
www.whatsapp.com
*.www.whatsapp.com
telegram.org
*.telegram.org
www.telegram.org
*.www.telegram.org
signal.org
*.signal.org
www.signal.org
*.www.signal.org
discord.com
*.discord.com
www.discord.com
*.www.discord.com
slack.com
*.slack.com
www.slack.com
*.www.slack.com
zoom.us
*.zoom.us
www.zoom.us
*.www.zoom.us
meet.google.com
*.meet.google.com
WHITELIST_EXP_EOF

echo "✅ whitelist_expanded.txt создан: $(wc -l < whitelist_expanded.txt) записей"

# Применяем whitelist
echo "🛡️  Применяем whitelist..."
grep -v -F -f whitelist_expanded.txt domains_normalized.txt > filtered.txt

echo "✅ После whitelist: $(wc -l < filtered.txt) доменов"

# 6. Показываем примеры для проверки
echo ""
echo "📊 ПЕРВЫЕ 20 ДОМЕНОВ (примеры блокировки):"
head -20 filtered.txt | cat -n
echo ""
echo "📊 СТАТИСТИКА ПО КАТЕГОРИЯМ:"
echo "Общее количество доменов: $(wc -l < filtered.txt)"
echo ""
echo "🔍 Проверяем наличие ключевых категорий:"
for category in "porn" "casino" "gambl" "drug" "weapon" "gun" "violence" "malware"; do
    count=$(grep -i "$category" filtered.txt | wc -l)
    echo "  • $category: $count доменов"
done

# 7. Создаем ЧИСТЫЙ файл для Bloom filter и blacklist.txt ОТДЕЛЬНО
echo "📄 Создаем файлы..."

# 7a. Создаем чистый файл для Bloom filter
cp filtered.txt filtered_clean.txt
# Удаляем комментарии и пустые строки
sed -i '/^#/d; /^$/d' filtered_clean.txt

# Проверяем что файл не пустой
if [ ! -s "filtered_clean.txt" ]; then
    echo "❌ ОШИБКА: filtered_clean.txt пустой!"
    echo "Проверяем filtered.txt:"
    head -5 filtered.txt
    exit 1
fi

DOMAIN_COUNT=$(wc -l < filtered_clean.txt)
echo "✅ filtered_clean.txt: $DOMAIN_COUNT доменов (для Bloom filter)"

# 7b. blacklist.txt - С комментариями (для людей)
cat > blacklist.txt << HEADER_EOF
# AutoRefresh Content Filter - Complete Blacklist
# Generated: $(date)
# Total domains: $DOMAIN_COUNT
# Sources:
# 1. StevenBlack/hosts (fakenews-gambling-porn)
# 2. StevenBlack/hosts (base with malware)
# 3. BlockList Project - Drugs
# 4. BlockList Project - Weapons
# 5. BlockList Project - Abuse/Violence
#
# Whitelist applied: social networks, essential services
#
# FORMAT: One domain per line
#

HEADER_EOF

cat filtered_clean.txt >> blacklist.txt
echo "✅ blacklist.txt создан с заголовком"

# 8. СОЗДАЕМ BLOOM-FILTER
echo ""
echo "🌺 СОЗДАЕМ BLOOM-FILTER (СИНХРОНИЗИРОВАНО С JAVA)..."
echo "=================================================="

python3 << 'BLOOM_EOF'
import math
import sys
import os
from bitarray import bitarray

try:
    import mmh3
except ImportError:
    print("❌ ОШИБКА: mmh3 не установлена!")
    sys.exit(1)

# 1. Читаем домены
with open('filtered_clean.txt', 'r', encoding='utf-8') as f:
    domains = [line.strip() for line in f if line.strip() and not line.startswith('#')]

n = len(domains)
if n == 0:
    print("❌ ОШИБКА: Список доменов пуст!")
    sys.exit(1)

# 2. Расчет параметров (m и k)
# Используем те же константы, что и в Java для стабильности
false_positive_rate = 0.005
m = -int((n * math.log(false_positive_rate)) / (math.log(2) ** 2))
k = int((m / n) * math.log(2))

# Округляем m до ближайшего байта (кратно 8)
m = ((m + 7) // 8) * 8

print(f"🔧 Параметры: n={n}, m={m} bits ({m//8} bytes), k={k}")

# 3. Создание битового массива
bit_array = bitarray(m)
bit_array.setall(0)

# 4. Заполнение (ВАЖНО: Логика как в Java)
print("⚙️ Заполнение...")
for domain in domains:
    for seed in range(k):
        # mmh3.hash выдает 32-битное знаковое число
        h = mmh3.hash(domain, seed, signed=True)
        # Имитируем (h & 0x7FFFFFFF) % m из Java
        index = (h & 0x7FFFFFFF) % m
        bit_array[index] = 1

# 5. Сохранение (БЕЗ ЗАГОЛОВКА - только сырые байты)
output_file = 'bloom_filter.bin'
with open(output_file, 'wb') as f:
    # Записываем только саму маску битов
    f.write(bit_array.tobytes())

print(f"✅ Файл {output_file} создан. Размер: {os.path.getsize(output_file)} байт")
BLOOM_EOF

# 9. СОЗДАЕМ/ОБНОВЛЯЕМ README
echo ""
echo "📝 Обновляем README.md..."

BLOOM_SIZE=$(stat -c%s bloom_filter.bin 2>/dev/null || stat -f%z bloom_filter.bin)
BLOOM_SIZE_KB=$((BLOOM_SIZE / 1024))
BLOOM_SIZE_MB=$(echo "scale=2; $BLOOM_SIZE / 1024 / 1024" | bc)
CURRENT_DATE=$(date +"%Y-%m-%d %H:%M:%S")

cat > README.md << README_EOF
# AutoRefresh Content Filters

Полная система фильтрации контента для приложения AutoRefresh (рейтинг 13+).

## 📊 СТАТИСТИКА
- **Дата обновления:** $CURRENT_DATE
- **Всего доменов:** $DOMAIN_COUNT
- **Размер Bloom-фильтра:** $BLOOM_SIZE_KB KB ($BLOOM_SIZE_MB MB)
- **Вероятность ложных срабатываний:** 0.5%

## 🎯 БЛОКИРУЕМЫЕ КАТЕГОРИИ
1. **Порно/Adult content** (из StevenBlack)
2. **Азартные игры/Casino** (из StevenBlack)
3. **Фейковые новости** (из StevenBlack)
4. **Вредоносное ПО/Malware** (из StevenBlack)
5. **Наркотики/Drugs** (из BlockList Project)
6. **Оружие/Weapons** (из BlockList Project)
7. **Насилие/Violence** (из BlockList Project)

## ✅ РАЗРЕШЕННЫЕ КАТЕГОРИИ
- Социальные сети (Facebook, Twitter, Instagram, VK, OK)
- Знакомства (без adult-контента)
- Информационные сайты об алкоголе/табаке
- Поисковые системы и почта
- Технологические платформы

## 📁 ФАЙЛЫ
- \`bloom_filter.bin\` - Основной фильтр в формате Bloom
- \`blacklist.txt\` - Текстовый список всех доменов
- \`update.sh\` - Скрипт генерации фильтров

## 🔗 ИСТОЧНИКИ (MIT License)
1. **StevenBlack/hosts** - комбинированный список (fakenews-gambling-porn + base)
2. **BlockList Project** - специализированные списки:
   - Наркотики: \`drugs-nl.txt\`
   - Оружие: \`weapons-nl.txt\`
   - Насилие: \`abuse-nl.txt\`

## 🔧 ТЕХНИЧЕСКИЕ ДЕТАЛИ
- **Алгоритм:** Bloom filter с murmurhash3
- **Хэш-функций:** зависит от количества доменов
- **Формат файла:** собственный бинарный формат
- **Обновление:** автоматическое, ежедневное

## 🚀 ИСПОЛЬЗОВАНИЕ
1. Скопируйте \`bloom_filter.bin\` в assets приложения
2. Используйте BloomFilter класс для проверки URL
3. Интегрируйте с WebViewClient.shouldInterceptRequest()

## 📄 ЛИЦЕНЗИЯ
Данные распространяются под MIT-лицензиями исходных источников.
Код скрипта - MIT License.

---

*Автоматически сгенерировано $CURRENT_DATE*
README_EOF

echo "✅ README.md обновлен"

# 10. ВАЖНОЕ: УДАЛЯЕМ ВСЕ ВРЕМЕННЫЕ ФАЙЛЫ ПЕРЕД ВЫХОДОМ
echo ""
echo "🧹 УДАЛЯЕМ ВСЕ ВРЕМЕННЫЕ ФАЙЛЫ..."
echo "================================="

# Список файлов для удаления
TEMP_FILES="raw1.txt raw2.txt raw3_drugs.txt raw4_weapons.txt raw5_violence.txt
            raw_combined.txt raw1_backup.txt raw2_backup.txt raw3_backup.txt
            raw4_backup.txt raw5_backup.txt raw_combined_backup.txt
            domains.txt domains_normalized.txt whitelist_expanded.txt
            filtered.txt filtered_clean.txt"

for file in $TEMP_FILES; do
    if [ -f "$file" ]; then
        rm -f "$file"
        echo "   Удалён: $file"
    fi
done

echo "✅ Все временные файлы удалены"

# 11. ФИНАЛЬНАЯ ПРОВЕРКА
echo ""
echo "🔍 ФИНАЛЬНАЯ ПРОВЕРКА СОЗДАННЫХ ФАЙЛОВ:"
echo "========================================"

FINAL_FILES=("bloom_filter.bin" "blacklist.txt" "README.md")
ALL_OK=true

for file in "${FINAL_FILES[@]}"; do
    if [ -f "$file" ]; then
        size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file")
        echo "✅ $file: $size байт"
        
        if [ "$size" -eq 0 ]; then
            echo "   ❌ ВНИМАНИЕ: файл пустой!"
            ALL_OK=false
        fi
    else
        echo "❌ $file: НЕ НАЙДЕН!"
        ALL_OK=false
    fi
done

echo ""
if [ "$ALL_OK" = true ]; then
    echo "🎉 СКРИПТ ВЫПОЛНЕН УСПЕШНО!"
    echo "📦 Созданы файлы:"
    echo "   • bloom_filter.bin ($BLOOM_SIZE_KB KB)"
    echo "   • blacklist.txt ($DOMAIN_COUNT доменов)"
    echo "   • README.md (обновлен)"
else
    echo "❌ ОШИБКА: Не все файлы созданы правильно!"
    exit 1
fi
