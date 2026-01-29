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
echo "🌺 СОЗДАЕМ BLOOM-FILTER..."
echo "=========================="

python3 << 'BLOOM_EOF'
import struct
import math
import sys
import os
from bitarray import bitarray

try:
    import mmh3
    MMH3_AVAILABLE = True
except ImportError:
    print("❌ ОШИБКА: Библиотека mmh3 не установлена!")
    sys.exit(1)

print("=== СОЗДАНИЕ BLOOM-FILTER ===")

# 1. Читаем ВСЕ домены ИЗ filtered_clean.txt (без комментариев)
print("📖 Чтение доменов из filtered_clean.txt...")
with open('filtered_clean.txt', 'r', encoding='utf-8') as f:
    domains = []
    line_count = 0
    for line in f:
        line_count += 1
        domain = line.strip()
        if domain and not domain.startswith('#'):  # Пропускаем комментарии и пустые строки
            domains.append(domain)
    
print(f"📊 Обработано строк: {line_count:,}")
print(f"📊 Валидных доменов: {len(domains):,}")

# 2. Проверка на пустоту
if len(domains) == 0:
    print("❌ ОШИБКА: Нет доменов для обработки!")
    print("Первые 5 строк filtered_clean.txt:")
    with open('filtered_clean.txt', 'r') as f:
        for i in range(5):
            print(f"  {i+1}: {f.readline().strip()}")
    sys.exit(1)

# 3. Параметры Bloom-фильтра
n = len(domains)
false_positive_rate = 0.005  # Более строгая вероятность

m = -int((n * math.log(false_positive_rate)) / (math.log(2) ** 2))
k = int((m / n) * math.log(2))
m = ((m + 7) // 8) * 8

print(f"🔧 Параметры Bloom-фильтра:")
print(f"   • Элементов (n): {n:,}")
print(f"   • Размер битового массива (m): {m:,} бит ({m//8:,} байт)")
print(f"   • Хэш-функций (k): {k}")
print(f"   • Ожидаемые ложные срабатывания: {false_positive_rate*100:.2f}%")

# 4. Создаем и заполняем фильтр
print("\n⚙️  Заполняем Bloom-фильтр...")
bit_array = bitarray(m)
bit_array.setall(0)

processed = 0
for domain in domains:
    for seed in range(k):
        hash_val = mmh3.hash(domain, seed) % m
        bit_array[hash_val] = 1
    
    processed += 1
    if processed % 50000 == 0:
        print(f"   Обработано: {processed:,}/{n:,}")

# 5. Сохраняем в НАШЕМ ФОРМАТЕ
print("\n💾 Сохраняем bloom_filter.bin...")
output_file = 'bloom_filter.bin'
with open(output_file, 'wb') as f:
    f.write(struct.pack('<I', 0x424C4F4D))
    f.write(struct.pack('<I', 1))
    f.write(struct.pack('<I', m))
    f.write(struct.pack('<I', k))
    f.write(struct.pack('<I', n))
    bit_array.tofile(f)

# 6. Проверяем созданный файл
file_size = os.path.getsize(output_file)
print(f"\n✅ Bloom-фильтр создан!")
print(f"📏 Размер файла: {file_size:,} байт ({file_size/1024/1024:.2f} MB)")

# 7. Тестовые проверки фильтра
print("\n🔍 Тестовые проверки фильтра:")
test_domains = [
    "google.com",           # Должно быть разрешено
    "youtube.com",          # Должно быть разрешено
    "example-porn-site.com", # Должно быть заблокировано (если есть в списке)
    "casino-example.com",   # Должно быть заблокировано
    "drugs-example.com",    # Должно быть заблокировано
]

for test_domain in test_domains:
    found = False
    for seed in range(k):
        hash_val = mmh3.hash(test_domain, seed) % m
        if not bit_array[hash_val]:
            break
    else:
        found = True
    
    status = "🟡 ВОЗМОЖНО" if found else "✅ НЕТ"
    print(f"   {status} {test_domain}")

BLOOM_EOF

# 9. УДАЛЯЕМ ВРЕМЕННЫЕ ФАЙЛЫ (кроме нужных)
echo ""
echo "🧹 Очистка временных файлов..."
rm -f raw1.txt raw2.txt raw3_drugs.txt raw4_weapons.txt raw5_violence.txt
rm -f raw_combined.txt whitelist_expanded.txt filtered.txt filtered_clean.txt domains_normalized.txt domains.txt
echo "✅ Временные файлы удалены"

# 10. ФИНАЛЬНАЯ СТАТИСТИКА
echo ""
echo "🎯 ФИНАЛЬНАЯ СТАТИСТИКА:"
echo "========================"
echo "📄 blacklist.txt: $DOMAIN_COUNT доменов"

if [ -f "bloom_filter.bin" ]; then
    bloom_size=$(stat -c%s bloom_filter.bin 2>/dev/null || stat -f%z bloom_filter.bin)
    bloom_size_kb=$((bloom_size / 1024))
    bloom_size_mb=$(echo "scale=2; $bloom_size / 1024 / 1024" | bc)
    
    echo "🌺 bloom_filter.bin:"
    echo "   • Размер: $bloom_size байт ($bloom_size_kb KB, $bloom_size_mb MB)"
    
    # Проверяем заголовок
    python3 << 'FINAL_CHECK'
import struct
try:
    with open('bloom_filter.bin', 'rb') as f:
        header = f.read(20)
        magic, version, m, k, n = struct.unpack('<IIIII', header)
        print(f"   • MAGIC: {'✅ BLOOM' if magic == 0x424C4F4D else '❌ ОШИБКА'}")
        print(f"   • Версия: {version}")
        print(f"   • Размер массива: {m:,} бит ({m//8:,} байт)")
        print(f"   • Хэш-функций: {k}")
        print(f"   • Ожидаемых элементов: {n:,}")
        
        # Читаем все домены для статистики
        with open('blacklist.txt', 'r', encoding='utf-8') as bl:
            domains = [line.strip() for line in bl if line.strip() and not line.startswith('#')]
        
        from collections import defaultdict
        categories = defaultdict(int)
        for domain in domains[:1000]:  # Проверяем первые 1000
            domain_lower = domain.lower()
            if any(word in domain_lower for word in ['porn', 'xxx', 'adult', 'sex']):
                categories['porn'] += 1
            elif any(word in domain_lower for word in ['casino', 'gambl', 'poker', 'bet']):
                categories['gambling'] += 1
            elif any(word in domain_lower for word in ['drug', 'weed', 'cocaine', 'opioid']):
                categories['drugs'] += 1
            elif any(word in domain_lower for word in ['weapon', 'gun', 'rifle', 'ammo']):
                categories['weapons'] += 1
            elif any(word in domain_lower for word in ['violence', 'abuse', 'hurt', 'attack']):
                categories['violence'] += 1
            elif any(word in domain_lower for word in ['malware', 'virus', 'trojan', 'hack']):
                categories['malware'] += 1
        
        print(f"\n📊 Примерное распределение категорий (первые 1000 доменов):")
        for cat, count in categories.items():
            print(f"   • {cat}: {count} доменов")
        
except Exception as e:
    print(f"   ❌ Ошибка проверки: {e}")
FINAL_CHECK
else
    echo "❌ bloom_filter.bin не создан!"
    exit 1
fi

# 11. СОЗДАЕМ/ОБНОВЛЯЕМ README
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

echo ""
echo "✅ СКРИПТ ВЫПОЛНЕН УСПЕШНО!"
echo "🎉 СОЗДАН ПОЛНЫЙ ФИЛЬТР ВСЕХ КАТЕГОРИЙ!"
echo "📦 Итоговые файлы: bloom_filter.bin ($BLOOM_SIZE_KB KB) и blacklist.txt ($DOMAIN_COUNT доменов)"

# В самый конец update.sh добавьте:

echo ""
echo "=== ФИНАЛЬНАЯ ПРОВЕРКА ==="
echo "Время: $(date)"

# Явно проверяем что файлы созданы
echo "🔍 Проверяем созданные файлы:"

if [ -f "bloom_filter.bin" ]; then
    bloom_size=$(stat -c%s bloom_filter.bin)
    echo "✅ bloom_filter.bin: $bloom_size байт"
    if [ "$bloom_size" -lt 1000 ]; then
        echo "❌ ОШИБКА: bloom_filter.bin слишком мал!"
        exit 1
    fi
else
    echo "❌ ОШИБКА: bloom_filter.bin не создан!"
    exit 1
fi

if [ -f "blacklist.txt" ]; then
    domain_count=$(grep -v '^#' blacklist.txt | grep -c '\.')
    echo "✅ blacklist.txt: $domain_count доменов"
else
    echo "❌ ОШИБКА: blacklist.txt не создан!"
    exit 1
fi

if [ -f "README.md" ]; then
    echo "✅ README.md: создан"
else
    echo "❌ ОШИБКА: README.md не создан!"
    exit 1
fi

echo ""
echo "✅ ВСЕ ФАЙЛЫ УСПЕШНО СОЗДАНЫ"
echo "📦 Готово для коммита в GitHub"
