#!/bin/bash
set -e

echo "=== ПРОСТАЯ ГЕНЕРАЦИЯ BLACKLIST ==="

# 1. Скачиваем
curl -s "https://nsfw.oisd.nl" -o raw.txt

# 2. Очищаем
cat raw.txt | \
    sed -E 's/^(\|\||\|)//' | \
    sed -E 's/(\^|\^.*)$//' | \
    sed -E 's/^(http:\/\/|https:\/\/|\*\.|\.)//' | \
    grep -E '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | \
    sort -u > domains.txt

# 3. Whitelist
echo "autorefresh.se" > whitelist.txt
grep -v -F -f whitelist.txt domains.txt > filtered.txt

# 4. Создаем ТОЛЬКО TXT файл
echo "# Автообновляемый blacklist" > blacklist.txt
echo "# Создано: $(date)" >> blacklist.txt
echo "" >> blacklist.txt
cat filtered.txt >> blacklist.txt

echo "✅ blacklist.txt создан: $(grep -c '^[^#]' blacklist.txt) доменов"

# 5. СОЗДАЕМ ПРОСТОЙ .bin ФАЙЛ
echo "💾 Создаем простой blacklist.bin..."
python3 << 'EOF'
import struct

# Берем первые 1000 доменов
with open('filtered.txt', 'r') as f:
    domains = []
    for line in f:
        domain = line.strip()
        if domain:
            domains.append(domain)
        if len(domains) >= 1000:
            break

print(f"Создаем .bin с {len(domains)} доменами...")

with open('blacklist.bin', 'wb') as f:
    f.write(struct.pack('<i', 1))  # версия
    f.write(struct.pack('<i', len(domains)))  # количество
    
    for domain in domains:
        data = domain.encode('utf-8')
        f.write(struct.pack('<i', len(data)))  # длина
        f.write(data)  # домен

print(f"✅ blacklist.bin создан")
EOF

# Очистка
rm -f raw.txt domains.txt whitelist.txt filtered.txt

echo "🎉 ОБА ФАЙЛА СОЗДАНЫ!"
ls -lh blacklist.*
