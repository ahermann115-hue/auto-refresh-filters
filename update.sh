#!/bin/bash
set -e

echo "=== ГЕНЕРАЦИЯ BLOOM-FILTER ДЛЯ AUTOREFRESH ==="
echo "🕐 Время: $(date)"
echo "📁 Рабочая директория: $(pwd)"
echo ""

# 0. УСТАНАВЛИВАЕМ ЗАВИСИМОСТИ PYTHON
echo "🐍 Устанавливаем Python зависимости..."
pip install mmh3 bitarray --quiet
echo "✅ Зависимости установлены"

# 1. Скачиваем черный список
echo "📥 Загружаем OISD NSFW список..."
curl -s "https://nsfw.oisd.nl" -o raw.txt
echo "✅ Сырой файл: $(wc -l < raw.txt) строк"

# 2. Сохраняем копию сырого файла для истории
cp raw.txt raw_backup.txt
echo "📁 Сохранена копия: raw_backup.txt"

# 3. Очищаем и форматируем домены
echo "🧹 Очищаем формат..."
cat raw.txt | \
    sed -E 's/^(\|\||\|)//' | \
    sed -E 's/(\^|\^.*)$//' | \
    sed -E 's/^(http:\/\/|https:\/\/|\*\.|\.)//' | \
    grep -E '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | \
    sort -u > domains.txt

echo "✅ Уникальных доменов: $(wc -l < domains.txt)"

# 4. Применяем whitelist (исключения)
echo "🔍 Применяем whitelist..."
cat > whitelist.txt << 'WHITELIST'
autorefresh.se
# Добавь свои исключения ниже:
# example.com
# test.org
WHITELIST

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
    echo "# Источник: https://nsfw.oisd.nl"
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

# Проверяем наличие mmh3
try:
    import mmh3
    MMH3_AVAILABLE = True
except ImportError:
    print("❌ ОШИБКА: Библиотека mmh3 не установлена!")
    print("Установите: pip install mmh3")
    MMH3_AVAILABLE = False

# Фолбэк хэш-функция если mmh3 недоступна
def fallback_hash(data, seed):
    import hashlib
    h = hashlib.md5((str(data) + str(seed)).encode('utf-8')).hexdigest()
    return int(h, 16)

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
n = len(domains)                    # количество элементов
false_positive_rate = 0.01          # 1% ложных срабатываний

# Формулы для оптимального Bloom-фильтра
# m = - (n * ln(p)) / (ln(2)^2)
# k = (m / n) * ln(2)
m = -int((n * math.log(false_positive_rate)) / (math.log(2) ** 2))  # размер в битах
k = int((m / n) * math.log(2))                                     # хэш-функций

# Выравниваем до байта (кратно 8)
m = ((m + 7) // 8) * 8

print(f"🔧 Параметры Bloom-фильтра:")
print(f"   • Элементов (n): {n:,}")
print(f"   • Размер битового массива (m): {m:,} бит ({m//8:,} байт)")
print(f"   • Хэш-функций (k): {k}")
print(f"   • Ожидаемые ложные срабатывания: {false_positive_rate*100:.2f}%")
print(f"   • Теоретический размер: ~{m//8/1024/1024:.2f} MB")

# 3. Создаем и заполняем фильтр
print("\n⚙️  Заполняем Bloom-фильтр...")
bit_array = bitarray(m)
bit_array.setall(0)

processed = 0
for domain in domains:
    for seed in range(k):
        if MMH3_AVAILABLE:
            hash_val = mmh3.hash(domain, seed) % m
        else:
            hash_val = fallback_hash(domain, seed) % m
        bit_array[hash_val] = 1
    
    processed += 1
    if processed % 50000 == 0:
        print(f"   Обработано: {processed:,}/{n:,}")

# Статистика заполненности
ones_count = bit_array.count()
fill_rate = (ones_count / m) * 100
print(f"\n📈 Статистика заполненности:")
print(f"   • Установлено битов: {ones_count:,}")
print(f"   • Всего битов: {m:,}")
print(f"   • Заполненность: {fill_rate:.2f}%")

# Расчет реальной вероятности ложных срабатываний
# p = (1 - e^(-k * n / m)) ^ k
actual_p = math.pow(1 - math.exp(-k * n / m), k)
print(f"   • Реальная вероятность ложных срабатываний: {actual_p*100:.4f}%")

# 4. Сохраняем в НАШЕМ ФОРМАТЕ
print("\n💾 Сохраняем bloom_filter.bin...")
output_file = 'bloom_filter.bin'
with open(output_file, 'wb') as f:
    # ЗАГОЛОВОК (16 байт, little-endian)
    # MAGIC: 'BLOOM' в ASCII (0x42 4C 4F 4D)
    f.write(struct.pack('<I', 0x424C4F4D))  # MAGIC
    f.write(struct.pack('<I', 1))           # VERSION
    f.write(struct.pack('<I', m))           # BIT_ARRAY_SIZE
    f.write(struct.pack('<I', k))           # HASH_FUNCTIONS
    f.write(struct.pack('<I', n))           # EXPECTED_ELEMENTS (дополнительно)
    
    # БИТОВЫЙ МАССИВ
    bit_array.tofile(f)

# 5. Проверяем созданный файл
file_size = os.path.getsize(output_file)
print(f"\n✅ Bloom-фильтр создан!")
print(f"📏 Размер файла: {file_size:,} байт ({file_size/1024/1024:.2f} MB)")
print(f"📐 Ожидаемый размер: {16 + (m+7)//8:,} байт")

# Читаем заголовок для проверки
with open(output_file, 'rb') as f:
    magic, version, m_check, k_check, n_check = struct.unpack('<IIIII', f.read(20))
    
    print(f"\n🔬 ПРОВЕРКА ЗАГОЛОВКА:")
    magic_hex = hex(magic)
    magic_ascii = ''.join(chr((magic >> (8*i)) & 0xFF) for i in range(4))
    
    print(f"   • MAGIC: {magic_hex} ('{magic_ascii[::-1]}')")
    if magic == 0x424C4F4D:
        print("      ✅ КОРРЕКТНЫЙ ФОРМАТ BLOOM-FILTER")
    else:
        print(f"      ❌ ОШИБКА: Ожидалось 0x424C4F4D ('BLOOM')")
    
    print(f"   • VERSION: {version}")
    print(f"   • BIT_ARRAY_SIZE: {m_check:,} бит")
    print(f"   • HASH_FUNCTIONS: {k_check}")
    print(f"   • EXPECTED_ELEMENTS: {n_check:,}")
    
    # Проверяем соответствие
    if m != m_check or k != k_check or n != n_check:
        print("\n⚠️  ПРЕДУПРЕЖДЕНИЕ: Параметры не совпадают!")
        print(f"   Ожидалось: m={m}, k={k}, n={n}")
        print(f"   В файле:   m={m_check}, k={k_check}, n={n_check}")
    
    # Проверяем размер данных
    f.seek(0, 2)  # В конец файла
    total_size = f.tell()
    data_size = total_size - 20  # минус заголовок
    expected_data_size = (m + 7) // 8
    
    print(f"\n📐 ПРОВЕРКА РАЗМЕРОВ:")
    print(f"   • Общий размер файла: {total_size:,} байт")
    print(f"   • Размер данных (битовый массив): {data_size:,} байт")
    print(f"   • Ожидаемый размер данных: {expected_data_size:,} байт")
    
    if data_size == expected_data_size:
        print("      ✅ Размер данных корректен")
    else:
        print(f"      ❌ ОШИБКА: Несоответствие размера данных!")

BLOOM_EOF

# 8. УДАЛЯЕМ СТАРЫЙ ФОРМАТ И ВРЕМЕННЫЕ ФАЙЛЫ
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
    echo "   • Сжатие: $((100 - bloom_size * 100 / 6514126))% от старого формата"
    
    # Проверяем заголовок через Python
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
        
        # Читаем немного данных для проверки
        f.seek(20)
        first_bytes = f.read(32)
        ones_in_first_bytes = sum(bin(b).count('1') for b in first_bytes)
        print(f"   • Битов установлено в первых 32 байтах: {ones_in_first_bytes}")
        
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
cat > README.md << 'README'
# AutoRefresh Filters

Этот репозиторий содержит фильтры для блокировки нежелательного контента в приложении AutoRefresh.

## Файлы

### Основные файлы:
- `bloom_filter.bin` - **ОСНОВНОЙ ФИЛЬТР** в формате Bloom-filter
- `blacklist.txt` - Текстовый список доменов (для справки)

### Формат bloom_filter.bin:
