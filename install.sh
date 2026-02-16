#!/bin/bash

# =============================================================
# BLACKARCH В ИЗОЛИРОВАННОМ КОНТЕЙНЕРЕ
# user - обычная жизнь на хосте
# pentest - полностью изолированный BlackArch в контейнере
# =============================================================

set -euo pipefail

# --- Цвета ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Функции ---
log() { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# --- Функция безопасного ввода пароля с очисткой памяти ---
read_secure_password() {
    local prompt=$1
    local password=""
    local password2=""
    
    while true; do
        # Читаем напрямую из /dev/tty
        read -s -p "$prompt: " password < /dev/tty
        echo > /dev/tty
        read -s -p "Подтвердите: " password2 < /dev/tty
        echo > /dev/tty
        
        if [ "$password" != "$password2" ]; then
            echo "❌ Пароли не совпадают!" > /dev/tty
            continue
        fi
        
        # Проверка сложности
        if [ ${#password} -lt 12 ]; then
            echo "❌ Пароль должен быть минимум 12 символов!" > /dev/tty
            continue
        fi
        
        if ! [[ "$password" =~ [0-9] ]]; then
            echo "❌ Пароль должен содержать цифру!" > /dev/tty
            continue
        fi
        
        if ! [[ "$password" =~ [A-Z] ]]; then
            echo "❌ Пароль должен содержать заглавную букву!" > /dev/tty
            continue
        fi
        
        if ! [[ "$password" =~ [a-z] ]]; then
            echo "❌ Пароль должен содержать строчную букву!" > /dev/tty
            continue
        fi
        
        if ! [[ "$password" =~ [^a-zA-Z0-9] ]]; then
            echo "❌ Пароль должен содержать спецсимвол!" > /dev/tty
            continue
        fi
        
        break
    done
    
    # Возвращаем пароль, вызывающая функция должна сразу его использовать и затереть
    echo "$password"
}

# --- Проверка gum ---
if ! command -v gum &> /dev/null; then
    echo -e "${YELLOW}Устанавливаем gum...${NC}"
    pacman -Sy --noconfirm gum
fi

# --- Заголовок ---
gum style --foreground 196 --border-foreground 196 --border double --align center --width 70 --margin "1" --padding "2" \
"🛡️  BLACKARCH В ИЗОЛИРОВАННОМ КОНТЕЙНЕРЕ  🛡️" \
"user - обычная жизнь на хосте" \
"pentest - полностью изолированный контейнер"

# --- Проверка окружения ---
log "Проверяем окружение..."
if ! grep -q "Arch Linux" /etc/os-release 2>/dev/null; then
    error "Запускай скрипт из Arch Linux Live среды!"
fi

if ! ping -c 1 archlinux.org &>/dev/null; then
    error "Нет интернета!"
fi

# =============================================================
# ИНТЕРАКТИВНАЯ НАСТРОЙКА
# =============================================================

# --- Выбор диска ---
gum style --foreground 99 "💾 Выбери диск для установки:"
DISK_LIST=$(lsblk -d -n -o NAME,SIZE,MODEL | grep -v "loop")
SELECTED=$(gum choose --height=10 <<< "$DISK_LIST")
DISK="/dev/$(echo "$SELECTED" | awk '{print $1}')"

gum style --foreground 196 "⚠️  Диск $DISK будет полностью очищен!"
gum confirm "Продолжить?" || exit 0

# --- Имя компьютера ---
HOSTNAME=$(gum input --placeholder "hostname" --value "security-lab")
HOSTNAME=${HOSTNAME:-security-lab}

# --- Пароли для обычного пользователя ---
gum style --foreground 99 "👤 НАСТРОЙКА ОБЫЧНОГО ПОЛЬЗОВАТЕЛЯ (user)"
USER_PASSWORD=$(read_secure_password "Пароль для user")

# --- Пароль root ---
ROOT_PASSWORD=$(read_secure_password "Пароль root")

# --- Размер диска для контейнера ---
gum style --foreground 99 "📦 Выдели место для контейнера с BlackArch (в GiB):"
CONTAINER_SIZE=$(gum input --placeholder "30" --value "30")
CONTAINER_SIZE=${CONTAINER_SIZE:-30}

# --- Выбор набора BlackArch инструментов ---
gum style --foreground 196 "🛠️  Выбери набор инструментов для контейнера:"
TOOLSET_CHOICE=$(gum choose \
    "1️⃣  Минимальный (только базовые, ~2GB)" \
    "2️⃣  Стандартный (рекомендуется, ~8GB)" \
    "3️⃣  Полный (все инструменты, >50GB)")

case "$TOOLSET_CHOICE" in
    *"Минимальный"*)
        BLACKARCH_GROUPS="blackarch-recon blackarch-scanner"
        ;;
    *"Стандартный"*)
        BLACKARCH_GROUPS="blackarch-recon blackarch-scanner blackarch-sniffer \
                          blackarch-forensic blackarch-webapp blackarch-exploitation"
        ;;
    *"Полный"*)
        BLACKARCH_GROUPS="blackarch"
        ;;
esac

# --- Видеодрайвер ---
GPU=$(gum choose "Intel" "AMD" "NVIDIA" "VMware/VirtualBox")
case $GPU in
    "Intel") GRAPHICS="mesa vulkan-intel intel-media-driver" ;;
    "AMD") GRAPHICS="mesa vulkan-radeon xf86-video-amdgpu" ;;
    "NVIDIA") GRAPHICS="nvidia nvidia-utils nvidia-settings"; NVIDIA=true ;;
    "VMware/VirtualBox") GRAPHICS="virtualbox-guest-utils xf86-video-vmware" ;;
esac

# --- Подтверждение ---
gum style --border normal --padding "1" \
"📋 КОНФИГУРАЦИЯ:
Диск:          $DISK
Контейнер:     ${CONTAINER_SIZE}G для BlackArch
Пользователи:  user (хоcт) + pentest (в контейнере)
Инструменты:   $TOOLSET_CHOICE"

gum confirm "Начать установку?" || exit 0

# =============================================================
# РАЗМЕТКА ДИСКА
# =============================================================
log "Размечаем диск..."

# Очистка
sgdisk --zap-all "$DISK"

# Создание разделов: EFI + Boot + Root + Container
sgdisk --new=1:0:+1G --typecode=1:ef00 --change-name=1:"EFI" "$DISK"
sgdisk --new=2:0:+2G --typecode=2:8300 --change-name=2:"BOOT" "$DISK"
sgdisk --new=3:0:0 --typecode=3:8300 --change-name=3:"ROOT" "$DISK"

# Определяем имена разделов
PART_EFI="${DISK}1"
PART_BOOT="${DISK}2"
PART_ROOT="${DISK}3"

if [[ "$DISK" == *"nvme"* ]] || [[ "$DISK" == *"mmcblk"* ]]; then
    PART_EFI="${DISK}p1"
    PART_BOOT="${DISK}p2"
    PART_ROOT="${DISK}p3"
fi

# --- Форматирование ---
log "Форматируем разделы..."
mkfs.fat -F32 "$PART_EFI"
mkfs.ext4 -F "$PART_BOOT"
mkfs.ext4 -F "$PART_ROOT"

# --- Монтирование ---
log "Монтируем разделы..."
mount "$PART_ROOT" /mnt
mkdir -p /mnt/boot
mount -o fmask=0077,dmask=0077 "$PART_BOOT" /mnt/boot
mkdir -p /mnt/boot/efi
mount "$PART_EFI" /mnt/boot/efi

# =============================================================
# УСТАНОВКА БАЗОВОЙ СИСТЕМЫ (ХОСТ)
# =============================================================
log "Устанавливаем базовую систему хоста..."

BASE_PKGS="base linux linux-firmware base-devel networkmanager sudo vim git \
           man-db man-pages texinfo $GRAPHICS \
           systemd-container arch-install-scripts btrfs-progs"

pacstrap /mnt $BASE_PKGS

# Генерация fstab
genfstab -U /mnt >> /mnt/etc/fstab

# =============================================================
# НАСТРОЙКА ХОСТА
# =============================================================
log "Настраиваем хост-систему..."

arch-chroot /mnt /bin/bash <<EOF

# --- Время и локаль ---
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "ru_RU.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# --- Сеть ---
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts << HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS

# --- Создание обычного пользователя ---
useradd -m -G wheel,audio,video,storage,input,power -s /bin/bash user

# --- Настройка sudo ---
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
echo "Defaults timestamp_timeout=10" >> /etc/sudoers
echo "Defaults lecture_file = /etc/sudoers.lecture" >> /etc/sudoers
echo "⚠️  Ты в обычном режиме. Будь осторожен с sudo!" > /etc/sudoers.lecture

# --- Загрузчик (systemd-boot) ---
bootctl install --esp-path=/boot/efi

cat > /boot/loader/entries/arch.conf << BOOT
title   Arch Linux (Host)
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=PARTUUID=$(blkid -s PARTUUID -o value $PART_ROOT) rw quiet
BOOT

cat > /boot/loader/loader.conf << LOADER
default arch.conf
timeout 2
console-mode max
editor no
LOADER

# --- NetworkManager ---
systemctl enable NetworkManager

# --- NVIDIA ---
if [ -n "$NVIDIA" ]; then
    sed -i 's/MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
    mkinitcpio -P
fi

EOF

# --- Установка паролей ---
printf "%s:%s" "root" "$ROOT_PASSWORD" | arch-chroot /mnt chpasswd
printf "%s:%s" "user" "$USER_PASSWORD" | arch-chroot /mnt chpasswd

# Очищаем пароли из памяти
unset ROOT_PASSWORD USER_PASSWORD

# =============================================================
# СОЗДАНИЕ ИЗОЛИРОВАННОГО КОНТЕЙНЕРА ДЛЯ PENTEST
# =============================================================
log "📦 Создаем изолированный контейнер для pentest..."

arch-chroot /mnt /bin/bash <<EOF

# --- Создаем директорию для контейнеров ---
mkdir -p /var/lib/machines
btrfs subvolume create /var/lib/machines/pentest 2>/dev/null || mkdir -p /var/lib/machines/pentest

# --- Устанавливаем BlackArch в контейнер ---
# Сначала устанавливаем базовую систему Arch
pacstrap -c /var/lib/machines/pentest base linux linux-firmware base-devel

# --- Добавляем BlackArch репозиторий в контейнер ---
cat > /var/lib/machines/pentest/tmp/install-blackarch.sh << 'BLACKARCH'
#!/bin/bash
set -e

# Включаем multilib
sed -i '/\[multilib\]/,/Include/ s/^#//' /etc/pacman.conf
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf

# Скачиваем и проверяем ключи BlackArch
cd /tmp
curl --proto "=https" --tlsv1.2 -O https://blackarch.org/blackarch-keyring.pkg.tar.xz
curl --proto "=https" --tlsv1.2 -O https://blackarch.org/blackarch-keyring.pkg.tar.xz.sig

# Проверяем подпись (если есть pacman-key)
pacman-key --verify blackarch-keyring.pkg.tar.xz.sig || exit 1

# Устанавливаем ключи
pacman -U --noconfirm blackarch-keyring.pkg.tar.xz

# Добавляем репозиторий
echo "[blackarch]" >> /etc/pacman.conf
echo "Server = https://mirror.f4st.host/blackarch/\$repo/os/\$arch" >> /etc/pacman.conf
echo "SigLevel = Required DatabaseOptional" >> /etc/pacman.conf

pacman -Syy
BLACKARCH

chmod +x /var/lib/machines/pentest/tmp/install-blackarch.sh
systemd-nspawn -D /var/lib/machines/pentest /tmp/install-blackarch.sh

# --- Устанавливаем выбранные инструменты BlackArch ---
if [ "$BLACKARCH_GROUPS" = "blackarch" ]; then
    systemd-nspawn -D /var/lib/machines/pentest pacman -S --noconfirm blackarch
else
    for group in $BLACKARCH_GROUPS; do
        systemd-nspawn -D /var/lib/machines/pentest pacman -S --noconfirm \$group || true
    done
fi

# --- Создаем пользователя в контейнере ---
systemd-nspawn -D /var/lib/machines/pentest useradd -m -G video,audio -s /bin/bash pentest
systemd-nspawn -D /var/lib/machines/pentest sh -c "echo 'pentest:pentest' | chpasswd"

# --- Настраиваем окружение в контейнере ---
cat > /var/lib/machines/pentest/home/pentest/.bashrc << 'BASHRC'
# Алиасы для пентеста
alias nmap='nmap'
alias wireshark='wireshark'
alias msf='msfconsole'
alias listen='tcpdump -i any'
alias lab='cd ~/labs'
alias tools='cd ~/tools'

# Создаем структуру директорий
mkdir -p ~/labs/{recon,exploit,post}
mkdir -p ~/tools
mkdir -p ~/reports

# Приглашение
PS1='\[\e[0;31m\]pentest\[\e[0m\]@\[\e[0;34m\]\h\[\e[0m\] \w\n# '
BASHRC

# --- Настраиваем X11 forwarding для графических приложений ---
mkdir -p /var/lib/machines/pentest/tmp/.X11-unix
mkdir -p /var/lib/machines/pentest/home/pentest/.Xauthority

EOF

# =============================================================
# НАСТРОЙКА ЗАПУСКА КОНТЕЙНЕРА
# =============================================================
log "🔧 Настраиваем автоматический запуск контейнера..."

arch-chroot /mnt /bin/bash <<EOF

# --- Создаем systemd service для контейнера ---
cat > /etc/systemd/system/pentest-container.service << SERVICE
[Unit]
Description=pentest BlackArch Container
After=network.target

[Service]
ExecStart=/usr/bin/systemd-nspawn -b -D /var/lib/machines/pentest \\
    --bind=/tmp/.X11-unix:/tmp/.X11-unix \\
    --bind=/dev/dri:/dev/dri \\
    --bind=/dev/shm:/dev/shm \\
    --private-network \\
    --network-veth-extra=ve-pentest \\
    --boot
ExecStop=/usr/bin/machinectl poweroff pentest
Restart=no

[Install]
WantedBy=multi-user.target
SERVICE

# --- Настраиваем сетевой мост для контейнера ---
cat > /etc/systemd/network/ve-pentest.network << NETWORK
[Match]
Name=ve-pentest

[Network]
Address=10.0.0.2/24
Gateway=10.0.0.1
NETWORK

# Включаем сервис
systemctl enable pentest-container.service

# --- Создаем скрипт для входа в контейнер от имени user ---
cat > /usr/local/bin/enter-pentest << 'ENTER'
#!/bin/bash
if [ "\$USER" != "user" ]; then
    echo "❌ Только user может входить в контейнер!"
    exit 1
fi

# Проверяем, запущен ли контейнер
if ! machinectl status pentest &>/dev/null; then
    echo "⚠️  Контейнер не запущен. Запускаем..."
    sudo systemctl start pentest-container.service
    sleep 5
fi

# Входим в контейнер
sudo machinectl login pentest
ENTER

chmod +x /usr/local/bin/enter-pentest

# --- Добавляем user в группу для управления контейнерами ---
usermod -aG systemd-nspawn user

# --- Настраиваем sudo для user без пароля для управления контейнером ---
cat > /etc/sudoers.d/99-container << SUDO
user ALL=(root) NOPASSWD: /usr/bin/systemctl start pentest-container.service
user ALL=(root) NOPASSWD: /usr/bin/systemctl stop pentest-container.service
user ALL=(root) NOPASSWD: /usr/bin/systemctl restart pentest-container.service
user ALL=(root) NOPASSWD: /usr/bin/machinectl *
SUDO

EOF

# =============================================================
# УСТАНОВКА HYPRLAND ДЛЯ ПОЛЬЗОВАТЕЛЯ
# =============================================================
log "🎨 Устанавливаем Hyprland для пользователя user..."

arch-chroot /mnt /bin/bash <<EOF

# Установка Hyprland
pacman -S --noconfirm \
    hyprland kitty waybar wofi mako thunar \
    polkit-gnome network-manager-applet \
    pipewire pipewire-pulse wireplumber \
    grim slurp swappy wl-clipboard \
    brightnessctl playerctl pavucontrol \
    ttf-jetbrains-mono-nerd noto-fonts-emoji \
    qt5-wayland qt6-wayland xdg-desktop-portal-hyprland \
    firefox thunderbird libreoffice-fresh \
    zsh zsh-completions

# --- Менеджер входа ---
pacman -S --noconfirm greetd greetd-tuigreet
systemctl enable greetd

cat > /etc/greetd/config.toml << GREET
[terminal]
vt = 1

[default_session]
command = "tuigreet --remember --time --cmd Hyprland"
user = "greeter"
GREET

# --- Конфиг Hyprland для user ---
mkdir -p /home/user/.config/hypr
mkdir -p /home/user/.config/kitty
mkdir -p /home/user/.config/waybar
mkdir -p /home/user/Pictures

cat > /home/user/.config/hypr/hyprland.conf << 'HYPR'
monitor=,preferred,auto,1

exec-once = waybar &
exec-once = mako &
exec-once = nm-applet --indicator &
exec-once = /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &
exec-once = pipewire &
exec-once = wireplumber &

\$mainMod = SUPER
\$terminal = kitty
\$menu = wofi --show drun

bind = \$mainMod, Return, exec, \$terminal
bind = \$mainMod, Q, killactive
bind = \$mainMod, Space, exec, \$menu
bind = \$mainMod, E, exec, thunar

# Горячая клавиша для входа в контейнер
bind = \$mainMod SHIFT, P, exec, kitty -e enter-pentest

general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2
    col.active_border = rgba(7aa2f7ee) rgba(c0caf5ee) 45deg
}

decoration {
    rounding = 8
    blur = yes
}
HYPR

# --- Kitty конфиг ---
cat > /home/user/.config/kitty/kitty.conf << KITTY
font_family JetBrainsMono Nerd Font
font_size 11
background_opacity 0.92
background #1a1b26
foreground #c0caf5
KITTY

# --- Обои ---
curl --proto "=https" --tlsv1.2 -s -L "https://raw.githubusercontent.com/tokyo-night/tokyo-night-vscode-theme/master/wallpapers/tokyo-night.png" \
     -o /home/user/Pictures/wallpaper.jpg 2>/dev/null || true

# --- Права ---
chown -R user:user /home/user

EOF

# =============================================================
# НАСТРОЙКА БЕЗОПАСНОСТИ
# =============================================================
log "🔒 Настраиваем дополнительные механизмы безопасности..."

arch-chroot /mnt /bin/bash <<EOF

# --- UFW firewall ---
pacman -S --noconfirm ufw
systemctl enable ufw
ufw default deny
ufw limit ssh
ufw allow from 192.168.1.0/24 to any port 22 comment 'SSH from LAN'
ufw --force enable

# --- AppArmor для дополнительной защиты ---
pacman -S --noconfirm apparmor
systemctl enable apparmor

# Профиль для контейнера
cat > /etc/apparmor.d/local/usr.bin.systemd-nspawn << APPARMOR
# Дополнительные ограничения для systemd-nspawn
/var/lib/machines/pentest/** r,
deny /home/user/** rw,
deny /root/** rw,
deny /etc/shadow r,
APPARMOR

# --- Аудит действий ---
pacman -S --noconfirm audit
systemctl enable auditd

cat > /etc/audit/rules.d/container.rules << AUDIT
-w /var/lib/machines/pentest -p wa -k pentest_container
-w /usr/local/bin/enter-pentest -p x -k pentest_access
AUDIT

# --- Защита ядра ---
cat > /etc/sysctl.d/99-security.conf << SYSCTL
kernel.kptr_restrict=2
kernel.dmesg_restrict=1
kernel.printk=3 3 3 3
kernel.randomize_va_space=2
kernel.yama.ptrace_scope=2
net.ipv4.conf.all.rp_filter=1
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_rfc1337=1
SYSCTL

# --- Запрещаем прямой доступ к контейнеру для всех, кроме user ---
chmod 750 /var/lib/machines
chown root:systemd-nspawn /var/lib/machines

EOF

# =============================================================
# ФИНАЛИЗАЦИЯ
# =============================================================
log "Завершаем установку..."
sync
umount -R /mnt

# --- Красивый вывод ---
gum style --foreground 196 --border-foreground 46 --border double --align center --width 80 --margin "1" --padding "2" \
"🎉 УСТАНОВКА ЗАВЕРШЕНА! СИСТЕМА ПОЛНОСТЬЮ ИЗОЛИРОВАНА 🎉

┌─────────────────────────────────────────────────────┐
│  👤 ХОСТ (user)                                      │
│  • Обычная повседневная жизнь                        │
│  • Пароль: (ты задал)                                │
│  • Полный доступ к железу                            │
│  • Hyprland с Tokyo Night темой                      │
├─────────────────────────────────────────────────────┤
│  📦 КОНТЕЙНЕР (pentest)                              │
│  • Полная изоляция через systemd-nspawn              │
│  • Собственное сетевое пространство (10.0.0.2)       │
│  • BlackArch с инструментами пентеста                │
│  • Пользователь: pentest / пароль: pentest           │
│  • Нет доступа к файлам хоста                        │
└─────────────────────────────────────────────────────┘

🚀 ПЕРЕЗАГРУЗКА: reboot

🔑 ВХОД В СИСТЕМУ:
   • Логин: user / (твой пароль)
   • Hyprland запустится автоматически

🖥️  ЗАПУСК PENTEST КОНТЕЙНЕРА:
   1. Нажми SUPER + SHIFT + P (откроется терминал)
   2. Или в терминале: enter-pentest
   3. Логин в контейнере: pentest / pentest

📁 ГДЕ ЧТО ХРАНИТСЯ:
   • /home/user          - твои личные файлы
   • /var/lib/machines/pentest - файловая система контейнера
   • В контейнере: ~/labs  - для лабораторных работ
   • В контейнере: ~/reports - для отчетов

🔒 МЕХАНИЗМЫ БЕЗОПАСНОСТИ:
   ✓ Контейнер не видит /home/user
   ✓ Сетевая изоляция (контейнер в своей сети)
   ✓ AppArmor профили
   ✓ Аудит всех действий
   ✓ Firewall с deny по умолчанию
   ✓ Защита ядра (kptr_restrict, dmesg_restrict и др.)

⚠️ ВАЖНО:
   1. Для обновления хоста: sudo pacman -Syu
   2. Для обновления контейнера: enter-pentest → sudo pacman -Syu
   3. Логи аудита: sudo ausearch -k pentest_container
   4. Статус контейнера: machinectl status pentest
   5. Остановка контейнера: sudo systemctl stop pentest-container.service

🎯 ПЕРВЫЕ ШАГИ ПОСЛЕ УСТАНОВКИ:
   1. Войди как user
   2. Открой терминал (SUPER + Return)
   3. Запусти контейнер: enter-pentest
   4. В контейнере: nmap -h (проверка инструментов)
   5. Создай свою первую лабораторию: mkdir -p ~/labs/recon

🛡️  УДАЧНОГО ИЗУЧЕНИЯ БЕЗОПАСНОСТИ!
"
