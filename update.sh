#!/bin/bash
set -e

echo "=== ГЕНЕРАЦИЯ BLOOM-FILTER ДЛЯ AUTOREFRESH ==="
echo "🕐 Время: $(date)"
echo "📁 Рабочая директория: $(pwd)"
echo ""

# 0. УСТАНАВЛИВАЕМ ЗАВИСИМОСТИ PYTHON
echo "🐍 Устанавливаем Python зависимости..."
pip install mmh3 bitarray --quiet 2>/dev/null || true
echo "✅ Зависимости установлены"

# 1. Скачиваем черный список
echo "📥 Загружаем OISD NSFW список..."
curl -s "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling-porn-social/hosts" -o raw.txt
echo "✅ Сырой файл: $(wc -l < raw.txt) строк"

# 2. Сохраняем копию сырого файла для истории
cp raw.txt raw_backup.txt
echo "📁 Сохранена копия: raw_backup.txt"

# 3. Очищаем и форматируем домены
echo "🧹 Очищаем формат hosts файла..."
cat raw.txt | \
    grep -E '^(0\.0\.0\.0|127\.0\.0\.1)\s+' | \  # Только строки с блокировкой
    sed -E 's/^(0\.0\.0\.0|127\.0\.0\.1)\s+//' | \  # Удаляем IP адрес
    sed -E 's/\s+#.*$//' | \  # Удаляем комментарии в конце строки
    sed -E 's/^\*\.//' | \  # Удаляем ведущие "*.", если есть
    grep -v -E '^(localhost|broadcasthost|ip6-|local)$' | \  # Удаляем служебные записи
    grep -E '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | \  # Проверяем валидность домена
    sort -u > domains.txt

# 4. Применяем whitelist (исключения)
echo "🔍 Применяем whitelist..."
cat > whitelist.txt << 'WHITELIST_EOF'
autorefresh.se
WHITELIST_EOF

grep -v -F -f whitelist.txt domains.txt > filtered.txt
echo "✅ После whitelist: $(wc -l < filtered.txt) доменов"

# 5. Показываем примеры для проверки
echo ""
echo "📊 ПЕРВЫЕ 10 ДОМЕНОВ:"
head -10 filtered.txt | cat -n
echo ""
echo "📊 ПОСЛЕДНИЕ 10 ДОМЕНОВ:"
tail -10 filtered.txt | cat -n
echo ""

# 6. Создаем читаемый TXT файл (для справки)
echo "📄 Создаем blacklist.txt..."
{
    echo "# ========================================="
    echo "# AUTOREFRESH BLACKLIST"
    echo "# Создано: $(date)"
    echo "# Источник: https://github.com/StevenBlack/hosts"
    echo "# Доменов: $(wc -l < filtered.txt)"
    echo "# Формат: Bloom-filter .bin"
    echo "# ========================================="
    echo ""
    echo "# Список доменов (для информации):"
    cat filtered.txt
} > blacklist.txt

echo "✅ blacklist.txt создан: $(grep -c '^[^#]' blacklist.txt) доменов"

# 7. СОЗДАЕМ BLOOM-FILTER В НОВОМ ФОРМАТЕ
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

# 1. Читаем ВСЕ домены
print("📖 Чтение доменов...")
with open('filtered.txt', 'r', encoding='utf-8') as f:
    domains = []
    for line in f:
        domain = line.strip()
        if domain and not domain.startswith('#'):
            domains.append(domain)
    
print(f"📊 Всего доменов: {len(domains):,}")

if len(domains) == 0:
    print("❌ ОШИБКА: Нет доменов для обработки!")
    sys.exit(1)

# 2. Параметры Bloom-фильтра
n = len(domains)
false_positive_rate = 0.01

m = -int((n * math.log(false_positive_rate)) / (math.log(2) ** 2))
k = int((m / n) * math.log(2))
m = ((m + 7) // 8) * 8

print(f"🔧 Параметры Bloom-фильтра:")
print(f"   • Элементов (n): {n:,}")
print(f"   • Размер битового массива (m): {m:,} бит ({m//8:,} байт)")
print(f"   • Хэш-функций (k): {k}")
print(f"   • Ожидаемые ложные срабатывания: {false_positive_rate*100:.2f}%")

# 3. Создаем и заполняем фильтр
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

# 4. Сохраняем в НАШЕМ ФОРМАТЕ
print("\n💾 Сохраняем bloom_filter.bin...")
output_file = 'bloom_filter.bin'
with open(output_file, 'wb') as f:
    f.write(struct.pack('<I', 0x424C4F4D))
    f.write(struct.pack('<I', 1))
    f.write(struct.pack('<I', m))
    f.write(struct.pack('<I', k))
    f.write(struct.pack('<I', n))
    bit_array.tofile(f)

# 5. Проверяем созданный файл
file_size = os.path.getsize(output_file)
print(f"\n✅ Bloom-фильтр создан!")
print(f"📏 Размер файла: {file_size:,} байт ({file_size/1024/1024:.2f} MB)")

BLOOM_EOF

# 8. УДАЛЯЕМ ВРЕМЕННЫЕ ФАЙЛЫ
echo ""
echo "🧹 Очистка временных файлов..."
rm -f raw.txt domains.txt whitelist.txt filtered.txt
echo "✅ Временные файлы удалены"

# 9. ФИНАЛЬНАЯ СТАТИСТИКА
echo ""
echo "🎯 ФИНАЛЬНАЯ СТАТИСТИКА:"
echo "========================"
echo "📄 blacklist.txt: $(grep -c '^[^#]' blacklist.txt) доменов"

if [ -f "bloom_filter.bin" ]; then
    bloom_size=$(stat -c%s bloom_filter.bin 2>/dev/null || stat -f%z bloom_filter.bin)
    echo "🌺 bloom_filter.bin:"
    echo "   • Размер: $bloom_size байт ($(($bloom_size / 1024)) KB)"
    
    # Проверяем заголовок
    python3 << 'FINAL_CHECK'
import struct
try:
    with open('bloom_filter.bin', 'rb') as f:
        header = f.read(20)
        magic, version, m, k, n = struct.unpack('<IIIII', header)
        print(f"   • MAGIC: {'✅ BLOOM' if magic == 0x424C4F4D else '❌ ОШИБКА'}")
        print(f"   • Версия: {version}")
        print(f"   • Размер массива: {m:,} бит")
        print(f"   • Хэш-функций: {k}")
        print(f"   • Ожидаемых элементов: {n:,}")
except Exception as e:
    print(f"   ❌ Ошибка проверки: {e}")
FINAL_CHECK
else
    echo "❌ bloom_filter.bin не создан!"
    exit 1
fi

# 10. СОЗДАЕМ README ДЛЯ GITHUB
echo ""
echo "📝 Создаем README.md..."
cat > README.md << 'README_EOF'
# AutoRefresh Filters

Этот репозиторий содержит фильтры для блокировки нежелательного контента в приложении AutoRefresh.

## Файлы

### Основные файлы:
- `bloom_filter.bin` - **ОСНОВНОЙ ФИЛЬТР** в формате Bloom-filter
- `blacklist.txt` - Текстовый список доменов (для справки)

### Формат bloom_filter.bin:
