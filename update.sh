#!/bin/bash
set -e

echo "=== ПОЛНАЯ ГЕНЕРАЦИЯ С ПРОВЕРКОЙ ==="
echo "🕐 Время: $(date)"
echo ""

# 1. Скачиваем
echo "📥 Загружаем OISD..."
curl -s "https://nsfw.oisd.nl" -o raw.txt
echo "✅ Сырой файл: $(wc -l < raw.txt) строк"

# 2. Сохраняем копию сырого файла для сравнения
cp raw.txt raw_backup.txt
echo "📁 Сохранена копия: raw_backup.txt"

# 3. Очищаем
echo "🧹 Очищаем формат..."
cat raw.txt | \
    sed -E 's/^(\|\||\|)//' | \
    sed -E 's/(\^|\^.*)$//' | \
    sed -E 's/^(http:\/\/|https:\/\/|\*\.|\.)//' | \
    grep -E '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | \
    sort -u > domains.txt

echo "✅ Уникальных доменов: $(wc -l < domains.txt)"

# 4. Whitelist
echo "🔍 Применяем whitelist..."
echo "autorefresh.se" > whitelist.txt
grep -v -F -f whitelist.txt domains.txt > filtered.txt

echo "✅ После whitelist: $(wc -l < filtered.txt)"

# 5. Показываем примеры
echo ""
echo "📊 ПЕРВЫЕ 10 ДОМЕНОВ:"
head -10 filtered.txt
echo ""
echo "📊 ПОСЛЕДНИЕ 10 ДОМЕНОВ:"
tail -10 filtered.txt
echo ""

# 6. Создаем TXT файл
echo "📄 Создаем blacklist.txt..."
{
    echo "# Автообновляемый blacklist"
    echo "# Создано: $(date)"
    echo "# Источник: https://nsfw.oisd.nl"
    echo "# Доменов: $(wc -l < filtered.txt)"
    echo ""
    cat filtered.txt
} > blacklist.txt

echo "✅ blacklist.txt: $(grep -c '^[^#]' blacklist.txt) доменов"

# 7. СОЗДАЕМ ПОЛНЫЙ БИНАРНЫЙ ФАЙЛ
echo "💾 Создаем ПОЛНЫЙ blacklist.bin..."

python3 << 'EOF'
import struct
import sys

print("=== КОНВЕРТАЦИЯ В БИНАРНЫЙ ===")

# Читаем ВСЕ домены
with open('filtered.txt', 'r', encoding='utf-8') as f:
    domains = []
    line_count = 0
    for line in f:
        line_count += 1
        domain = line.strip()
        if domain:
            domains.append(domain)
    
    print(f"Прочитано строк: {line_count}")
    print(f"Непустых доменов: {len(domains)}")

if len(domains) == 0:
    print("❌ ОШИБКА: Нет доменов для конвертации!")
    sys.exit(1)

print(f"Конвертируем {len(domains)} доменов...")

# Создаем бинарный файл
with open('blacklist.bin', 'wb') as f:
    # Заголовок
    f.write(struct.pack('<i', 1))  # версия
    f.write(struct.pack('<i', len(domains)))  # количество
    
    # Записываем ВСЕ домены
    written = 0
    for i, domain in enumerate(domains):
        try:
            data = domain.encode('utf-8')
            f.write(struct.pack('<i', len(data)))  # длина
            f.write(data)  # домен
            written += 1
        except Exception as e:
            print(f"Ошибка с доменом {i}: {domain[:50]}... - {e}")
            continue
        
        # Прогресс
        if (i + 1) % 50000 == 0:
            print(f"  Обработано: {i + 1}/{len(domains)}")

print(f"✅ Успешно записано: {written} доменов")

# Проверяем
import os
if os.path.exists('blacklist.bin'):
    bin_size = os.path.getsize('blacklist.bin')
    print(f"📏 Размер .bin файла: {bin_size:,} байт")
    
    # Читаем заголовок для проверки
    with open('blacklist.bin', 'rb') as f:
        version = struct.unpack('<i', f.read(4))[0]
        count = struct.unpack('<i', f.read(4))[0]
        print(f"🔍 Проверка: версия={version}, доменов={count}")
else:
    print("❌ Файл не создан!")
EOF

# 8. ФИНАЛЬНАЯ ПРОВЕРКА
echo ""
echo "🎯 ФИНАЛЬНАЯ СТАТИСТИКА:"
echo "========================"
echo "📄 blacklist.txt: $(grep -c '^[^#]' blacklist.txt) доменов"
if [ -f "blacklist.bin" ]; then
    bin_size=$(stat -c%s blacklist.bin 2>/dev/null || stat -f%z blacklist.bin)
    echo "💾 blacklist.bin: $bin_size байт"
    
    # Быстрая проверка через Python
    python3 << 'CHECK'
import struct
with open('blacklist.bin', 'rb') as f:
    version = struct.unpack('<i', f.read(4))[0]
    count = struct.unpack('<i', f.read(4))[0]
    print(f"   • Версия: {version}")
    print(f"   • Доменов в .bin: {count}")
CHECK
else
    echo "❌ blacklist.bin не создан!"
fi

# 9. Очистка (оставляем raw_backup.txt для анализа)
rm -f raw.txt domains.txt whitelist.txt filtered.txt

echo ""
echo "📁 СОЗДАННЫЕ ФАЙЛЫ:"
ls -lh blacklist.* raw_backup.txt
echo ""
echo "✅ ГЕНЕРАЦИЯ ЗАВЕРШЕНА"
