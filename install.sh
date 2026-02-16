#!/bin/bash

# =============================================================
# УСТАНОВЩИК BLACKARCH + HYPRLAND ДЛЯ SOC-АНАЛИТИКА
# Версия: 1.0
# =============================================================

set -e

# --- ЦВЕТА ДЛЯ ВЫВОДА (если gum не установлен) ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- ПРОВЕРКА И УСТАНОВКА GUM ---
if ! command -v gum &> /dev/null; then
    echo -e "${YELLOW}Устанавливаем gum для красивого интерфейса...${NC}"
    pacman -Sy --noconfirm gum
fi

# --- ПРИВЕТСТВИЕ ---
gum style --foreground 212 --border-foreground 196 --border double --align center --width 70 --margin "1 2" --padding "2 4" \
"🛡️  УСТАНОВЩИК BLACKARCH ДЛЯ SOC  🛡️" \
"Специализированное окружение для аналитика SOC" \
"Современный Hyprland + 3000+ инструментов"

# --- ПРОВЕРКА, ЧТО МЫ В ARCH LIVE ---
if ! grep -q "Arch Linux" /etc/os-release 2>/dev/null; then
    gum style --foreground 196 "❌ Этот скрипт должен запускаться из Arch Linux Live среды!"
    exit 1
fi

# =============================================================
# ИНТЕРАКТИВНАЯ КОНФИГУРАЦИЯ
# =============================================================

# 1. Выбор диска
gum style --foreground 99 "💾 Выбери диск для установки (ВНИМАНИЕ: все данные будут стерты!):"
DISK_LIST=$(lsblk -d -n -o NAME,SIZE,TYPE,MODEL | grep "disk")
SELECTED_DISK_LINE=$(gum choose --height=10 <<< "$DISK_LIST")
DISK="/dev/$(echo "$SELECTED_DISK_LINE" | awk '{print $1}')"

if [[ -z "$DISK" ]]; then
    gum style --foreground 196 "❌ Диск не выбран. Выход."
    exit 1
fi

gum style --foreground 196 "⚠️  ВЫБРАН ДИСК: $DISK - ВСЕ ДАННЫЕ БУДУТ УНИЧТОЖЕНЫ!"
if ! gum confirm "Точно продолжаем?"; then
    exit 0
fi

# 2. Имя компьютера
gum style --foreground 99 "🏷️  Введи hostname (например: soc-工作站-01):"
HOSTNAME=$(gum input --placeholder "soc-workstation" --value "soc-workstation")
HOSTNAME=${HOSTNAME:-soc-workstation}

# 3. Имя пользователя
gum style --foreground 99 "👤 Введи имя пользователя:"
USERNAME=$(gum input --placeholder "analyst" --value "analyst")
USERNAME=${USERNAME:-analyst}

# 4. Пароли (с подтверждением)
gum style --foreground 99 "🔑 Пароль для $USERNAME:"
PASSWORD=$(gum input --password)
gum style --foreground 99 "🔑 Подтверди пароль:"
PASSWORD_CONFIRM=$(gum input --password)

if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
    gum style --foreground 196 "❌ Пароли не совпадают. Выход."
    exit 1
fi

gum style --foreground 99 "🔑 Пароль root:"
ROOT_PASSWORD=$(gum input --password)
gum style --foreground 99 "🔑 Подтверди пароль root:"
ROOT_PASSWORD_CONFIRM=$(gum input --password)

if [ "$ROOT_PASSWORD" != "$ROOT_PASSWORD_CONFIRM" ]; then
    gum style --foreground 196 "❌ Пароли не совпадают. Выход."
    exit 1
fi

# 5. Размер swap (с анализом RAM)
RAM_GIB=$(free -g | awk '/^Mem:/{print $2}')
RECOMMENDED_SWAP=$(( RAM_GIB > 16 ? 8 : RAM_GIB > 8 ? 4 : RAM_GIB ))
if [ "$RECOMMENDED_SWAP" -eq 0 ]; then RECOMMENDED_SWAP=2; fi

gum style --foreground 99 "💿 Размер swap в GiB (рекомендуется $RECOMMENDED_SWAP):"
SWAP_SIZE=$(gum input --placeholder "$RECOMMENDED_SWAP" --value "$RECOMMENDED_SWAP")
SWAP_SIZE=${SWAP_SIZE:-$RECOMMENDED_SWAP}

# 6. Видеодрайвер
gum style --foreground 99 "🎮 Выбери графический драйвер:"
GRAPHICS_DRIVER_CHOICE=$(gum choose "Intel (встроенная)" "AMD (Radeon)" "NVIDIA (проприетарный)" "NVIDIA (open kernel)" "VMware/VirtualBox" "Не устанавливать (только базовый)")

GRAPHICS_PACKAGES="mesa"
case "$GRAPHICS_DRIVER_CHOICE" in
    "Intel (встроенная)")
        GRAPHICS_PACKAGES="$GRAPHICS_PACKAGES vulkan-intel intel-media-driver"
        ;;
    "AMD (Radeon)")
        GRAPHICS_PACKAGES="$GRAPHICS_PACKAGES vulkan-radeon xf86-video-amdgpu"
        ;;
    "NVIDIA (проприетарный)")
        GRAPHICS_PACKAGES="$GRAPHICS_PACKAGES nvidia nvidia-utils nvidia-settings"
        NVIDIA_DRIVER="proprietary"
        ;;
    "NVIDIA (open kernel)")
        GRAPHICS_PACKAGES="$GRAPHICS_PACKAGES nvidia-open nvidia-utils nvidia-settings"
        NVIDIA_DRIVER="open"
        ;;
    "VMware/VirtualBox")
        GRAPHICS_PACKAGES="$GRAPHICS_PACKAGES virtualbox-guest-utils xf86-video-vmware"
        ;;
esac

# 7. Выбор набора инструментов BlackArch
gum style --foreground 99 "🛠️  Выбери набор инструментов BlackArch:"

TOOLSET_CHOICE=$(gum choose \
    "1️⃣  Минимальный (только базовые инструменты)" \
    "2️⃣  Стандартный (рекомендуется для SOC)" \
    "3️⃣  Полный (ВСЕ инструменты, >80GB)" \
    "4️⃣  Выборочная установка групп")

case "$TOOLSET_CHOICE" in
    *"Минимальный"*)
        BLACKARCH_GROUPS="blackarch-config-blackarch blackarch-recon"
        ;;
    *"Стандартный"*)
        BLACKARCH_GROUPS="blackarch-config-blackarch blackarch-recon blackarch-scanner blackarch-sniffer \
                          blackarch-forensic blackarch-networking blackarch-webapp blackarch-wordlist"
        ;;
    *"Полный"*)
        BLACKARCH_GROUPS="blackarch"
        ;;
    *"Выборочная"*)
        gum style --foreground 99 "Выбери группы (через пробел):"
        gum style --foreground 214 "Доступные группы:"
        gum style "blackarch-recon - сбор информации"
        gum style "blackarch-scanner - сканирование"
        gum style "blackarch-sniffer - сниффинг"
        gum style "blackarch-forensic - форензика"
        gum style "blackarch-webapp - веб-приложения"
        gum style "blackarch-wireless - Wi-Fi"
        gum style "blackarch-cracker - взлом паролей"
        gum style "blackarch-exploitation - эксплуатация"
        gum style "blackarch-malware - вредоносное ПО"
        gum style "blackarch-wordlist - словари"
        
        BLACKARCH_GROUPS=$(gum input --placeholder "blackarch-recon blackarch-scanner")
        ;;
esac

# 8. Шифрование диска
gum style --foreground 99 "🔐 Включить LUKS шифрование диска? (рекомендуется для безопасности):"
ENCRYPT_DISK=$(gum choose "Да (рекомендуется)" "Нет")

# 9. Подтверждение
gum style --border normal --margin "1" --padding "1" --foreground 212 \
"📋 СВОДКА КОНФИГУРАЦИИ:" \
"Диск:           $DISK (шифрование: $ENCRYPT_DISK)" \
"Hostname:       $HOSTNAME" \
"Пользователь:   $USERNAME" \
"Swap:           ${SWAP_SIZE}G" \
"Драйвер:        $GRAPHICS_DRIVER_CHOICE" \
"Инструменты:    $TOOLSET_CHOICE"

if ! gum confirm "🚀 Начать установку?"; then
    gum style --foreground 196 "❌ Установка отменена."
    exit 0
fi

# =============================================================
# НАЧАЛО УСТАНОВКИ
# =============================================================

gum spin --title "Инициализация..." -- sleep 1

# --- РАЗМЕТКА ДИСКА ---
gum spin --title "Размечаем диск..." -- sleep 1
sgdisk --zap-all "$DISK"
sgdisk --new=1:0:+1G --typecode=1:ef00 --change-name=1:EFI "$DISK"
sgdisk --new=2:0:+${SWAP_SIZE}G --typecode=2:8200 --change-name=2:SWAP "$DISK"
sgdisk --new=3:0:0 --typecode=3:8300 --change-name=3:ROOT "$DISK"

# Определяем имена разделов
PART_EFI="${DISK}1"
PART_SWAP="${DISK}2"
PART_ROOT="${DISK}3"
if [[ "$DISK" == *"nvme"* ]] || [[ "$DISK" == *"mmcblk"* ]]; then
    PART_EFI="${DISK}p1"
    PART_SWAP="${DISK}p2"
    PART_ROOT="${DISK}p3"
fi

# --- ШИФРОВАНИЕ (опционально) ---
if [[ "$ENCRYPT_DISK" == "Да (рекомендуется)" ]]; then
    gum style --foreground 99 "🔐 Настраиваем LUKS шифрование..."
    
    # Запрашиваем пароль для LUKS
    gum style --foreground 99 "Введи пароль для шифрования диска:"
    LUKS_PASSWORD=$(gum input --password)
    gum style --foreground 99 "Подтверди пароль:"
    LUKS_PASSWORD_CONFIRM=$(gum input --password)
    
    if [ "$LUKS_PASSWORD" != "$LUKS_PASSWORD_CONFIRM" ]; then
        gum style --foreground 196 "❌ Пароли не совпадают. Выход."
        exit 1
    fi
    
    # Шифруем корневой раздел
    printf "%s" "$LUKS_PASSWORD" | cryptsetup luksFormat --type luks2 "$PART_ROOT" -
    printf "%s" "$LUKS_PASSWORD" | cryptsetup open "$PART_ROOT" cryptroot -
    
    # Внутри шифрования создаем физический том LVM (для гибкости)
    pvcreate /dev/mapper/cryptroot
    vgcreate vg0 /dev/mapper/cryptroot
    lvcreate -l 100%FREE vg0 -n root
    
    ROOT_FS="/dev/mapper/vg0-root"
else
    ROOT_FS="$PART_ROOT"
fi

# --- ФОРМАТИРОВАНИЕ ---
gum spin --title "Форматируем разделы..." -- sleep 1
mkfs.fat -F32 "$PART_EFI"
mkswap "$PART_SWAP"
swapon "$PART_SWAP"

if [[ "$ENCRYPT_DISK" == "Да (рекомендуется)" ]]; then
    mkfs.ext4 -F "$ROOT_FS"
else
    mkfs.ext4 -F "$ROOT_FS"
fi

# --- МОНТИРОВАНИЕ ---
gum spin --title "Монтируем разделы..." -- sleep 1
umount -R /mnt 2>/dev/null || true
mount "$ROOT_FS" /mnt
mkdir -p /mnt/boot
mount -o fmask=0077,dmask=0077 "$PART_EFI" /mnt/boot

# =============================================================
# УСТАНОВКА БАЗОВОЙ СИСТЕМЫ
# =============================================================

BASE_PACKAGES="base linux linux-firmware base-devel networkmanager sudo vim git \
               nano man-db man-pages texinfo $GRAPHICS_PACKAGES"

gum spin --title "Устанавливаем базовую систему..." -- pacstrap /mnt $BASE_PACKAGES

# Генерация fstab
genfstab -U /mnt >> /mnt/etc/fstab

# =============================================================
# ПЕРВИЧНАЯ НАСТРОЙКА В CHROOT
# =============================================================

gum spin --title "Настраиваем систему..." -- sleep 1

# Предварительные расчеты
if [[ "$ENCRYPT_DISK" == "Да (рекомендуется)" ]]; then
    ROOT_UUID=$(blkid -s UUID -o value "$PART_ROOT")
fi

arch-chroot /mnt /bin/bash <<EOF

# --- ЛОКАЛИЗАЦИЯ ---
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "ru_RU.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "LC_TIME=ru_RU.UTF-8" >> /etc/locale.conf

# --- ХОСТНЕЙМ ---
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts << HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS

# --- ПОЛЬЗОВАТЕЛИ ---
useradd -m -G wheel,audio,video,storage,input,network -s /bin/bash "$USERNAME"
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
echo "Defaults timestamp_timeout=5" >> /etc/sudoers
echo "Defaults logfile=/var/log/sudo.log" >> /etc/sudoers

# --- ЗАГРУЗЧИК (с поддержкой шифрования) ---
bootctl install

if [[ "$ENCRYPT_DISK" == "Да (рекомендуется)" ]]; then
    # Для шифрованного корня нужно добавить хуки в mkinitcpio
    sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block encrypt lvm2 filesystems fsck)/' /etc/mkinitcpio.conf
    mkinitcpio -P
    
    # Настройка загрузчика для шифрованного раздела
    cat > /boot/loader/entries/arch.conf << BOOTENTRY
title   Arch Linux (BlackArch SOC)
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options cryptdevice=UUID=$ROOT_UUID:cryptroot root=/dev/mapper/vg0-root rw quiet
BOOTENTRY
else
    PARTUUID_ROOT=$(blkid -s PARTUUID -o value "$PART_ROOT")
    cat > /boot/loader/entries/arch.conf << BOOTENTRY
title   Arch Linux (BlackArch SOC)
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=PARTUUID=$PARTUUID_ROOT rw quiet
BOOTENTRY
fi

# Конфиг загрузчика
echo "default arch.conf" > /boot/loader/loader.conf
echo "timeout 3" >> /boot/loader/loader.conf
echo "console-mode max" >> /boot/loader/loader.conf

# --- СЕТЬ ---
systemctl enable NetworkManager

# --- НАСТРОЙКА ДЛЯ NVIDIA (Wayland) ---
if [ -n "$NVIDIA_DRIVER" ]; then
    sed -i 's/MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
    mkinitcpio -P
    # Добавляем параметры для загрузчика
    sed -i 's/options.*/& nvidia_drm.modeset=1/' /boot/loader/entries/arch.conf
fi

EOF

# Установка паролей
printf "%s:%s" "root" "$ROOT_PASSWORD" | arch-chroot /mnt chpasswd
printf "%s:%s" "$USERNAME" "$PASSWORD" | arch-chroot /mnt chpasswd

# =============================================================
# ДОБАВЛЕНИЕ BLACKARCH РЕПОЗИТОРИЯ
# =============================================================

gum style --foreground 196 "🖤 Добавляем BlackArch репозиторий..."

arch-chroot /mnt /bin/bash <<EOF

# Включаем multilib (нужен для многих инструментов BlackArch) [citation:6][citation:7]
sed -i '/\[multilib\]/,/Include/ s/^#//' /etc/pacman.conf
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf

# Устанавливаем ключи и добавляем репозиторий BlackArch [citation:3][citation:9]
cd /tmp
curl -O https://blackarch.org/strap.sh

# Проверяем контрольную сумму (важно для безопасности) [citation:9]
EXPECTED_SUM="bbf0a0b838aed0ec05fff2d375dd17591cbdf8aa"
ACTUAL_SUM=\$(sha1sum strap.sh | cut -d' ' -f1)

if [ "\$ACTUAL_SUM" = "\$EXPECTED_SUM" ]; then
    chmod +x strap.sh
    ./strap.sh
else
    echo "❌ Ошибка проверки strap.sh! Прерывание."
    exit 1
fi

# Обновляем ключи [citation:3]
pacman-key --init
pacman-key --populate archlinux blackarch
pacman -Syyu --noconfirm

EOF

# =============================================================
# УСТАНОВКА ИНСТРУМЕНТОВ BLACKARCH
# =============================================================

gum style --foreground 196 "🛠️  Устанавливаем инструменты BlackArch..."

arch-chroot /mnt /bin/bash <<EOF

# Установка выбранных групп инструментов
if [ "$BLACKARCH_GROUPS" = "blackarch" ]; then
    # Полная установка (может занять много времени)
    echo "Устанавливаем ВСЕ инструменты BlackArch... это может занять >1 часа"
    pacman -S --noconfirm --needed blackarch
else
    # Выборочная установка
    for group in $BLACKARCH_GROUPS; do
        echo "Устанавливаем группу: \$group"
        pacman -S --noconfirm --needed \$group
    done
fi

# Устанавливаем дополнительные полезные инструменты для SOC
pacman -S --noconfirm --needed \
    wireshark-qt \
    tcpdump \
    nmap \
    metasploit \
    burpsuite \
    hydra \
    john \
    sqlmap \
    aircrack-ng \
    wireshark-cli \
    exploitdb \
    binwalk \
    foremost \
    volatility \
    yara \
    rkhunter \
    chkrootkit \
    lynis \
    nikto \
    dirb \
    gobuster \
    ffuf

# Добавляем пользователя в группу wireshark
usermod -aG wireshark "$USERNAME"

EOF

# =============================================================
# УСТАНОВКА HYPRLAND И НАСТРОЙКА ОКРУЖЕНИЯ
# =============================================================

gum style --foreground 212 "🎨 Устанавливаем Hyprland и настраиваем рабочее окружение..."

arch-chroot /mnt /bin/bash <<EOF

# Установка Hyprland и компонентов
pacman -S --noconfirm \
    hyprland kitty waybar mako thunar \
    polkit polkit-kde-agent \
    pipewire pipewire-alsa pipewire-pulse wireplumber \
    wl-clipboard grim slurp \
    swww network-manager-applet \
    ttf-jetbrains-mono-nerd noto-fonts-emoji ttf-dejavu \
    brightnessctl playerctl pavucontrol \
    gvfs fuzzel \
    qt6-multimedia qt6-wayland fastfetch \
    power-profiles-daemon sof-firmware alsa-firmware \
    hypridle hyprlock wayland-protocols \
    firefox thunderbird \
    zsh zsh-completions \
    tmux htop btop \
    openssh \
    vim vim-pluginator \
    git-lfs \
    python python-pip python-virtualenv \
    go rust \
    docker docker-compose \
    wireguard-tools openvpn

# Включаем сервисы
systemctl enable NetworkManager
systemctl enable power-profiles-daemon
systemctl enable docker
usermod -aG docker "$USERNAME"

# Установка менеджера входа (greetd)
pacman -S --noconfirm greetd greetd-tuigreet
systemctl enable greetd

cat > /etc/greetd/config.toml << GREETD
[terminal]
vt = 1

[default_session]
command = "Hyprland"
user = "$USERNAME"
GREETD

# =============================================================
# КОНФИГУРАЦИЯ HYPRLAND ДЛЯ SOC
# =============================================================

mkdir -p /home/$USERNAME/.config/hypr
mkdir -p /home/$USERNAME/.config/kitty
mkdir -p /home/$USERNAME/.config/waybar
mkdir -p /home/$USERNAME/.config/mako
mkdir -p /home/$USERNAME/.config/wofi
mkdir -p /home/$USERNAME/Pictures
mkdir -p /home/$USERNAME/Projects/{recon,exploit,forensics,reports}
mkdir -p /home/$USERNAME/Tools

# Скачиваем обои (темные, для работы ночью)
curl -s -L "https://raw.githubusercontent.com/blackarch/blackarch-artwork/master/backgrounds/blackarch-wallpaper-1920x1080.png" \
     -o /home/$USERNAME/Pictures/blackarch-wall.png

# Основной конфиг Hyprland
cat > /home/$USERNAME/.config/hypr/hyprland.conf << 'HYPRLAND'
# =============================================
# HYPRLAND CONFIG FOR SOC ANALYST
# =============================================

# Мониторы (настрой под себя)
monitor=,preferred,auto,1

# Автозапуск
exec-once = waybar &
exec-once = mako &
exec-once = nm-applet --indicator &
exec-once = pipewire &
exec-once = wireplumber &
exec-once = swww init && swww img ~/Pictures/blackarch-wall.png

# Переменные
$mainMod = SUPER
$terminal = kitty
$fileManager = thunar
$menu = wofi --show drun

# Основные бинды
bind = $mainMod, Return, exec, $terminal
bind = $mainMod, Q, killactive,
bind = $mainMod, M, exit,
bind = $mainMod, E, exec, $fileManager
bind = $mainMod, V, togglefloating,
bind = $mainMod, F, fullscreen,
bind = $mainMod, Space, exec, $menu
bind = $mainMod, R, exec, wofi-emoji

# SOC-специфичные бинды
bind = $mainMod SHIFT, N, exec, nmtui
bind = $mainMod SHIFT, W, exec, wireshark
bind = $mainMod SHIFT, M, exec, msfconsole
bind = $mainMod SHIFT, T, exec, $terminal -e "btm"
bind = $mainMod SHIFT, F, exec, thunar ~/Projects
bind = $mainMod SHIFT, R, exec, $terminal -e "sudo rkhunter --check"

# Переключение рабочих столов (9 рабочих столов для разных задач)
bind = $mainMod, 1, workspace, 1
bind = $mainMod, 2, workspace, 2
bind = $mainMod, 3, workspace, 3
bind = $mainMod, 4, workspace, 4
bind = $mainMod, 5, workspace, 5
bind = $mainMod, 6, workspace, 6
bind = $mainMod, 7, workspace, 7
bind = $mainMod, 8, workspace, 8
bind = $mainMod, 9, workspace, 9

bind = $mainMod SHIFT, 1, movetoworkspace, 1
bind = $mainMod SHIFT, 2, movetoworkspace, 2
bind = $mainMod SHIFT, 3, movetoworkspace, 3
bind = $mainMod SHIFT, 4, movetoworkspace, 4
bind = $mainMod SHIFT, 5, movetoworkspace, 5
bind = $mainMod SHIFT, 6, movetoworkspace, 6
bind = $mainMod SHIFT, 7, movetoworkspace, 7
bind = $mainMod SHIFT, 8, movetoworkspace, 8
bind = $mainMod SHIFT, 9, movetoworkspace, 9

# Медиа-клавиши
bindel = ,XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
bindel = ,XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bindl = ,XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
bindel = ,XF86MonBrightnessUp, exec, brightnessctl set +10%
bindel = ,XF86MonBrightnessDown, exec, brightnessctl set 10%-
bindl = ,XF86AudioPlay, exec, playerctl play-pause
bindl = ,XF86AudioNext, exec, playerctl next
bindl = ,XF86AudioPrev, exec, playerctl previous

# Оформление
general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2
    col.active_border = rgba(cc0000ff) rgba(ff4444ff) 45deg
    col.inactive_border = rgba(666666aa)
    layout = dwindle
    cursor_inactive_timeout = 0
}

decoration {
    rounding = 8
    blur = yes
    blur_size = 4
    blur_passes = 2
    drop_shadow = yes
    shadow_range = 4
    shadow_render_power = 3
    col.shadow = rgba(1a1b26ee)
}

# Прозрачность для некоторых окон
windowrulev2 = opacity 0.95 0.95, class:^(kitty)$
windowrulev2 = opacity 0.95 0.95, class:^(thunar)$
windowrulev2 = opacity 0.9 0.9, class:^(firefox)$

# Правила для всплывающих окон
windowrulev2 = float, title:^(Open File)$
windowrulev2 = float, title:^(Save As)$
HYPRLAND

# Конфиг Kitty терминала
cat > /home/$USERNAME/.config/kitty/kitty.conf << KITTY
font_family      JetBrainsMono Nerd Font
font_size        11
background_opacity 0.92
window_padding_width 8
cursor_shape     block
cursor_blink_interval 0
scrollback_lines 10000
tab_bar_style    fade
active_tab_foreground   #cc0000
inactive_tab_foreground #666666

# Цветовая схема для работы (темная, не напрягает глаза)
background #1e1e2e
foreground #cdd6f4
selection_background #585b70
selection_foreground #cdd6f4

# Черный
color0 #45475a
color8 #585b70

# Красный
color1 #f38ba8
color9 #f38ba8

# Зеленый
color2  #a6e3a1
color10 #a6e3a1

# Желтый
color3  #f9e2af
color11 #f9e2af

# Синий
color4  #89b4fa
color12 #89b4fa

# Пурпурный
color5  #cba6f7
color13 #cba6f7

# Голубой
color6  #94e2d5
color14 #94e2d5

# Белый
color7  #bac2de
color15 #a6adc8
KITTY

# Waybar конфиг для SOC
cat > /home/$USERNAME/.config/waybar/config << 'WAYBAR'
{
    "layer": "top",
    "position": "top",
    "height": 30,
    "spacing": 4,
    "modules-left": ["hyprland/workspaces"],
    "modules-center": ["clock"],
    "modules-right": ["cpu", "memory", "network", "pulseaudio", "battery", "tray"],
    
    "hyprland/workspaces": {
        "disable-scroll": true,
        "all-outputs": true,
        "format": "{name}",
        "persistent_workspaces": {
            "1": [], "2": [], "3": [], "4": [], "5": [], "6": [], "7": [], "8": [], "9": []
        }
    },
    
    "clock": {
        "format": "{:%H:%M  %d.%m.%Y}",
        "format-alt": "{:%Y-%m-%d}",
        "tooltip-format": "<tt>{calendar}</tt>",
        "calendar": {
            "mode": "month",
            "on-scroll": 1
        }
    },
    
    "cpu": {
        "format": "CPU {usage}%",
        "tooltip": true,
        "interval": 2
    },
    
    "memory": {
        "format": "RAM {}%",
        "interval": 5
    },
    
    "network": {
        "format-wifi": "📶 {essid}",
        "format-ethernet": "🌐 {ifname}",
        "format-disconnected": "🚫",
        "tooltip-format": "{ifname} ({ipaddr})",
        "interval": 5
    },
    
    "pulseaudio": {
        "format": "{icon} {volume}%",
        "format-muted": "🔇",
        "format-icons": ["🔈", "🔉", "🔊"],
        "on-click": "pavucontrol"
    },
    
    "battery": {
        "format": "{capacity}% {icon}",
        "format-icons": ["", "", "", "", ""],
        "format-charging": "⚡{capacity}%",
        "interval": 30
    }
}
WAYBAR

# Стили Waybar
cat > /home/$USERNAME/.config/waybar/style.css << CSS
* {
    border: none;
    border-radius: 0;
    font-family: "JetBrainsMono Nerd Font";
    font-size: 13px;
    min-height: 0;
}

window#waybar {
    background: rgba(30, 30, 46, 0.8);
    color: #cdd6f4;
}

#workspaces button {
    padding: 0 5px;
    background: transparent;
    color: #cdd6f4;
    border-bottom: 2px solid transparent;
}

#workspaces button.active {
    border-bottom: 2px solid #f38ba8;
    color: #f38ba8;
}

#workspaces button.urgent {
    border-bottom: 2px solid #f9e2af;
    color: #f9e2af;
}

#clock, #cpu, #memory, #network, #pulseaudio, #battery {
    padding: 0 8px;
    margin: 0 2px;
}

#cpu {
    color: #89b4fa;
}

#memory {
    color: #cba6f7;
}

#network {
    color: #a6e3a1;
}

#pulseaudio {
    color: #f9e2af;
}

#battery {
    color: #94e2d5;
}

#battery.warning {
    color: #f9e2af;
}

#battery.critical {
    color: #f38ba8;
}
CSS

# Mako (уведомления)
cat > /home/$USERNAME/.config/mako/config << MAKO
background-color=#1e1e2e
text-color=#cdd6f4
border-color=#f38ba8
border-size=2
border-radius=8
default-timeout=5000
ignore-timeout=0
max-history=50
MAKO

# Wofi (лаунчер)
cat > /
