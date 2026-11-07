#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Starting Arch Linux + Sway Dotfiles Installation..."

# 1. Enable Multilib Repository (if not enabled)
if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    echo "Enabling [multilib] repository in /etc/pacman.conf..."
    sudo sed -i '/^#\[multilib\]/{N;s/#\[multilib\]\n#Include/\[multilib\]\nInclude/}' /etc/pacman.conf
    sudo pacman -Syu --noconfirm
fi

# 2. YAY (AUR Helper) Check and Installation
if ! command -v yay &> /dev/null; then
    echo "AUR helper 'yay' not found. Installing..."
    sudo pacman -S --needed --noconfirm git base-devel
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    cd /tmp/yay && makepkg -si --noconfirm
    cd -
    rm -rf /tmp/yay
fi

echo "Updating system repositories and installing dependencies..."

# 3. Official Arch Linux Packages (Includes linux-headers from core repo)
PACMAN_PKGS=(
    sway swaybg foot wmenu swayidle swaylock waybar mako rofi alacritty
    thunar thunar-archive-plugin file-roller
    librewolf imv zathura zathura-pdf-mupdf
    grim slurp swappy wf-recorder cliphist wl-clipboard
    brightnessctl pavucontrol playerctl wireplumber pipewire-audio
    blueman network-manager-applet plasma-systemmonitor
    xdg-desktop-portal-wlr xdg-desktop-portal-gtk
    polkit-kde-agent xdg-user-dirs tlp
    ttf-font-awesome noto-fonts noto-fonts-emoji
    breeze-gtk qt5ct qt6ct fd linux-headers xorg-xwayland
)

sudo pacman -S --needed --noconfirm "${PACMAN_PKGS[@]}"

# 4. AUR Packages & NVIDIA Open Driver Suite
echo "Installing NVIDIA Open packages and AUR dependencies with YAY..."
AUR_PKGS=(
    autotiling
    wlogout
    zapzap
    rofi-emoji
    nvidia-open
    nvidia-utils
    lib32-nvidia-utils
    nvidia-settings
)

yay -S --needed --noconfirm --answerdiff=None --answerclean=None "${AUR_PKGS[@]}"

# 4.1. NVIDIA Driver & DRM / Kernel Modesetting Configuration
echo "Configuring NVIDIA Drivers and DRM Kernel Parameters..."

# 4.2 Automatic Bootloader DRM Parameter Injection (nvidia-drm.modeset=1 nvidia-drm.fbdev=1)
if [ -f /etc/default/grub ]; then
    echo "GRUB bootloader detected. Injecting DRM parameters..."
    if ! grep -q "nvidia-drm.modeset=1" /etc/default/grub; then
        sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="nvidia-drm.modeset=1 nvidia-drm.fbdev=1 /' /etc/default/grub
        sudo grub-mkconfig -o /boot/grub/grub.cfg
    fi
elif [ -d /boot/loader/entries ]; then
    echo "systemd-boot detected. Injecting DRM parameters to boot entries..."
    for entry in /boot/loader/entries/*.conf; do
        if [ -f "$entry" ] && ! grep -q "nvidia-drm.modeset=1" "$entry"; then
            sudo sed -i '/^options/s/$/ nvidia-drm.modeset=1 nvidia-drm.fbdev=1/' "$entry"
        fi
    done
fi

# 4.3 Early Loading of NVIDIA Modules & Removing 'kms' HOOK in /etc/mkinitcpio.conf
echo "Configuring early loading of NVIDIA modules in mkinitcpio..."

# Safely append NVIDIA modules to the MODULES array
if ! grep -q "nvidia_drm" /etc/mkinitcpio.conf; then
    sudo sed -i 's/^MODULES=(/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm /' /etc/mkinitcpio.conf
fi

# Remove conflicting 'kms' module from the HOOKS array
if grep -q "kms" /etc/mkinitcpio.conf; then
    sudo sed -i -E 's/\bkms\b//g; s/ +/ /g' /etc/mkinitcpio.conf
fi
# Regenerate Initramfs
sudo mkinitcpio -P

# 4.4 Adding the Pacman Hook for Automatic DKMS/Kernel Updates
echo "Adding NVIDIA Pacman Hook for kernel updates..."
sudo mkdir -p /etc/pacman.d/hooks

sudo bash -c 'cat << "EOF" > /etc/pacman.d/hooks/nvidia.hook
[Trigger]
Operation=Install
Operation=Upgrade
Operation=Remove
Type=Package
Target=nvidia-open
Target=linux

[Action]
Description=Updating NVIDIA module in initcpio...
Depends=mkinitcpio
When=PostTransaction
NeedsTargets
Exec=/bin/sh -c "while read -r trg; do case \$trg in linux) exit 0; esac; done; /usr/bin/mkinitcpio -P"
EOF'

# 5. Copying Configuration Files
echo "Deploying configuration files to ~/.config/..."

mkdir -p ~/.config
cp -rf "$SCRIPT_DIR/.config/"* ~/.config/

# Initialize XDG User Directories
mkdir -p ~/Desktop ~/Downloads ~/Templates ~/Public ~/Documents ~/Music ~/Pictures ~/Videos ~/Pictures/Wallpapers/lock-screen
xdg-user-dirs-update --force

# 5.1. Generate Thunar Document Templates
echo "Generating file templates for Thunar right-click menu..."
cat << 'EOF' > ~/Templates/"Text Document.txt"
EOF

cat << 'EOF' > ~/Templates/"Bash Script.sh"
#!/bin/bash
EOF
chmod +x ~/Templates/"Bash Script.sh"

cat << 'EOF' > ~/Templates/"Markdown File.md"
# Title
EOF

# Touch empty files for docx and pptx formats
touch ~/Templates/"Word Document.docx"
touch ~/Templates/"PowerPoint Presentation.pptx"

# 6. System Theme & Portal Integration
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

# 7. TLP Power Management Configuration
echo "Configuring TLP power management..."

sudo systemctl enable tlp.service

git clone https://github.com/Chanbadar/TLP-Supergfxctl-Settings-For-Battery.git /tmp/tlp-settings
if [ -f /tmp/tlp-settings/tlp.conf ]; then
    sudo cp /tmp/tlp-settings/tlp.conf /etc/tlp.conf
    sudo tlp start
fi
rm -rf /tmp/tlp-settings

echo "Installation complete. Self-cleaning installation directory..."

# 8. Self Cleanup (Removes cloned repository)
cd ~
rm -rf "$SCRIPT_DIR"

echo "Cleanup finished. Start Sway or reload using 'Mod+Shift+C'."
