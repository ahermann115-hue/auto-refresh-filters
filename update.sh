#!/bin/bash
set -e

echo "=== ГЕНЕРАЦИЯ И КОНВЕРТАЦИЯ BLACKLIST ==="
echo "🕐 Время начала: $(date)"

# 1. Проверка окружения
echo "🔧 Проверка Python..."
python3 --version

# 2. Скачиваем
echo "📥 Загружаем OISD..."
curl -s "https://nsfw.oisd.nl" -o raw.txt

# 3. Очищаем
echo "🧹 Очищаем формат..."
grep -E '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' raw.txt | \
    sed 's/^||//; s/^|//; s/\^.*$//; s/^\*\.//; s/^\.//' | \
    sort -u > domains.txt

count=$(wc -l < domains.txt)
echo "   Найдено: $count доменов"

# 4. Whitelist
echo "🔍 Применяем whitelist..."
echo "autorefresh.se" > whitelist.txt
grep -v -F -f whitelist.txt domains.txt > filtered.txt

# 5. Создаем текстовый файл
echo "📄 Создаем blacklist.txt..."
{
    echo "# Автообновляемый blacklist"
    echo "# Создано: $(date '+%Y-%m-%d %H:%M:%S UTC')"
    echo "# Timestamp: $(date +%s)"
    echo "# Источник: https://nsfw.oisd.nl"
    echo ""
    cat filtered.txt
} > blacklist.txt

txt_count=$(grep -c '^[^#]' blacklist.txt)
echo "✅ blacklist.txt: $txt_count доменов"

# 6. СОЗДАЕМ БИНАРНЫЙ ФАЙЛ (ОБЯЗАТЕЛЬНО!)
echo "💾 Создаем blacklist.bin..."

# Простой Python скрипт для создания бинарного файла
python3 << 'EOF'
import struct

print("Чтение доменов...")
with open('filtered.txt', 'r') as f:
    domains = [line.strip() for line in f if line.strip()]

print(f"Конвертация {len(domains)} доменов...")

with open('blacklist.bin', 'wb') as f:
    # Заголовок
    f.write(struct.pack('<i', 1))      # версия
    f.write(struct.pack('<i', len(domains)))  # количество
    
    # Данные
    for i, domain in enumerate(domains):
        data = domain.encode('utf-8')
        f.write(struct.pack('<i', len(data)))  # длина
        f.write(data)                          # домен
        
        if (i + 1) % 50000 == 0:
            print(f"  Обработано: {i + 1}/{len(domains)}")

print(f"✅ Бинарный файл создан: {len(domains)} доменов")
EOF

# 7. ПРОВЕРКА
echo ""
echo "🔍 ПРОВЕРКА ФАЙЛОВ:"
echo "=================="

if [ -f "blacklist.txt" ]; then
    echo "📄 blacklist.txt: $(wc -l < blacklist.txt) строк"
fi

if [ -f "blacklist.bin" ]; then
    bin_size=$(stat -c%s blacklist.bin 2>/dev/null || stat -f%z blacklist.bin)
    echo "💾 blacklist.bin: $bin_size байт"
    
    # Быстрая проверка содержимого
    python3 << 'CHECK'
import struct
with open('blacklist.bin', 'rb') as f:
    version = struct.unpack('<i', f.read(4))[0]
    count = struct.unpack('<i', f.read(4))[0]
    print(f"   • Версия: {version}")
    print(f"   • Доменов: {count}")
    if count > 0:
        first_len = struct.unpack('<i', f.read(4))[0]
        first_domain = f.read(first_len).decode('utf-8')
        print(f"   • Первый домен: {first_domain}")
CHECK
else
    echo "❌ blacklist.bin НЕ создан!"
    # Создаем хотя бы пустой
    python3 << 'EMPTY'
import struct
with open('blacklist.bin', 'wb') as f:
    f.write(struct.pack('<i', 1))
    f.write(struct.pack('<i', 0))
print("Создан пустой blacklist.bin")
EMPTY
fi

# 8. Очистка
echo ""
echo "🧹 Очистка временных файлов..."
rm -f raw.txt domains.txt whitelist.txt filtered.txt

echo ""
echo "✅ ВСЕ ФАЙЛЫ СОЗДАНЫ"
ls -lh blacklist.*
echo ""
echo "=== ЗАВЕРШЕНО: $(date) ==="
