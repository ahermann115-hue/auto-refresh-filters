#!/bin/bash
set -e

echo "=== ГЕНЕРАЦИЯ BLACKLIST ==="

# 1. Скачиваем сырой список
echo "📥 Загружаем OISD..."
curl -s "https://nsfw.oisd.nl" -o raw.txt

# 2. Очищаем формат
echo "🧹 Очищаем формат..."
cat raw.txt | \
    sed -E 's/^(\|\||\|)//' | \
    sed -E 's/(\^|\^.*)$//' | \
    sed -E 's/^(http:\/\/|https:\/\/|\*\.|\.)//' | \
    grep -E '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | \
    sort -u > domains.txt

count=$(wc -l < domains.txt)
echo "   Найдено доменов: $count"

# 3. Применяем whitelist
echo "🔍 Фильтруем whitelist..."
cat > whitelist.txt << EOF
autorefresh.se
EOF

grep -v -F -f whitelist.txt domains.txt > filtered.txt
filtered_count=$(wc -l < filtered.txt)
echo "   После whitelist: $filtered_count"

# 4. Создаем текстовый файл с заголовком
echo "# Автообновляемый blacklist" > blacklist.txt
echo "# Создано: $(date '+%Y-%m-%d %H:%M:%S')" >> blacklist.txt
echo "# Источник: https://nsfw.oisd.nl" >> blacklist.txt
echo "" >> blacklist.txt
cat filtered.txt >> blacklist.txt

final_txt_count=$(grep -c '^[^#]' blacklist.txt)
echo "✅ Текстовый файл готов: $final_txt_count доменов"

# 5. СОЗДАЕМ БИНАРНЫЙ ФАЙЛ
echo "🔄 Создаем бинарный файл..."

# Используем Python для создания бинарного формата
python3 << 'PYTHON_SCRIPT'
import struct
import sys

def create_binary_file():
    # Читаем домены из filtered.txt (без комментариев)
    domains = []
    with open('filtered.txt', 'r', encoding='utf-8') as f:
        for line in f:
            domain = line.strip()
            if domain:  # Пропускаем пустые строки
                domains.append(domain)
    
    print(f"📊 Конвертируем {len(domains)} доменов в бинарный формат...")
    
    # Записываем бинарный файл
    with open('blacklist.bin', 'wb') as f:
        # Заголовок: версия формата (1)
        f.write(struct.pack('i', 1))
        
        # Количество доменов
        f.write(struct.pack('i', len(domains)))
        
        # Записываем каждый домен
        for i, domain in enumerate(domains):
            # Кодируем домен в UTF-8
            domain_bytes = domain.encode('utf-8')
            
            # Длина домена (4 байта)
            f.write(struct.pack('i', len(domain_bytes)))
            
            # Сам домен
            f.write(domain_bytes)
            
            # Прогресс для больших файлов
            if (i + 1) % 50000 == 0:
                print(f"   Прогресс: {i + 1}/{len(domains)}")
    
    print(f"✅ Бинарный файл создан успешно")

if __name__ == "__main__":
    try:
        create_binary_file()
    except Exception as e:
        print(f"❌ Ошибка при создании бинарного файла: {e}")
        sys.exit(1)
PYTHON_SCRIPT

# 6. ПРОВЕРЯЕМ РЕЗУЛЬТАТЫ
echo ""
echo "🔍 ПРОВЕРКА СОЗДАННЫХ ФАЙЛОВ:"
echo "=============================="

# Текстовый файл
if [ -f "blacklist.txt" ]; then
    txt_lines=$(grep -c '^[^#]' blacklist.txt)
    txt_size=$(stat -c%s blacklist.txt 2>/dev/null || stat -f%z blacklist.txt)
    echo "📄 blacklist.txt:"
    echo "   • Строк с доменами: $txt_lines"
    echo "   • Размер: $txt_size байт"
else
    echo "❌ blacklist.txt НЕ создан!"
fi

# Бинарный файл
if [ -f "blacklist.bin" ]; then
    bin_size=$(stat -c%s blacklist.bin 2>/dev/null || stat -f%z blacklist.bin)
    
    # Проверяем заголовок бинарного файла
    python3 << 'CHECK_SCRIPT'
import struct
import os

try:
    with open('blacklist.bin', 'rb') as f:
        version = struct.unpack('i', f.read(4))[0]
        count = struct.unpack('i', f.read(4))[0]
        
    print("💾 blacklist.bin:")
    print(f"   • Версия формата: {version}")
    print(f"   • Доменов: {count}")
    print(f"   • Размер: {os.path.getsize('blacklist.bin'):,} байт")
    
    # Проверяем первый домен для примера
    if count > 0:
        with open('blacklist.bin', 'rb') as f:
            f.read(8)  # Пропускаем заголовок
            first_length = struct.unpack('i', f.read(4))[0]
            first_domain = f.read(first_length).decode('utf-8')
            print(f"   • Первый домен: {first_domain}")
            
except Exception as e:
    print(f"❌ Ошибка проверки blacklist.bin: {e}")
CHECK_SCRIPT
else
    echo "❌ blacklist.bin НЕ создан!"
    
    # Создаем простой бинарный файл как заглушку
    echo "🛠️ Создаем тестовый бинарный файл..."
    python3 << 'FALLBACK_SCRIPT'
import struct
test_domains = [
    "doubleclick.net",
    "google-analytics.com",
    "ads.facebook.com"
]
with open('blacklist.bin', 'wb') as f:
    f.write(struct.pack('i', 1))
    f.write(struct.pack('i', len(test_domains)))
    for domain in test_domains:
        data = domain.encode('utf-8')
        f.write(struct.pack('i', len(data)))
        f.write(data)
print("   Создан тестовый файл с 3 доменами")
FALLBACK_SCRIPT
fi

# 7. ОЧИСТКА ВРЕМЕННЫХ ФАЙЛОВ
echo ""
echo "🧹 Очистка временных файлов..."
rm -f raw.txt domains.txt whitelist.txt filtered.txt

echo ""
echo "✅ ВСЕ ФАЙЛЫ СОЗДАНЫ:"
echo "===================="
ls -lh blacklist.*
echo ""
echo "=== ГЕНЕРАЦИЯ ЗАВЕРШЕНА ==="
