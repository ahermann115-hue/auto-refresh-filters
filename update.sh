#!/bin/bash
set -e

echo "=== ГЕНЕРАЦИЯ BLACKLIST ==="

# 1. Скачиваем
echo "📥 Загружаем OISD..."
curl -s "https://nsfw.oisd.nl" -o raw.txt

# 2. Очищаем ВСЁ лишнее за один проход
echo "🧹 Очищаем формат..."
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
echo "✅ Текстовый готов: $final доменов"

# 4. Сохраняем текстовый
echo "# Создано: $(date)" > header.txt
echo "" >> header.txt
cat header.txt blacklist.txt > final.txt
mv final.txt blacklist.txt

# 5. 🔥 КОНВЕРТАЦИЯ В БИНАРНЫЙ ФОРМАТ
echo "🔄 Конвертируем в бинарный формат..."

# Создаем Python скрипт для конвертации
python3 << 'EOF'
import struct
import sys

# Читаем текстовый файл
with open('blacklist.txt', 'r', encoding='utf-8') as f:
    domains = []
    for line in f:
        line = line.strip()
        # Пропускаем пустые строки и комментарии
        if line and not line.startswith('#'):
            domains.append(line)

print(f"📊 Конвертируем {len(domains)} доменов...")

# Записываем бинарный файл
with open('blacklist.bin', 'wb') as f:
    # Версия формата (1) - 4 байта
    f.write(struct.pack('i', 1))
    # Количество доменов - 4 байта
    f.write(struct.pack('i', len(domains)))
    
    for domain in domains:
        data = domain.encode('utf-8')
        # Длина домена - 4 байта
        f.write(struct.pack('i', len(data)))
        # Сам домен
        f.write(data)

print(f"✅ Бинарный файл создан: {len(domains)} доменов")

# Проверяем
import os
txt_size = os.path.getsize('blacklist.txt')
bin_size = os.path.getsize('blacklist.bin')
print(f"📁 Размеры:")
print(f"   blacklist.txt: {txt_size:,} байт")
print(f"   blacklist.bin: {bin_size:,} байт")
print(f"   Разница: {bin_size - txt_size:,} байт (+{(bin_size/txt_size*100)-100:.1f}%)")
EOF

# Очистка
rm -f raw.txt domains.txt whitelist.txt header.txt
echo "=== ОБА ФАЙЛА СОЗДАНЫ ==="
