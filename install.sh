#!/bin/bash
set -e

### УКАЖИ СВОЙ ДИСК
DISK="/dev/nvme0n1"

### Разметка (best-practice)
sgdisk -Z $DISK
sgdisk -n 1:0:+512M -t 1:ef00 $DISK
sgdisk -n 2:0:0       -t 2:8300 $DISK

mkfs.fat -F32 ${DISK}p1
mkfs.ext4 ${DISK}p2

mount ${DISK}p2 /mnt
mkdir /mnt/boot
mount ${DISK}p1 /mnt/boot

### Базовая система
pacstrap /mnt base linux linux-firmware networkmanager sudo vim git \
    base-devel man-db man-pages

genfstab -U /mnt &amp;amp;amp;gt;&amp;amp;amp;gt; /mnt/etc/fstab

### CHROOT
arch-chroot /mnt /bin/bash &amp;amp;amp;lt;&amp;amp;amp;lt; 'EOF'

### Локали
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" &amp;amp;amp;gt; /etc/locale.conf

### Хостнейм
echo "archlinux" &amp;amp;amp;gt; /etc/hostname

### Сеть
systemctl enable NetworkManager

### Пользователь
useradd -m -G wheel video input seat user
echo "user:password" | chpasswd
echo "root:password" | chpasswd
sed -i 's/# %wheel ALL/%wheel ALL/' /etc/sudoers

### SUDO безопасность
echo "Defaults timestamp_timeout=0" &amp;amp;amp;gt;&amp;amp;amp;gt; /etc/sudoers
echo "Defaults logfile=/var/log/sudo.log" &amp;amp;amp;gt;&amp;amp;amp;gt; /etc/sudoers

### systemd-boot
bootctl install

ROOT_UUID=$(blkid -s PARTUUID -o value ${DISK}p2)

cat &amp;amp;amp;lt;&amp;amp;amp;lt; BOOT &amp;amp;amp;gt; /boot/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=PARTUUID=$ROOT_UUID rw quiet splash
BOOT

### БАЗОВАЯ БЕЗОПАСНОСТЬ

### 1. auditd — обязательное журналирование действий
pacman -S --noconfirm audit
systemctl enable auditd

### 2. Firewall (nftables)
pacman -S --noconfirm nftables
systemctl enable nftables

cat &amp;amp;amp;lt;&amp;amp;amp;lt; NFT &amp;amp;amp;gt; /etc/nftables.conf
table inet filter {
  chain input {
    type filter hook input priority 0;
    ct state established,related accept
    iif lo accept
    ip protocol icmp accept
    tcp dport { 22 } accept
    reject
  }
  chain forward { reject }
  chain output { accept }
}
NFT

### 3. journald: защита логов
cat &amp;amp;amp;lt;&amp;amp;amp;lt; JRN &amp;amp;amp;gt; /etc/systemd/journald.conf.d/00-sec.conf
[Journal]
Storage=persistent
Compress=yes
MaxRetentionSec=14day
Seal=yes
SplitMode=uid
JRN

### 4. Fail2ban
pacman -S --noconfirm fail2ban
systemctl enable fail2ban

### 5. Автообновления (без фанатизма)
pacman -S --noconfirm cronie
systemctl enable cronie

echo "0 5 * * * root pacman -Sy --noconfirm &amp;amp;amp;amp;&amp;amp;amp;amp; pacman -Su --noconfirm" \
    &amp;amp;amp;gt; /etc/cron.d/auto-update


### Установка Hyprland + окружение
pacman -S --noconfirm \
  hyprland kitty waybar mako thunar \
  polkit polkit-kde-agent \
  pipewire pipewire-alsa pipewire-pulse wireplumber \
  wl-clipboard grim slurp \
  swww network-manager-applet \
  ttf-jetbrains-mono-nerd \
  brightnessctl \
  gvfs fuzzel

### greetd
pacman -S --noconfirm greetd greetd-tuigreet
systemctl enable greetd

cat &amp;amp;amp;lt;&amp;amp;amp;lt; GREET &amp;amp;amp;gt; /etc/greetd/config.toml
[terminal]
vt = 1

[default_session]
command = "Hyprland"
user = "user"
GREET

### Конфиги Hyprland
mkdir -p /home/user/.config/hypr
cat &amp;amp;amp;lt;&amp;amp;amp;lt; HYPR &amp;amp;amp;gt; /home/user/.config/hypr/hyprland.conf
exec-once = waybar &amp;amp;amp;amp;
exec-once = mako &amp;amp;amp;amp;
exec-once = nm-applet &amp;amp;amp;amp;
exec-once = swww init &amp;amp;amp;amp;&amp;amp;amp;amp; swww img ~/Pictures/wall.jpg

source = ~/.config/hypr/keybinds.conf
source = ~/.config/hypr/monitors.conf

general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2
    layout = dwindle
}

decoration {
    rounding = 8
    blur = yes
    blur_size = 4
}
HYPR

mkdir -p /home/user/.config/hypr

cat &amp;amp;amp;lt;&amp;amp;amp;lt; KEYS &amp;amp;amp;gt; /home/user/.config/hypr/keybinds.conf
bind = SUPER, Return, exec, kitty
bind = SUPER, Q, killactive
bind = SUPER, D, exec, fuzzel

bind = SUPER, 1, workspace, 1
bind = SUPER, 2, workspace, 2
bind = SUPER, 3, workspace, 3
bind = SUPER, 4, workspace, 4

bind = SUPER+SHIFT, 1, movetoworkspace, 1
bind = SUPER+SHIFT, 2, movetoworkspace, 2
bind = SUPER+SHIFT, 3, movetoworkspace, 3
bind = SUPER+SHIFT, 4, movetoworkspace, 4

bind = SUPER, F, fullscreen
bind = SUPER, V, togglefloating

bind = SUPER, E, exec, thunar

bind = ,XF86MonBrightnessUp, exec, brightnessctl set +10%
bind = ,XF86MonBrightnessDown, exec, brightnessctl set 10%-
bind = ,XF86AudioRaiseVolume, exec, pactl set-sink-volume @DEFAULT_SINK@ +5%
bind = ,XF86AudioLowerVolume, exec, pactl set-sink-volume @DEFAULT_SINK@ -5%
bind = ,XF86AudioMute, exec, pactl set-sink-mute @DEFAULT_SINK@ toggle
KEYS

cat &amp;amp;amp;lt;&amp;amp;amp;lt; MON &amp;amp;amp;gt; /home/user/.config/hypr/monitors.conf
monitor = , preferred, auto, 1
MON

### Waybar
mkdir -p /home/user/.config/waybar
cat &amp;amp;amp;lt;&amp;amp;amp;lt; WB &amp;amp;amp;gt; /home/user/.config/waybar/config
{
  "layer": "top",
  "position": "top",
  "modules-left": ["hyprland/workspaces"],
  "modules-center": ["clock"],
  "modules-right": ["pulseaudio","network","battery"],
  "clock": { "format": "%H:%M" }
}
WB

### Kitty
mkdir -p /home/user/.config/kitty
cat &amp;amp;amp;lt;&amp;amp;amp;lt; KIT &amp;amp;amp;gt; /home/user/.config/kitty/kitty.conf
font_family JetBrainsMono Nerd Font
font_size 13
cursor_blink_interval 0
KIT

### Mako
mkdir -p /home/user/.config/mako
cat &amp;amp;amp;lt;&amp;amp;amp;lt; MK &amp;amp;amp;gt; /home/user/.config/mako/config
background-color=#1e1e2eff
border-color=#88c0d0ff
text-color=#eceff4ff
border-size=2
default-timeout=5000
MK

### Wallpaper
mkdir -p /home/user/Pictures
curl -s -L https://picsum.photos/1920/1080 -o /home/user/Pictures/wall.jpg

chown -R user:user /home/user

EOF

echo "ГОТОВО. Перезагружайся."
