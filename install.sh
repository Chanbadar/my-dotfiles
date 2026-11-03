#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Starting Arch Linux + Sway Dotfiles Installation..."

# 1. YAY (AUR Helper) Check and Installation
if ! command -v yay &> /dev/null; then
    echo "AUR helper 'yay' not found. Installing..."
    sudo pacman -S --needed --noconfirm git base-devel
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    cd /tmp/yay && makepkg -si --noconfirm
    cd -
    rm -rf /tmp/yay
fi

echo "Updating system repositories and installing dependencies..."

# 2. Official Arch Linux Packages
PACMAN_PKGS=(
    sway swayidle swaylock waybar mako rofi alacritty
    thunar thunar-archive-plugin file-roller
    librewolf imv zathura zathura-pdf-mupdf
    grim slurp swappy wf-recorder cliphist wl-clipboard
    brightnessctl playerctl wireplumber pipewire-audio
    blueman network-manager-applet plasma-systemmonitor
    xdg-desktop-portal-wlr xdg-desktop-portal-gtk
    polkit-kde-agent xdg-user-dirs tlp
    ttf-font-awesome noto-fonts noto-fonts-emoji
    breeze-gtk qt5ct qt6ct fd
)

sudo pacman -S --needed --noconfirm "${PACMAN_PKGS[@]}"

# 3. AUR Packages
AUR_PKGS=(
    autotiling
    wlogout
    zapzap
    rofi-emoji
)

yay -S --needed --noconfirm --answerdiff=None --answerclean=None "${AUR_PKGS[@]}"

# 4. Copying Configuration Files
echo "Deploying configuration files to ~/.config/..."

mkdir -p ~/.config
cp -rf "$SCRIPT_DIR/.config/"* ~/.config/

# Initialize XDG User Directories
mkdir -p ~/Desktop ~/Downloads ~/Templates ~/Public ~/Documents ~/Music ~/Pictures ~/Videos ~/Pictures/Wallpapers/lock-screen
xdg-user-dirs-update --force

# 5. System Theme & Portal Integration
echo "Applying dark theme configurations..."

gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
gsettings set org.gnome.desktop.interface gtk-theme 'Breeze-Dark'

# Deploy System Environment Variables (/etc/environment)
if [ -f "$SCRIPT_DIR/environment" ]; then
    echo "Deploying system environment variables to /etc/environment..."
    sudo cp "$SCRIPT_DIR/environment" /etc/environment
fi

# Setting Default Applications
xdg-mime default imv.desktop image/png image/jpeg image/webp image/gif
xdg-mime default org.pwmt.zathura.desktop application/pdf

# Set Configuration Permissions
chmod +x ~/.config/sway/config 2>/dev/null || true

# 6. TLP Power Management Configuration
echo "Configuring TLP power management..."

sudo systemctl enable tlp.service

git clone https://github.com/Chanbadar/TLP-Supergfxctl-Settings-For-Battery.git /tmp/tlp-settings
if [ -f /tmp/tlp-settings/tlp.conf ]; then
    sudo cp /tmp/tlp-settings/tlp.conf /etc/tlp.conf
    sudo tlp start
fi
rm -rf /tmp/tlp-settings

echo "Installation complete. Self-cleaning installation directory..."

# 7. Self Cleanup (Removes cloned repository)
cd ~
rm -rf "$SCRIPT_DIR"

echo "Cleanup finished. Start Sway or reload using 'Mod+Shift+C'."
