#!/bin/bash

# Облегченный скрипт установки Arch Linux с ручной разметкой
# По инструкции из "Дневник UNIX'оида"
# https://t.me/thmUNIX | https://youtube.com/@thmUNIX

set -e  # Остановка при ошибках

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Функции для вывода
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

step() {
    echo -e "\n${BLUE}==== $1 ====${NC}\n"
}

# Проверка Live окружения
if [ ! -f /etc/arch-release ]; then
    error "Скрипт должен запускаться из Arch Linux Live окружения"
fi

if [ "$EUID" -ne 0 ]; then
    error "Скрипт должен запускаться от root"
fi

# ============ ШАГ 1: Подключение к Интернету ============
step "Шаг 1: Проверка подключения к Интернету"

if ping -c 3 archlinux.org &> /dev/null; then
    info "Подключение к Интернету установлено"
else
    warning "Нет подключения к Интернету!"
    echo "Для Ethernet подключение должно работать автоматически"
    echo "Для Wi-Fi используйте команды:"
    echo "  iwctl"
    echo "  station list"
    echo "  station адаптер get-networks"
    echo "  station адаптер connect \"SSID_сети\""
    echo "  quit"
    echo ""
    echo "Если возникла проблема: rfkill unblock all"
    read -p "Нажмите Enter после подключения к сети..."
fi

# ============ ШАГ 2: Настройка пакетного менеджера ============
step "Шаг 2: Настройка пакетного менеджера"

# Настройка параллельных загрузок
info "Настройка ParallelDownloads = 15..."
sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 15/' /etc/pacman.conf
grep -q "^ParallelDownloads" /etc/pacman.conf || echo "ParallelDownloads = 15" >> /etc/pacman.conf

# ============ ЗАПРОС ПАРАМЕТРОВ ============
step "Сбор информации для установки"

# Показываем доступные диски
lsblk
echo ""
read -p "Введите диск для установки (например, /dev/sda): " DISK
if [ ! -b "$DISK" ]; then
    error "Диск $DISK не найден"
fi

read -p "Hostname (имя компьютера): " HOSTNAME
read -p "Имя пользователя: " USERNAME
read -sp "Пароль root: " ROOT_PASSWORD
echo
read -sp "Пароль пользователя $USERNAME: " USER_PASSWORD
echo

read -p "Часовой пояс (например, Europe/Moscow): " TIMEZONE
read -p "Язык системы (например, en_US.UTF-8 или ru_RU.UTF-8): " SYSTEM_LANG

# Размер swap-файла
read -p "Размер swap-файла (например, 4G, 6G, 8G): " SWAP_SIZE

# ============ ШАГ 3: Ручная разметка диска через cfdisk ============
step "Шаг 3: Ручная разметка диска"

echo ""
info "Текущая разметка диска $DISK:"
lsblk "$DISK"
echo ""

echo -e "${YELLOW}============================================${NC}"
echo -e "${YELLOW}  Ручная разметка диска через cfdisk${NC}"
echo -e "${YELLOW}============================================${NC}"
echo ""
echo "Инструкция по разметке:"
echo ""
echo "  1. Создайте EFI раздел (обязательно):"
echo "     → New → размер: 1G"
echo "     → Type → EFI System"
echo ""
echo "  2. Создайте root раздел (обязательно):"
echo "     → New → всё оставшееся место"
echo "     → Type → Linux filesystem"
echo ""
echo "  3. Запишите изменения:"
echo "     → Write → введите 'yes' → Enter"
echo ""
echo "  4. Выйдите из cfdisk:"
echo "     → Quit"
echo ""
warning "ВАЖНО: Запомните имена разделов (например: sda1, sda2)"
echo ""
read -p "Нажмите Enter для запуска cfdisk..."

# Запускаем cfdisk
cfdisk "$DISK"

echo ""
info "Обновлённая разметка диска:"
lsblk "$DISK"
echo ""

# Размонтируем всё что могло автоматически смонтироваться
info "Размонтирование автоматически смонтированных разделов..."
umount -R /mnt 2>/dev/null || true
for part in $(lsblk -ln -o PATH "$DISK" | tail -n +2); do
    umount -f "$part" 2>/dev/null || true
done

# Запрашиваем разделы у пользователя
echo ""
read -p "Введите EFI раздел (например, /dev/sda1): " EFI_PART
if [ ! -b "$EFI_PART" ]; then
    error "Раздел $EFI_PART не найден"
fi

read -p "Введите root раздел (например, /dev/sda2): " ROOT_PART
if [ ! -b "$ROOT_PART" ]; then
    error "Раздел $ROOT_PART не найден"
fi

# Проверяем что разделы разные
if [ "$EFI_PART" = "$ROOT_PART" ]; then
    error "EFI и root разделы не могут быть одинаковыми!"
fi

echo ""
echo -e "${YELLOW}Проверьте выбранные разделы:${NC}"
echo "  EFI раздел:  $EFI_PART"
echo "  Root раздел: $ROOT_PART"
echo ""
warning "ВСЕ ДАННЫЕ НА ЭТИХ РАЗДЕЛАХ БУДУТ УДАЛЕНЫ!"
read -p "Всё верно? Продолжить? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    error "Установка отменена"
fi

# ============ ШАГ 4: Форматирование разделов ============
step "Шаг 4: Форматирование разделов"

info "Форматирование $EFI_PART в FAT32 (EFI)..."
mkfs.fat -F32 "$EFI_PART"

info "Форматирование $ROOT_PART в ext4 (root)..."
mkfs.ext4 -F "$ROOT_PART"

# ============ ШАГ 5: Монтирование разделов ============
step "Шаг 5: Монтирование разделов"

info "Монтирование корневого раздела..."
mount "$ROOT_PART" /mnt

info "Создание и монтирование /boot/efi..."
mkdir -p /mnt/boot/efi
mount "$EFI_PART" /mnt/boot/efi

info "Разделы смонтированы:"
lsblk "$DISK"

# ============ ШАГ 6: Установка пакетов ============
step "Шаг 6: Установка пакетов"

info "Установка базовой системы с ядром zen и необходимыми пакетами..."
info "Это может занять некоторое время..."

pacstrap /mnt \
    base \
    base-devel \
    linux-zen \
    linux-zen-headers \
    linux-firmware \
    nano \
    vim \
    bash-completion \
    grub \
    efibootmgr \
    networkmanager \
    ttf-ubuntu-font-family \
    ttf-hack \
    ttf-dejavu \
    ttf-opensans \
    ttf-liberation \
    ttf-roboto \
    noto-fonts \
    noto-fonts-emoji \
    sddm \
    pipewire \
    pipewire-alsa \
    pipewire-pulse \
    pipewire-jack \
    wireplumber \
    unzip \
    unrar \
    p7zip \
    ntfs-3g \
    firefox \
    git \
    curl \
    wget

info "Пакеты успешно установлены"

# ============ ШАГ 7: Генерация fstab ============
step "Шаг 7: Генерация fstab"

info "Генерация fstab..."
genfstab -U /mnt >> /mnt/etc/fstab
info "fstab сгенерирован"

# ============ ШАГ 8-16: Настройка системы в chroot ============
step "Шаг 8-16: Настройка системы"

info "Создание скрипта настройки для chroot окружения..."

# Создаем скрипт для выполнения в chroot
cat > /mnt/root/setup-chroot.sh << 'EOFCHROOT'
#!/bin/bash
set -e

echo "=============================="
echo "Настройка системы в chroot..."
echo "=============================="

# ШАГ 9: Включение сервисов
echo "[Шаг 9] Включение сервисов..."
systemctl enable NetworkManager
systemctl enable sddm

# ШАГ 10: Пользователи & пароли
echo "[Шаг 10] Создание пользователей и установка паролей..."
useradd -m -G wheel,audio,video,optical,storage $USERNAME
echo "$USERNAME:$USER_PASSWORD" | chpasswd
echo "root:$ROOT_PASSWORD" | chpasswd

# Даем права sudo группе wheel
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

# ШАГ 11: Локали & язык системы
echo "[Шаг 11] Настройка локалей..."

# Раскомментируем нужные локали
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/^#ru_RU.UTF-8 UTF-8/ru_RU.UTF-8 UTF-8/' /etc/locale.gen

# Устанавливаем язык системы
echo "LANG=$SYSTEM_LANG" > /etc/locale.conf

# Генерируем локали
locale-gen

# Настройка hostname и hosts
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF

# ШАГ 12: Установка загрузчика
echo "[Шаг 12] Установка загрузчика GRUB..."
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB

# Убираем параметр quiet из GRUB
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[^"]*"/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3"/' /etc/default/grub

# Генерируем конфигурацию GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# ШАГ 15: Настройка даты & времени
echo "[Шаг 15] Настройка часового пояса и времени..."
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# ШАГ 16: Создание swap-файла
echo "[Шаг 16] Создание swap-файла размером $SWAP_SIZE..."
mkswap -U clear --size $SWAP_SIZE --file /swapfile
chmod 600 /swapfile
swapon /swapfile

# Добавляем swap в fstab
echo "/swapfile	none	swap	defaults	0	0" >> /etc/fstab

echo "=============================="
echo "Настройка системы завершена!"
echo "=============================="
EOFCHROOT

# Передаем переменные в chroot скрипт
sed -i "s/\$USERNAME/$USERNAME/g" /mnt/root/setup-chroot.sh
sed -i "s/\$USER_PASSWORD/$USER_PASSWORD/g" /mnt/root/setup-chroot.sh
sed -i "s/\$ROOT_PASSWORD/$ROOT_PASSWORD/g" /mnt/root/setup-chroot.sh
sed -i "s/\$HOSTNAME/$HOSTNAME/g" /mnt/root/setup-chroot.sh
sed -i "s|\$TIMEZONE|$TIMEZONE|g" /mnt/root/setup-chroot.sh
sed -i "s/\$SWAP_SIZE/$SWAP_SIZE/g" /mnt/root/setup-chroot.sh
sed -i "s/\$SYSTEM_LANG/$SYSTEM_LANG/g" /mnt/root/setup-chroot.sh

chmod +x /mnt/root/setup-chroot.sh

# ШАГ 8: Смена корня системы и выполнение настройки
info "Переход в chroot и настройка системы..."
arch-chroot /mnt /root/setup-chroot.sh
rm /mnt/root/setup-chroot.sh

# ============ ШАГ 13: Перезагрузка в новую систему ============
step "Шаг 13: Завершение установки"

info "Размонтирование разделов..."
umount -R /mnt

echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Установка Arch Linux завершена!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo -e "${BLUE}Установленные компоненты:${NC}"
echo "  • Ядро: linux-zen"
echo "  • Загрузчик: GRUB"
echo "  • Дисплейный менеджер: SDDM"
echo "  • Сеть: NetworkManager"
echo "  • Swap-файл: $SWAP_SIZE"
echo
echo -e "${YELLOW}Важная информация:${NC}"
echo "  Hostname: $HOSTNAME"
echo "  Пользователь: $USERNAME"
echo "  Часовой пояс: $TIMEZONE"
echo "  Язык системы: $SYSTEM_LANG"
echo "  EFI раздел: $EFI_PART"
echo "  Root раздел: $ROOT_PART"
echo
echo -e "${GREEN}Следующие шаги:${NC}"
echo "  1. Извлеките установочный носитель"
echo "  2. Перезагрузитесь: reboot"
echo "  3. После входа установите окружение рабочего стола:"
echo "     sudo pacman -S xorg plasma-desktop kwin"
echo "     (или gnome, xfce4, hyprland и т.д.)"
echo
echo -e "${BLUE}Для подключения к Wi-Fi после перезагрузки:${NC}"
echo "  • В GUI окружения используйте стандартные средства"
echo "  • Или используйте: nmtui"
echo
read -p "Нажмите Enter для перезагрузки..."
reboot
