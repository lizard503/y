#!/bin/bash

# =============================================================
# КАСТОМНЫЙ УСТАНОВЩИК ARCH LINUX + QUICKSHELL
# Базируется на скриптах 2 и 3 из анализа
# Автор: Твой покорный слуга (на основе твоих примеров)
# =============================================================

set -e

# --- ЦВЕТА И СТИЛИ ДЛЯ ВЫВОДА (если gum не установлен) ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Функция для красивых заголовков (если gum нет)
print_header() {
    echo -e "${PURPLE}========================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${PURPLE}========================================${NC}"
}

# --- ПРОВЕРКА И УСТАНОВКА GUM ---
if ! command -v gum &> /dev/null; then
    echo -e "${YELLOW}Устанавливаем gum для красивого интерфейса...${NC}"
    pacman -Sy --noconfirm gum
fi

# --- ИНТЕРАКТИВНАЯ КОНФИГУРАЦИЯ (из Скрипта 2) ---
gum style --foreground 212 --border-foreground 212 --border double --align center --width 60 --margin "1 2" --padding "2 4" "Arch Linux + Quickshell Installer"

# 1. Выбор диска
gum style --foreground 99 "💾 Выбери диск для установки:"
DISK_LIST=$(lsblk -d -n -o NAME,SIZE,TYPE,MODEL | grep "disk")
SELECTED_DISK_LINE=$(gum choose --height=10 <<< "$DISK_LIST")
DISK="/dev/$(echo "$SELECTED_DISK_LINE" | awk '{print $1}')"

if [[ -z "$DISK" ]]; then
    gum style --foreground 196 "❌ Диск не выбран. Выход."
    exit 1
fi
gum style --foreground 46 "✅ Выбран диск: $DISK"

# 2. Имя компьютера
gum style --foreground 99 "🏷️ Введи hostname:"
HOSTNAME=$(gum input --placeholder "my-arch" --value "my-arch")
HOSTNAME=${HOSTNAME:-my-arch}

# 3. Имя пользователя
gum style --foreground 99 "👤 Введи имя пользователя:"
USERNAME=$(gum input --placeholder "user" --value "user")
USERNAME=${USERNAME:-user}

# 4. Пароли
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

# 5. Размер swap
RAM_GIB=$(free -g | awk '/^Mem:/{print $2}')
RECOMMENDED_SWAP=$(( RAM_GIB > 8 ? 4 : RAM_GIB > 4 ? 4 : RAM_GIB ))
if [ "$RECOMMENDED_SWAP" -eq 0 ]; then RECOMMENDED_SWAP=2; fi

gum style --foreground 99 "💿 Размер swap в GiB:"
SWAP_SIZE=$(gum input --placeholder "$RECOMMENDED_SWAP" --value "$RECOMMENDED_SWAP")
SWAP_SIZE=${SWAP_SIZE:-$RECOMMENDED_SWAP}

# 6. Видеодрайвер
gum style --foreground 99 "🎮 Выбери графический драйвер:"
GRAPHICS_DRIVER_CHOICE=$(gum choose "Intel (Arc/Integrated)" "AMD (Radeon)" "Nvidia (Proprietary)" "Nvidia (Open)" "Nvidia (DKMS)" "VM/None (VirtIO/QXL)")

GRAPHICS_PACKAGES="mesa"
case "$GRAPHICS_DRIVER_CHOICE" in
    "Intel (Arc/Integrated)")
        GRAPHICS_PACKAGES="$GRAPHICS_PACKAGES vulkan-intel intel-media-driver"
        ;;
    "AMD (Radeon)")
        GRAPHICS_PACKAGES="$GRAPHICS_PACKAGES vulkan-radeon xf86-video-amdgpu"
        ;;
    "Nvidia (Proprietary)")
        GRAPHICS_PACKAGES="$GRAPHICS_PACKAGES nvidia nvidia-utils nvidia-settings"
        NVIDIA_DRIVER="proprietary"
        ;;
    "Nvidia (Open)")
        GRAPHICS_PACKAGES="$GRAPHICS_PACKAGES nvidia-open nvidia-utils nvidia-settings"
        NVIDIA_DRIVER="open"
        ;;
    "Nvidia (DKMS)")
        GRAPHICS_PACKAGES="$GRAPHICS_PACKAGES nvidia-dkms nvidia-utils nvidia-settings"
        NVIDIA_DRIVER="dkms"
        ;;
    "VM/None (VirtIO/QXL)")
        GRAPHICS_PACKAGES="$GRAPHICS_PACKAGES"
        ;;
esac

# 7. Выбор типа установки
gum style --foreground 99 "🖥️  Выбери тип установки:"
INSTALL_TYPE=$(gum choose "1️⃣  Минимальная (только база)" "2️⃣  Полная (с моим Quickshell шеллом)")

# 8. Подтверждение
gum style --border normal --margin "1" --padding "1" --foreground 212 \
"📋 Сводка конфигурации:" \
"Диск:      $DISK" \
"Hostname:  $HOSTNAME" \
"Username:  $USERNAME" \
"Swap:      ${SWAP_SIZE}G" \
"Драйвер:   $GRAPHICS_DRIVER_CHOICE" \
"Тип:       $INSTALL_TYPE"

if ! gum confirm "Начать установку?"; then
    gum style --foreground 196 "❌ Установка отменена."
    exit 0
fi

# =============================================================
# НАЧАЛО УСТАНОВКИ
# =============================================================

gum style --foreground 212 "▶️ Начинаем установку..."

# --- РАЗМЕТКА ДИСКА ---
gum spin --title "Размечаем диск..." -- sleep 1
sgdisk --zap-all "$DISK"
sgdisk --new=1:0:+1G --typecode=1:ef00 --change-name=1:EFI "$DISK"
sgdisk --new=2:0:+${SWAP_SIZE}G --typecode=2:8200 --change-name=2:SWAP "$DISK"
sgdisk --new=3:0:0 --typecode=3:8300 --change-name=3:ROOT "$DISK"

# Определяем имена разделов (для NVMe особый случай)
PART_EFI="${DISK}1"
PART_SWAP="${DISK}2"
PART_ROOT="${DISK}3"
if [[ "$DISK" == *"nvme"* ]] || [[ "$DISK" == *"mmcblk"* ]]; then
    PART_EFI="${DISK}p1"
    PART_SWAP="${DISK}p2"
    PART_ROOT="${DISK}p3"
fi

# --- ФОРМАТИРОВАНИЕ ---
gum spin --title "Форматируем разделы..." -- sleep 1
mkfs.fat -F32 "$PART_EFI"
mkswap "$PART_SWAP"
swapon "$PART_SWAP"
mkfs.ext4 -F "$PART_ROOT"

# --- МОНТИРОВАНИЕ ---
gum spin --title "Монтируем разделы..." -- sleep 1
umount -R /mnt 2>/dev/null || true
mount "$PART_ROOT" /mnt
mkdir -p /mnt/boot
mount -o fmask=0077,dmask=0077 "$PART_EFI" /mnt/boot

# --- УСТАНОВКА БАЗОВОЙ СИСТЕМЫ ---
BASE_PACKAGES="base linux linux-firmware base-devel networkmanager sudo git vi nano man-db man-pages $GRAPHICS_PACKAGES"
gum spin --title "Устанавливаем базовую систему (это займет некоторое время)..." -- pacstrap /mnt $BASE_PACKAGES

# --- ГЕНЕРАЦИЯ FSTAB ---
genfstab -U /mnt >> /mnt/etc/fstab

# --- ПРЕДВАРИТЕЛЬНЫЕ РАСЧЕТЫ ДЛЯ CHROOT ---
PARTUUID_ROOT=$(blkid -s PARTUUID -o value "$PART_ROOT")

# =============================================================
# CHROOT: НАСТРОЙКА СИСТЕМЫ
# =============================================================
gum spin --title "Настраиваем систему в chroot..." -- sleep 1

arch-chroot /mnt /bin/bash <<EOF

# --- ЛОКАЛИЗАЦИЯ ---
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "LC_COLLATE=C" >> /etc/locale.conf

# --- ХОСТНЕЙМ И ХОСТЫ ---
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts << HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS

# --- ПОЛЬЗОВАТЕЛИ ---
useradd -m -G wheel,audio,video,storage,input -s /bin/bash "$USERNAME"
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
echo "Defaults timestamp_timeout=0" >> /etc/sudoers

# --- ЗАГРУЗЧИК (systemd-boot) ---
bootctl install
echo "default arch.conf" > /boot/loader/loader.conf
echo "timeout 3" >> /boot/loader/loader.conf
echo "console-mode max" >> /boot/loader/loader.conf

cat > /boot/loader/entries/arch.conf << BOOTENTRY
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=PARTUUID=$PARTUUID_ROOT rw quiet
BOOTENTRY

# --- СЕТЬ ---
systemctl enable NetworkManager

# --- НАСТРОЙКА MKINITCPIO ДЛЯ NVIDIA (ЕСЛИ ВЫБРАНО) ---
if [ -n "$NVIDIA_DRIVER" ]; then
    sed -i 's/MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
    mkinitcpio -P
    # Добавляем modeset для Wayland
    sed -i '/options root=/ s/$/ nvidia_drm.modeset=1/' /boot/loader/entries/arch.conf
fi

EOF

# --- УСТАНОВКА ПАРОЛЕЙ (БЕЗОПАСНО) ---
printf "%s:%s" "root" "$ROOT_PASSWORD" | arch-chroot /mnt chpasswd
printf "%s:%s" "$USERNAME" "$PASSWORD" | arch-chroot /mnt chpasswd

# =============================================================
# ПОСТ-УСТАНОВОЧНАЯ НАСТРОЙКА (ЕСЛИ ВЫБРАНА ПОЛНАЯ)
# =============================================================
if [[ "$INSTALL_TYPE" == *"Полная"* ]]; then
    gum style --foreground 212 "🎨 Устанавливаем полное окружение с Quickshell..."
    
    arch-chroot /mnt /bin/bash <<EOF
    
    # --- УСТАНОВКА YAY (AUR Helper) ---
    cd /tmp
    git clone https://aur.archlinux.org/yay-bin.git
    chown -R "$USERNAME":"$USERNAME" yay-bin
    cd yay-bin
    sudo -u "$USERNAME" makepkg -si --noconfirm
    
    # --- УСТАНОВКА НЕОБХОДИМЫХ ПАКЕТОВ (как в Скрипте 3) ---
    pacman -S --noconfirm \
        hyprland kitty waybar mako thunar \
        polkit polkit-kde-agent \
        pipewire pipewire-alsa pipewire-pulse wireplumber \
        wl-clipboard grim slurp \
        swww network-manager-applet \
        ttf-jetbrains-mono-nerd noto-fonts-emoji \
        brightnessctl playerctl pavucontrol \
        gvfs fuzzel \
        qt6-multimedia qt6-wayland fastfetch \
        power-profiles-daemon sof-firmware alsa-firmware \
        hypridle hyprlock wayland-protocols
    
    # --- УСТАНОВКА QUICKSHELL ИЗ AUR ---
    sudo -u "$USERNAME" yay -S --noconfirm quickshell-git
    
    # --- НАСТРОЙКА GREETD (LOGIN MANAGER) ---
    pacman -S --noconfirm greetd greetd-tuigreet
    systemctl enable greetd
    
    # Конфигурация greetd для запуска Hyprland
    cat > /etc/greetd/config.toml << GREETD
[terminal]
vt = 1

[default_session]
command = "Hyprland"
user = "$USERNAME"
GREETD
    
    # =============================================================
    # ТВОЙ КАСТОМНЫЙ QUICKSHELL ШЕЛЛ
    # =============================================================
    
    # Создаем директорию для твоего шелла
    mkdir -p /home/$USERNAME/.config/quickshell
    mkdir -p /home/$USERNAME/.local/share/quickshell
    
    # Создаем базовую структуру QML-проекта
    cat > /home/$USERNAME/.config/quickshell/main.qml << QML
import Quickshell
import Quickshell.Wayland
import QtQuick

Shell {
    id: root
    
    // Настройки монитора
    anchors.fill: true
    
    // Твой кастомный шелл компонент
    Rectangle {
        anchors.fill: parent
        color: "#1a1b26"  // Tokyo Night theme
        
        // Верхняя панель (пример)
        Rectangle {
            id: topBar
            width: parent.width
            height: 40
            color: "#24283b"
            
            // Левый блок - рабочие столы
            Row {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                
                Repeater {
                    model: 5
                    Rectangle {
                        width: 30
                        height: 30
                        radius: 6
                        color: index === 0 ? "#7aa2f7" : "#414868"
                        
                        Text {
                            anchors.centerIn: parent
                            text: index + 1
                            color: "white"
                            font.pointSize: 12
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                // Здесь будет переключение workspace
                                print("Workspace clicked:", index + 1)
                            }
                        }
                    }
                }
            }
            
            // Центр - часы
            Text {
                anchors.centerIn: parent
                text: new Date().toLocaleTimeString(Qt.locale(), "HH:mm")
                color: "white"
                font.pointSize: 14
                font.bold: true
                
                Timer {
                    interval: 1000
                    running: true
                    repeat: true
                    onTriggered: parent.text = new Date().toLocaleTimeString(Qt.locale(), "HH:mm")
                }
            }
            
            // Правый блок - системный трей
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12
                
                // Иконка звука (заглушка)
                Text { text: "🔊"; color: "white"; font.pointSize: 14 }
                
                // Иконка батареи (заглушка)
                Text { text: "🔋"; color: "white"; font.pointSize: 14 }
                
                // Иконка сети (заглушка)
                Text { text: "Wi-Fi"; color: "white"; font.pointSize: 12 }
            }
        }
        
        // Главная область - можно добавить виджеты
        Item {
            anchors.top: topBar.bottom
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            
            // Пример виджета погоды (заглушка)
            Rectangle {
                anchors.centerIn: parent
                width: 300
                height: 200
                color: "#24283b"
                radius: 12
                
                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    Text { text: "🌤️ Погода"; color: "#9aa5ce"; font.pointSize: 16 }
                    Text { text: "Москва: +5°C"; color: "white"; font.pointSize: 14 }
                    Text { text: "Ветер: 3 м/с"; color: "#9aa5ce"; font.pointSize: 12 }
                }
            }
        }
    }
    
    // Подключение к Wayland
    WaylandSocket {
        id: wlSocket
        onConnected: console.log("Quickshell connected to Wayland")
    }
}
QML

    # Конфигурация Quickshell для автозапуска
    cat > /home/$USERNAME/.config/quickshell/config.toml << QUICKSHELLCONF
# Конфигурация Quickshell
panel = "main.qml"
autostart = true

[environment]
QT_QPA_PLATFORM = "wayland"
GDK_BACKEND = "wayland"
QUICKSHELL_LOG_LEVEL = "info"
QUICKSHELL_LOG_FILE = "/tmp/quickshell.log"
QUICKSHELL_DEBUG = false

[modules]
# Здесь можно подключать дополнительные модули
# widgets = true
# network = true
# battery = true
QUICKSHELLCONF

    # =============================================================
    # КОНФИГУРАЦИЯ HYPRLAND ДЛЯ РАБОТЫ С QUICKSHELL
    # =============================================================
    
    mkdir -p /home/$USERNAME/.config/hypr
    
    cat > /home/$USERNAME/.config/hypr/hyprland.conf << HYPRLAND
# =============================================
# HYPRLAND CONFIG FOR QUICKSHELL
# =============================================

# Мониторы
monitor=,preferred,auto,1

# Автозапуск (Quickshell вместо стандартных панелей)
exec-once = quickshell
exec-once = nm-applet --indicator
exec-once = pipewire
exec-once = wireplumber

# Основные бинды
\$mainMod = SUPER

bind = \$mainMod, Return, exec, kitty
bind = \$mainMod, Q, killactive,
bind = \$mainMod, M, exit,
bind = \$mainMod, E, exec, thunar
bind = \$mainMod, V, togglefloating,
bind = \$mainMod, F, fullscreen,
bind = \$mainMod, Space, exec, fuzzel

# Переключение рабочих столов
bind = \$mainMod, 1, workspace, 1
bind = \$mainMod, 2, workspace, 2
bind = \$mainMod, 3, workspace, 3
bind = \$mainMod, 4, workspace, 4
bind = \$mainMod, 5, workspace, 5

# Перемещение окон
bind = \$mainMod SHIFT, 1, movetoworkspace, 1
bind = \$mainMod SHIFT, 2, movetoworkspace, 2
bind = \$mainMod SHIFT, 3, movetoworkspace, 3
bind = \$mainMod SHIFT, 4, movetoworkspace, 4
bind = \$mainMod SHIFT, 5, movetoworkspace, 5

# Медиа-клавиши
bindel = ,XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
bindel = ,XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bindl = ,XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
bindel = ,XF86MonBrightnessUp, exec, brightnessctl set +10%
bindel = ,XF86MonBrightnessDown, exec, brightnessctl set 10%-

# Оформление
general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2
    col.active_border = rgba(7aa2f7ee) rgba(c0caf5ee) 45deg
    col.inactive_border = rgba(414868aa)
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

windowrulev2 = opacity 0.95 0.95, class:^(kitty)$
windowrulev2 = opacity 0.9 0.9, class:^(thunar)$
HYPRLAND

    # =============================================================
    # КОНФИГУРАЦИЯ ДРУГИХ ПРОГРАММ
    # =============================================================
    
    # Kitty terminal
    mkdir -p /home/$USERNAME/.config/kitty
    cat > /home/$USERNAME/.config/kitty/kitty.conf << KITTY
font_family      JetBrainsMono Nerd Font
font_size        12
background_opacity 0.9
window_padding_width 8
cursor_shape     block
cursor_blink_interval 0
KITTY

    # Waybar (как запасной вариант, если Quickshell не запустится)
    mkdir -p /home/$USERNAME/.config/waybar
    cat > /home/$USERNAME/.config/waybar/config << WAYBAR
{
    "layer": "top",
    "position": "top",
    "height": 30,
    "modules-left": ["hyprland/workspaces"],
    "modules-center": ["clock"],
    "modules-right": ["pulseaudio", "network", "battery", "tray"],
    "hyprland/workspaces": {
        "disable-scroll": true,
        "all-outputs": true
    },
    "clock": {
        "format": "{:%H:%M}",
        "format-alt": "{:%Y-%m-%d}"
    },
    "battery": {
        "format": "{capacity}% {icon}",
        "format-icons": ["", "", "", "", ""]
    }
}
WAYBAR

    # Mako (уведомления)
    mkdir -p /home/$USERNAME/.config/mako
    cat > /home/$USERNAME/.config/mako/config << MAKO
background-color=#1a1b26
text-color=#c0caf5
border-color=#7aa2f7
border-size=2
border-radius=8
default-timeout=5000
ignore-timeout=0
max-history=50
MAKO

    # Права на домашнюю директорию
    chown -R $USERNAME:$USERNAME /home/$USERNAME
    
EOF

    gum style --foreground 46 "✅ Полное окружение с Quickshell установлено!"
fi

# =============================================================
# ФИНАЛИЗАЦИЯ
# =============================================================

sync
umount -R /mnt

gum style --foreground 212 --border-foreground 46 --border double --align center --width 60 --margin "1 2" --padding "2 4" \
"🎉 УСТАНОВКА ЗАВЕРШЕНА! 🎉

💡 Что дальше:
1. Перезагрузись: reboot
2. Войди под пользователем $USERNAME
3. Если выбрал полную установку:
   - Quickshell должен запуститься автоматически
   - Для настройки Quickshell редактируй:
     ~/.config/quickshell/main.qml
   - Логи Quickshell: /tmp/quickshell.log

🔧 Если Quickshell не запускается:
   - Запусти вручную: quickshell
   - Проверь логи
   - Как запасной вариант есть Waybar

🚀 Твой путь кастомизации только начинается!"

# Небольшое предупреждение о паролях
gum style --foreground 214 --border normal --padding "1 2" \
"⚠️  Не забудь сменить пароли после первого входа:
passwd
passwd $USERNAME"
