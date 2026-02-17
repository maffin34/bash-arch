#!/bin/bash

# Скрипт автоматической установки Arch Linux v1.4
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

# Проверка Reflector
info "Проверка зеркал Reflector..."
if ! grep -q "^Server" /etc/pacman.d/mirrorlist; then
    warning "Reflector не сгенерировал список зеркал"
    info "Используем зеркала вручную..."
    cat > /etc/pacman.d/mirrorlist << 'EOF'
## Russia
Server = https://mirror.yandex.ru/archlinux/$repo/os/$arch
Server = https://mirrors.powernet.com.ru/archlinux/$repo/os/$arch
## Germany
Server = https://ftp.fau.de/archlinux/$repo/os/$arch
Server = https://mirror.netcologne.de/archlinux/$repo/os/$arch
EOF
else
    info "Reflector успешно сгенерировал зеркала"
fi

# Настройка параллельных загрузок
info "Настройка ParallelDownloads = 15..."
sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 15/' /etc/pacman.conf
grep -q "^ParallelDownloads" /etc/pacman.conf || echo "ParallelDownloads = 15" >> /etc/pacman.conf

# ============ ЗАПРОС ПАРАМЕТРОВ ============
step "Сбор информации для установки"

# Показываем доступные диски
lsblk
echo ""

# Выбор типа установки
echo "Выбор типа установки:"
echo "  1) Полная установка (УДАЛИТ ВСЕ ДАННЫЕ на выбранном диске)"
echo "  2) Dual-boot с Windows (общий EFI раздел)"
echo "  3) Рядом с Windows (отдельный EFI раздел)"
echo ""
read -p "Выберите вариант (1-3): " INSTALL_TYPE

INSTALL_MODE=""
case $INSTALL_TYPE in
    1)
        INSTALL_MODE="full"
        info "Режим: Полная установка"
        ;;
    2)
        INSTALL_MODE="dualboot-shared"
        info "Режим: Dual-boot с общим EFI"
        ;;
    3)
        INSTALL_MODE="dualboot-separate"
        info "Режим: Dual-boot с отдельным EFI"
        ;;
    *)
        error "Неверный выбор режима установки"
        ;;
esac

read -p "Введите диск для установки (например, /dev/sda): " DISK
if [ ! -b "$DISK" ]; then
    error "Диск $DISK не найден"
fi

# Показываем текущую разметку диска
echo ""
info "Текущая разметка диска $DISK:"
lsblk "$DISK"
fdisk -l "$DISK"
echo ""

# Для dual-boot режимов нужна дополнительная информация
if [ "$INSTALL_MODE" = "dualboot-shared" ] || [ "$INSTALL_MODE" = "dualboot-separate" ]; then
    warning "Убедитесь, что вы освободили место для Arch Linux в Windows!"
    warning "Используйте 'Управление дисками' в Windows для сжатия тома"
    echo ""
    read -p "Вы освободили место на диске? (yes/no): " FREED_SPACE
    if [ "$FREED_SPACE" != "yes" ]; then
        error "Сначала освободите место в Windows, затем запустите скрипт снова"
    fi
fi

read -p "Hostname (имя компьютера): " HOSTNAME
read -p "Имя пользователя: " USERNAME
read -sp "Пароль root: " ROOT_PASSWORD
echo
read -sp "Пароль пользователя $USERNAME: " USER_PASSWORD
echo

read -p "Часовой пояс (например, Europe/Moscow): " TIMEZONE

# Размер swap-файла
read -p "Размер swap-файла (например, 4G, 6G, 8G): " SWAP_SIZE

# Выбор драйверов GPU
echo ""
echo "Выбор драйверов видеокарты:"
echo "  1) Драйвера не нужны (виртуальная машина/сервер)"
echo "  2) NVIDIA"
echo "  3) AMD"
echo "  4) Intel"
echo ""
read -p "Выберите вариант (1-4): " GPU_CHOICE

GPU_PACKAGES=""
GPU_NAME="Нет"
INSTALL_YAY=false

case $GPU_CHOICE in
    1)
        GPU_NAME="Не установлены"
        GPU_PACKAGES=""
        ;;
    2)
        echo ""
        echo "Выбор драйверов NVIDIA:"
        echo "  1) nvidia-580xx-dkms (для GTX 900/1000 серии - Maxwell/Pascal) [AUR]"
        echo "  2) nvidia-open-dkms (для GTX 1650+, RTX 20/30/40/50 - Turing и новее)"
        echo ""
        read -p "Выберите вариант (1-2): " NVIDIA_CHOICE
        
        case $NVIDIA_CHOICE in
            1)
                GPU_NAME="NVIDIA 580xx (Maxwell/Pascal)"
                GPU_PACKAGES="nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils nvidia-settings egl-wayland"
                INSTALL_YAY=true
                warning "nvidia-580xx-dkms устанавливается из AUR, потребуется yay"
                ;;
            2)
                GPU_NAME="NVIDIA Open (Turing+)"
                GPU_PACKAGES="nvidia-open-dkms nvidia-utils lib32-nvidia-utils nvidia-settings egl-wayland"
                ;;
            *)
                error "Неверный выбор NVIDIA драйвера"
                ;;
        esac
        ;;
    3)
        GPU_NAME="AMD"
        GPU_PACKAGES="mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon libva-mesa-driver lib32-libva-mesa-driver"
        ;;
    4)
        GPU_NAME="Intel"
        GPU_PACKAGES="mesa lib32-mesa vulkan-intel lib32-vulkan-intel intel-media-driver libva-intel-driver"
        ;;
    *)
        error "Неверный выбор драйвера"
        ;;
esac

# Выбор Desktop Environment
echo ""
echo "Выбор рабочего окружения:"
echo "  1) Не нужно (минимальная установка)"
echo "  2) KDE Plasma"
echo "  3) Hyprland"
echo "  4) Niri"
echo ""
read -p "Выберите вариант (1-4): " DE_CHOICE

DE_PACKAGES=""
DE_NAME="Нет"

case $DE_CHOICE in
    1)
        DE_NAME="Не установлено"
        DE_PACKAGES=""
        ;;
    2)
        DE_NAME="KDE Plasma"
        DE_PACKAGES="plasma-desktop plasma-workspace kwin systemsettings plasma-nm plasma-pa powerdevil bluedevil kscreen konsole dolphin kate ark spectacle gwenview okular breeze breeze-gtk kdeplasma-addons plasma-wayland-session xwaylandvideobridge"
        ;;
    3)
        DE_NAME="Hyprland"
        DE_PACKAGES="hyprland xdg-desktop-portal-hyprland xwaylandvideobridge kitty dolphin qt5ct qt6ct"
        ;;
    4)
        DE_NAME="Niri"
        DE_PACKAGES="niri xdg-desktop-portal-gnome kitty alacritty fuzzel xwayland-satellite dolphin qt5ct qt6ct"
        ;;
    *)
        error "Неверный выбор окружения"
        ;;
esac

if [ "$INSTALL_MODE" = "full" ]; then
    warning "ВСЕ ДАННЫЕ НА $DISK БУДУТ УДАЛЕНЫ!"
else
    warning "Будут созданы новые разделы на свободном месте диска $DISK"
fi
read -p "Продолжить установку? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    error "Установка отменена"
fi

# ============ ШАГ 3: Разметка диска ============
step "Шаг 3: Разметка диска"

if [ "$INSTALL_MODE" = "full" ]; then
    # ============ РЕЖИМ 1: Полная установка ============
    info "Очистка диска $DISK..."
    wipefs -af "$DISK"
    sgdisk -Z "$DISK"

    info "Создание разделов..."
    # 1: EFI system - 1G
    # 2: Linux filesystem - всё остальное место
    sgdisk -n 1:0:+1G -t 1:ef00 "$DISK"
    sgdisk -n 2:0:0 -t 2:8300 "$DISK"

    # Определение имен разделов
    if [[ "$DISK" =~ "nvme" ]]; then
        PART1="${DISK}p1"
        PART2="${DISK}p2"
    else
        PART1="${DISK}1"
        PART2="${DISK}2"
    fi
    
    EFI_PART="$PART1"
    ROOT_PART="$PART2"
    FORMAT_EFI=true

elif [ "$INSTALL_MODE" = "dualboot-shared" ]; then
    # ============ РЕЖИМ 2: Dual-boot с общим EFI ============
    info "Поиск существующего EFI раздела..."
    
    # Ищем EFI раздел
    EFI_PART=$(lsblk -no PATH,PARTTYPE "$DISK" | grep -i "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" | awk '{print $1}' | head -n1)
    
    if [ -z "$EFI_PART" ]; then
        error "EFI раздел не найден! Убедитесь, что Windows установлен в UEFI режиме."
    fi
    
    info "Найден EFI раздел: $EFI_PART"
    FORMAT_EFI=false
    
    # Показываем свободное место
    info "Свободное место на диске:"
    parted "$DISK" unit GB print free
    echo ""
    
    warning "Создание раздела для Arch Linux на свободном месте..."
    warning "ВАЖНО: Убедитесь, что вводите правильные значения!"
    echo ""
    read -p "Начало раздела в GB (например, 100): " START_GB
    read -p "Размер раздела в GB (например, 50, или 0 для использования всего свободного места): " SIZE_GB
    
    # Создаем раздел
    if [ "$SIZE_GB" = "0" ]; then
        # Используем всё доступное место
        parted "$DISK" mkpart primary ext4 "${START_GB}GB" 100%
    else
        END_GB=$(echo "$START_GB + $SIZE_GB" | bc)
        parted "$DISK" mkpart primary ext4 "${START_GB}GB" "${END_GB}GB"
    fi
    
    # Получаем номер последнего созданного раздела
    PART_NUM=$(parted "$DISK" print | grep "^ " | tail -n1 | awk '{print $1}')
    
    if [[ "$DISK" =~ "nvme" ]]; then
        ROOT_PART="${DISK}p${PART_NUM}"
    else
        ROOT_PART="${DISK}${PART_NUM}"
    fi
    
    info "Создан раздел для Arch: $ROOT_PART"

elif [ "$INSTALL_MODE" = "dualboot-separate" ]; then
    # ============ РЕЖИМ 3: Dual-boot с отдельным EFI ============
    info "Создание отдельных разделов для Arch Linux..."
    
    # Показываем свободное место
    info "Свободное место на диске:"
    parted "$DISK" unit GB print free
    echo ""
    
    warning "Будут созданы 2 раздела: EFI (1GB) и root"
    warning "ВАЖНО: Убедитесь, что вводите правильные значения!"
    echo ""
    read -p "Начало первого раздела в GB (например, 100): " START_GB
    read -p "Размер root раздела в GB (например, 50, или 0 для использования всего свободного места): " SIZE_GB
    
    # Создаем EFI раздел (1GB)
    EFI_END=$(echo "$START_GB + 1" | bc)
    parted "$DISK" mkpart primary fat32 "${START_GB}GB" "${EFI_END}GB"
    parted "$DISK" set $(parted "$DISK" print | grep "^ " | tail -n1 | awk '{print $1}') esp on
    
    # Получаем номер EFI раздела
    EFI_PART_NUM=$(parted "$DISK" print | grep "^ " | tail -n1 | awk '{print $1}')
    
    # Создаем root раздел
    if [ "$SIZE_GB" = "0" ]; then
        parted "$DISK" mkpart primary ext4 "${EFI_END}GB" 100%
    else
        ROOT_END=$(echo "$EFI_END + $SIZE_GB" | bc)
        parted "$DISK" mkpart primary ext4 "${EFI_END}GB" "${ROOT_END}GB"
    fi
    
    # Получаем номер root раздела
    ROOT_PART_NUM=$(parted "$DISK" print | grep "^ " | tail -n1 | awk '{print $1}')
    
    if [[ "$DISK" =~ "nvme" ]]; then
        EFI_PART="${DISK}p${EFI_PART_NUM}"
        ROOT_PART="${DISK}p${ROOT_PART_NUM}"
    else
        EFI_PART="${DISK}${EFI_PART_NUM}"
        ROOT_PART="${DISK}${ROOT_PART_NUM}"
    fi
    
    FORMAT_EFI=true
    info "Создан EFI раздел: $EFI_PART"
    info "Создан root раздел: $ROOT_PART"
fi

info "Разделы созданы:"
lsblk "$DISK"

# ============ ШАГ 4: Форматирование разделов ============
step "Шаг 4: Форматирование разделов"

if [ "$FORMAT_EFI" = true ]; then
    info "Форматирование $EFI_PART в FAT32 (EFI)..."
    mkfs.vfat -F32 "$EFI_PART"
else
    info "Используется существующий EFI раздел $EFI_PART (не форматируется)"
fi

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

# Базовые пакеты
PACSTRAP_PACKAGES="base base-devel linux-zen linux-zen-headers linux-firmware nano vim bash-completion bash grub efibootmgr networkmanager ttf-ubuntu-font-family ttf-hack ttf-dejavu ttf-opensans sddm pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber git wget curl unzip unrar p7zip tar ntfs-3g exfat-utils dosfstools ffmpeg gstreamer gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-libav firefox bluez bluez-utils"

# Для dual-boot добавляем os-prober
if [ "$INSTALL_MODE" = "dualboot-shared" ] || [ "$INSTALL_MODE" = "dualboot-separate" ]; then
    PACSTRAP_PACKAGES="$PACSTRAP_PACKAGES os-prober"
fi

# Добавляем драйверы GPU если они не из AUR
if [ -n "$GPU_PACKAGES" ] && [ "$INSTALL_YAY" = false ]; then
    PACSTRAP_PACKAGES="$PACSTRAP_PACKAGES $GPU_PACKAGES"
fi

# Добавляем DE пакеты
if [ -n "$DE_PACKAGES" ]; then
    PACSTRAP_PACKAGES="$PACSTRAP_PACKAGES $DE_PACKAGES"
fi

pacstrap /mnt $PACSTRAP_PACKAGES

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
systemctl enable bluetooth

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

# Устанавливаем язык системы (всегда en_US.UTF-8)
echo "LANG=en_US.UTF-8" > /etc/locale.conf

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
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Arch

# Убираем параметр quiet из GRUB
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[^"]*"/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3"/' /etc/default/grub

# Для dual-boot включаем os-prober
if [ "$INSTALL_MODE" = "dualboot-shared" ] || [ "$INSTALL_MODE" = "dualboot-separate" ]; then
    echo "Включение os-prober для обнаружения Windows..."
    echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
    
    # Монтируем другие разделы для поиска
    mkdir -p /mnt/windows
    for part in $(lsblk -ln -o PATH,FSTYPE | grep ntfs | awk '{print $1}'); do
        mount "$part" /mnt/windows 2>/dev/null || true
    done
fi

# Генерируем конфигурацию GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Размонтируем временные монтирования
if [ "$INSTALL_MODE" = "dualboot-shared" ] || [ "$INSTALL_MODE" = "dualboot-separate" ]; then
    umount /mnt/windows 2>/dev/null || true
    rmdir /mnt/windows 2>/dev/null || true
fi

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

# Установка yay и драйверов из AUR (если нужно)
if [ "$INSTALL_YAY" = true ]; then
    echo "=============================="
    echo "Установка yay (AUR helper)..."
    echo "=============================="
    
    # Устанавливаем от имени пользователя
    sudo -u $USERNAME bash << 'EOFYAY'
cd /tmp
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
cd ~
EOFYAY
    
    echo "=============================="
    echo "Установка драйверов из AUR..."
    echo "=============================="
    
    # Устанавливаем драйверы через yay
    sudo -u $USERNAME yay -S --noconfirm $GPU_PACKAGES
fi

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
sed -i "s/\$INSTALL_YAY/$INSTALL_YAY/g" /mnt/root/setup-chroot.sh
sed -i "s/\$GPU_PACKAGES/$GPU_PACKAGES/g" /mnt/root/setup-chroot.sh
sed -i "s/\$INSTALL_MODE/$INSTALL_MODE/g" /mnt/root/setup-chroot.sh

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
echo "  • Звук: PipeWire"
echo "  • Bluetooth: bluez"
echo "  • Браузер: Firefox"
echo "  • Мультимедиа: FFmpeg, GStreamer"
echo "  • Драйверы GPU: $GPU_NAME"
echo "  • Рабочее окружение: $DE_NAME"
echo "  • Swap-файл: $SWAP_SIZE"

if [ "$INSTALL_MODE" = "dualboot-shared" ]; then
    echo "  • Режим: Dual-boot с Windows (общий EFI)"
elif [ "$INSTALL_MODE" = "dualboot-separate" ]; then
    echo "  • Режим: Dual-boot с Windows (отдельный EFI)"
else
    echo "  • Режим: Полная установка"
fi

echo
echo -e "${YELLOW}Важная информация:${NC}"
echo "  Hostname: $HOSTNAME"
echo "  Пользователь: $USERNAME"
echo "  Часовой пояс: $TIMEZONE"
echo "  Язык системы: en_US.UTF-8"
echo "  Локали: en_US.UTF-8, ru_RU.UTF-8"
echo "  EFI раздел: $EFI_PART"
echo "  Root раздел: $ROOT_PART"
echo

if [ "$INSTALL_MODE" = "dualboot-shared" ] || [ "$INSTALL_MODE" = "dualboot-separate" ]; then
    echo -e "${GREEN}Dual-boot настроен!${NC}"
    echo "  • При загрузке появится меню GRUB"
    echo "  • Выбирайте Arch Linux или Windows"
    echo "  • Если Windows не отображается в меню:"
    echo "    1. Загрузитесь в Arch"
    echo "    2. Выполните: sudo grub-mkconfig -o /boot/grub/grub.cfg"
    echo
fi

if [ "$DE_NAME" = "Не установлено" ]; then
    echo -e "${GREEN}Следующие шаги:${NC}"
    echo "  1. Извлеките установочный носитель"
    echo "  2. Перезагрузитесь: reboot"
    echo "  3. После входа установите окружение рабочего стола:"
    echo "     sudo pacman -S plasma-desktop kwin (для KDE Plasma)"
    echo "     sudo pacman -S hyprland (для Hyprland)"
    echo "     sudo pacman -S niri (для Niri)"
    echo
else
    echo -e "${GREEN}Система готова к использованию!${NC}"
    echo "  1. Извлеките установочный носитель"
    echo "  2. Перезагрузитесь: reboot"
    echo "  3. Войдите в систему через SDDM"
    echo
    
    if [ "$DE_NAME" = "Hyprland" ]; then
        echo -e "${YELLOW}Примечание для Hyprland:${NC}"
        echo "  • Конфигурация: ~/.config/hypr/hyprland.conf"
        echo "  • Установите дополнительно:"
        echo "    sudo pacman -S wofi waybar dunst (launcher, панель, уведомления)"
        echo "  • Полезные пакеты:"
        echo "    sudo pacman -S swaybg wlogout swaylock (обои, выход, блокировка)"
        echo
    fi
    
    if [ "$DE_NAME" = "Niri" ]; then
        echo -e "${YELLOW}Примечание для Niri:${NC}"
        echo "  • Конфигурация: ~/.config/niri/config.kdl"
        echo "  • Fuzzel (launcher): Super+D"
        echo "  • Терминал: Super+T"
        echo "  • Полезные пакеты:"
        echo "    sudo pacman -S waybar mako swaybg (панель, уведомления, обои)"
        echo
    fi
fi

echo -e "${BLUE}Для подключения к Wi-Fi после перезагрузки:${NC}"
if [ "$DE_NAME" = "KDE Plasma" ]; then
    echo "  • Используйте системный трей (правый нижний угол)"
elif [ "$DE_NAME" = "Hyprland" ] || [ "$DE_NAME" = "Niri" ]; then
    echo "  • Установите nm-applet: sudo pacman -S network-manager-applet"
    echo "  • Или используйте: nmtui"
else
    echo "  • Используйте: nmtui"
fi
echo

if [[ "$GPU_NAME" == *"NVIDIA"* ]]; then
    echo -e "${YELLOW}Настройка NVIDIA для Wayland:${NC}"
    echo "  После перезагрузки выполните:"
    echo "    echo 'options nvidia_drm modeset=1' | sudo tee /etc/modprobe.d/nvidia.conf"
    echo "    sudo mkinitcpio -P"
    echo "    sudo reboot"
    echo
fi

echo
read -p "Нажмите Enter для перезагрузки..."
reboot
