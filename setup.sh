#!/usr/bin/env bash
# =============================================================================
# setup.sh — Fedora KDE Plasma post-install setup
# Run from ~/config/ on a fresh Fedora install.
# =============================================================================
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# USER-CONFIGURABLE VARIABLES
# ─────────────────────────────────────────────────────────────────────────────

# Absolute path to this repo (where configs live)
CONFIG_DIR="$HOME/config"

# Git remote for neovim config
NVIM_CONFIG_REPO="git@github.com:borgaar/nvim-config.git"

# Swap multiplier (1.25x RAM)
SWAP_MULTIPLIER="1.25"

# Enable YubiKey stuff
YUBIKEY="yes"

# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────

print_section() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

print_step() { echo "  ▶ $1"; }
print_ok()   { echo "  ✓ $1"; }
print_warn() { echo "  ⚠ $1"; }

# ─────────────────────────────────────────────────────────────────────────────
# PREFLIGHT
# ─────────────────────────────────────────────────────────────────────────────

print_section "Preflight checks"

if [[ ! -d "$CONFIG_DIR" ]]; then
    echo "ERROR: CONFIG_DIR '$CONFIG_DIR' does not exist. Aborting."
    exit 1
fi

print_ok "Config directory found: $CONFIG_DIR"

# ─────────────────────────────────────────────────────────────────────────────
# SYSTEM UPDATE & PROPRIETARY REPOS
# ─────────────────────────────────────────────────────────────────────────────

print_section "Enabling RPM Fusion (free + nonfree) and refreshing system"

sudo dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

# Refresh Flathub (full, not the filtered Fedora variant)
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# Full system upgrade first so drivers build against the running kernel
sudo dnf upgrade -y --refresh

print_ok "Repos enabled and system upgraded"

# ─────────────────────────────────────────────────────────────────────────────
# MULTIMEDIA CODECS & FFMPEG
# ─────────────────────────────────────────────────────────────────────────────

print_section "Installing multimedia codecs & FFmpeg"

# Replace the restricted ffmpeg-free stub with the full RPM Fusion build
sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing || true
sudo dnf group upgrade -y multimedia \
    --setopt=install_weak_deps=False \
    --exclude=PackageKit-gstreamer-plugin
sudo dnf group install -y sound-and-video

# GStreamer plugin bundles
sudo dnf install -y \
    gstreamer1-plugins-bad-free \
    gstreamer1-plugins-bad-free-extras \
    gstreamer1-plugins-good \
    gstreamer1-plugins-good-extras \
    gstreamer1-plugins-base \
    gstreamer1-plugin-openh264 \
    gstreamer1-libav \
    lame

print_ok "Codecs installed"

# ─────────────────────────────────────────────────────────────────────────────
# GPU DETECTION & DRIVER / VA-API SETUP
# ─────────────────────────────────────────────────────────────────────────────

print_section "Detecting GPU and installing drivers / hardware acceleration"

HAS_NVIDIA=false
HAS_AMD=false
HAS_INTEL=false

if lspci | grep -Ei 'VGA|3D|Display' | grep -qi 'nvidia'; then HAS_NVIDIA=true; fi
if lspci | grep -Ei 'VGA|3D|Display' | grep -qi 'amd\|radeon'; then HAS_AMD=true; fi
if lspci | grep -Ei 'VGA|3D|Display' | grep -qi 'intel'; then HAS_INTEL=true; fi

if $HAS_NVIDIA; then
    print_step "NVIDIA GPU detected — installing akmod-nvidia (proprietary)"
    sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia xorg-x11-drv-nvidia-cuda
    # NVIDIA VAAPI wrapper for hardware-accelerated video decode
    sudo dnf install -y nvidia-vaapi-driver libva-utils
    print_ok "NVIDIA drivers queued. The kernel module will build on first reboot."
fi

if $HAS_AMD; then
    print_step "AMD GPU detected — installing Mesa freeworld + Vulkan"
    sudo dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld || true
    sudo dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld || true
    # 32-bit libs for Steam / Proton
    sudo dnf swap -y mesa-va-drivers.i686 mesa-va-drivers-freeworld.i686 2>/dev/null || true
    sudo dnf swap -y mesa-vdpau-drivers.i686 mesa-vdpau-drivers-freeworld.i686 2>/dev/null || true
    sudo dnf install -y mesa-vulkan-drivers mesa-vulkan-drivers.i686 vulkan-tools
    print_ok "AMD Mesa freeworld drivers installed"
fi

if $HAS_INTEL; then
    print_step "Intel GPU detected — installing intel-media-driver + Vulkan"
    # intel-media-driver covers Gen9 (Skylake) and newer
    # libva-intel-driver covers older Gen (pre-Skylake)
    sudo dnf install -y intel-media-driver libva-intel-driver libva-utils
    sudo dnf install -y mesa-vulkan-drivers mesa-vulkan-drivers.i686 vulkan-tools
    print_ok "Intel media driver installed"
fi

if ! $HAS_NVIDIA && ! $HAS_AMD && ! $HAS_INTEL; then
    print_warn "Could not auto-detect GPU. Skipping driver install — check manually with: lspci | grep -Ei 'VGA|3D|Display'"
fi

# ─────────────────────────────────────────────────────────────────────────────
# FIRMWARE
# ─────────────────────────────────────────────────────────────────────────────

print_section "Installing additional firmware"

sudo dnf install -y fwupd
sudo fwupdmgr -y refresh --force
sudo fwupdmgr -y get-updates || true
sudo fwupdmgr -y update

print_ok "Firmware installed"

# ─────────────────────────────────────────────────────────────────────────────
# MAIN DNF PACKAGE INSTALL
# ─────────────────────────────────────────────────────────────────────────────

print_section "Installing packages via DNF"

sudo dnf install -y \
    \
    `# ── Browsers & media ──────────────────────────────────────────` \
    firefox \
    mpv \
    vlc \
    \
    `# ── Terminal & shell ─────────────────────────────────────────` \
    alacritty \
    zsh \
    cowsay \
    sl \
    cmatrix \
    \
    `# ── Editors ──────────────────────────────────────────────────` \
    neovim \
    vim \
    \
    `# ── Dev tools: compilers & build systems ─────────────────────` \
    rustup \
    cmake \
    clang \
    clang-tools-extra \
    gcc \
    gcc-c++ \
    make \
    \
    `# ── Dev tools: languages & runtimes ──────────────────────────` \
    python3 \
    python3-pip \
    python3-devel \
    python3-virtualenv \
    nodejs \
    \
    `# ── Dev tools: git & VCS ─────────────────────────────────────` \
    git \
    \
    `# ── Dev tools: shell productivity ────────────────────────────` \
    tmux \
    direnv \
    \
    `# ── Dev tools: search & file navigation ──────────────────────` \
    tree \
    \
    `# ── Dev tools: misc utilities ────────────────────────────────` \
    jq \
    \
    `# ── Language servers (LSPs) ──────────────────────────────────` \
    lua \
    \
    `# ── CLI networking & diagnostics ────────────────────────────` \
    bind-utils \
    nmap-ncat \
    net-tools \
    nmap \
    traceroute \
    mtr \
    tcpdump \
    wireshark-cli \
    iperf3 \
    curl \
    wget \
    httpie \
    openssh-clients \
    openvpn \
    NetworkManager-openvpn \
    iproute \
    iproute-tc \
    iputils \
    whois \
    socat \
    openssl \
    \
    `# ── System monitors & utils ──────────────────────────────────` \
    htop \
    btop \
    iotop \
    lsof \
    strace \
    pciutils \
    usbutils \
    inxi \
    fastfetch \
    duf \
    ncdu \
    psmisc \
    util-linux-user \
    \
    `# ── Productivity / Office ────────────────────────────────────` \
    libreoffice \
    qalculate-qt \
    thunderbird \
    \
    `# ── KDE / Wayland extras ─────────────────────────────────────` \
    spectacle \
    kamoso \
    wl-clipboard \
    xdg-utils \
    \
    `# ── Gaming ───────────────────────────────────────────────────` \
    steam \
    qbittorrent \
    `# ── YubiKey ──────────────────────────────────────────────────` \
    yubikey-manager \
    yubikey-manager-qt \
    pcsc-lite \
    pcsc-lite-ccid \
    pcsc-tools \
    opensc \
    gnupg2 \
    gnupg2-smime \
    pinentry-qt \
    gnupg2-scdaemon

print_ok "DNF packages installed"

# ─────────────────────────────────────────────────────────────────────────────
# Install Starship
# ─────────────────────────────────────────────────────────────────────────────

print_section "Installing Starship through Copr"

sudo dnf copr enable -y atim/starship
sudo dnf install -y starship

print_ok "Installed Starship through Copr"

# ─────────────────────────────────────────────────────────────────────────────
# YUBIKEY — enable pcscd (smartcard daemon)
# ─────────────────────────────────────────────────────────────────────────────

if [[ "$YUBIKEY" == "yes" ]]; then
    sudo systemctl enable --now pcscd.socket
    print_ok "pcscd enabled (socket-activated)"
else
    print_warn "pcscd setup skipped (YUBIKEY=no)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Docker
# ─────────────────────────────────────────────────────────────────────────────

print_section "Installing Docker engine from official Docker repository"

sudo dnf config-manager addrepo --overwrite --from-repofile https://download.docker.com/linux/fedora/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker

print_ok "Docker engine installed and started"

# ─────────────────────────────────────────────────────────────────────────────
# RUST (via rustup — initialize stable toolchain)
# ─────────────────────────────────────────────────────────────────────────────

print_section "Initializing Rust stable toolchain via rustup"

# rustup was installed as an RPM; rustup-init sets up ~/.cargo
rustup-init -y --default-toolchain stable --no-modify-path

# Source cargo env for the remainder of this script
# shellcheck source=/dev/null
source "$HOME/.cargo/env" 2>/dev/null || export PATH="$HOME/.cargo/bin:$PATH"

print_ok "Rust stable toolchain ready (~/.cargo/bin)"

# ─────────────────────────────────────────────────────────────────────────────
# BUN
# ─────────────────────────────────────────────────────────────────────────────

print_section "Installing bun (JavaScript runtime & package manager)"

curl -fsSL https://bun.sh/install | bash
export PATH="$HOME/.bun/bin:$PATH"

print_ok "bun installed to ~/.bun/bin"

# ─────────────────────────────────────────────────────────────────────────────
# LANGUAGE SERVERS via bun (pyright, typescript-language-server)
# ─────────────────────────────────────────────────────────────────────────────

print_section "Installing language servers via bun"

bun install -g pyright typescript typescript-language-server

print_ok "pyright and typescript-language-server installed"

# ─────────────────────────────────────────────────────────────────────────────
# PNPM
# ─────────────────────────────────────────────────────────────────────────────

print_section "Installing pnpm"

curl -fsSL https://get.pnpm.io/install.sh | sh -
export PNPM_HOME="$HOME/.local/share/pnpm"
export PATH="$PNPM_HOME:$PATH"

print_ok "pnpm installed to ~/.local/share/pnpm"

# ─────────────────────────────────────────────────────────────────────────────
# FLATPAK APPS
# Spotify, Discord, OBS Studio are not in Fedora official repos.
# OBS is available as an RPM but Flathub is the OBS Project's recommended path.
# ─────────────────────────────────────────────────────────────────────────────

print_section "Installing Flatpak apps from Flathub"

flatpak install -y --noninteractive flathub \
    com.spotify.Client \
    com.discordapp.Discord \
    com.obsproject.Studio

print_ok "Spotify, Discord, and OBS Studio installed via Flatpak"

# ─────────────────────────────────────────────────────────────────────────────
# SWAPFILE
# ─────────────────────────────────────────────────────────────────────────────

print_section "Creating swapfile at /swapfile (${SWAP_MULTIPLIER}× RAM)"

RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
SWAP_KB=$(awk "BEGIN { printf \"%d\", $RAM_KB * $SWAP_MULTIPLIER }")
SWAP_MB=$(( SWAP_KB / 1024 ))

print_step "Detected RAM: $(( RAM_KB / 1024 )) MiB  →  swap size: ${SWAP_MB} MiB"

sudo fallocate -l "${SWAP_MB}M" /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

if ! grep -q '/swapfile' /etc/fstab; then
    echo '/swapfile none swap defaults 0 0' | sudo tee -a /etc/fstab
fi

print_ok "Swapfile created, activated, and persisted in /etc/fstab"

# ─────────────────────────────────────────────────────────────────────────────
# SYMLINKS
# ─────────────────────────────────────────────────────────────────────────────

print_section "Creating symlinks"

mkdir -p "$HOME/.config"

# ── ~/.config/* directories ──────────────────────────────────────────────────

for dir in alacritty btop htop qalculate; do
    TARGET="$CONFIG_DIR/.config/$dir"
    LINK="$HOME/.config/$dir"
    if [[ -d "$TARGET" ]]; then
        rm -rf "$LINK"
        ln -s "$TARGET" "$LINK"
        print_ok "~/.config/$dir  →  $TARGET"
    else
        print_warn "~/.config/$dir skipped (not found: $TARGET)"
    fi
done

# ── Home directory dotfiles ───────────────────────────────────────────────────

for dotfile in .zshrc .gitconfig; do
    SRC="$CONFIG_DIR/$dotfile"
    DEST="$HOME/$dotfile"
    if [[ -f "$SRC" ]]; then
        rm -f "$DEST"
        ln -s "$SRC" "$DEST"
        print_ok "~/$dotfile  →  $SRC"
    else
        print_warn "~/$dotfile skipped (not found: $SRC)"
    fi
done

# ── .gnupg/sshcontrol + gpg-agent.conf + optional scdaemon.conf ──────────────

mkdir -p "$HOME/.gnupg"
chmod 700 "$HOME/.gnupg"

for gnupg_file in sshcontrol gpg-agent.conf; do
    SRC="$CONFIG_DIR/.gnupg/$gnupg_file"
    DEST="$HOME/.gnupg/$gnupg_file"
    if [[ -f "$SRC" ]]; then
        rm -f "$DEST"
        ln -s "$SRC" "$DEST"
        print_ok "~/.gnupg/$gnupg_file  →  $SRC"
    else
        print_warn "~/.gnupg/$gnupg_file skipped (not found: $SRC)"
    fi
done

if [[ "$YUBIKEY" == "yes" ]]; then
    SCDAEMON_CONF="$HOME/.gnupg/scdaemon.conf"
    if [[ ! -f "$SCDAEMON_CONF" ]]; then
        echo "disable-ccid" > "$SCDAEMON_CONF"
        print_ok "~/.gnupg/scdaemon.conf created (disable-ccid)"
    else
        print_warn "~/.gnupg/scdaemon.conf already exists — skipping"
    fi
fi

print_ok "All symlinks done"

# ─────────────────────────────────────────────────────────────────────────────
# START GPG-AGENT (SSH support) — needed to clone via SSH with YubiKey
# ─────────────────────────────────────────────────────────────────────────────

print_section "Starting gpg-agent with SSH support"

gpgconf --launch gpg-agent
export SSH_AUTH_SOCK=$(gpgconf --list-dirs agent-ssh-socket)
print_ok "SSH_AUTH_SOCK=$SSH_AUTH_SOCK"

# ─────────────────────────────────────────────────────────────────────────────
# NEOVIM CONFIG
# ─────────────────────────────────────────────────────────────────────────────

print_section "Cloning neovim config"

NVIM_DEST="$HOME/.config/nvim"

if [[ -d "$NVIM_DEST" ]]; then
    print_warn "~/.config/nvim already exists — skipping clone"
else
    git clone "$NVIM_CONFIG_REPO" "$NVIM_DEST"
    print_ok "borgaar/nvim-config cloned to ~/.config/nvim"
fi

# ─────────────────────────────────────────────────────────────────────────────
# DEV DIRECTORY
# ─────────────────────────────────────────────────────────────────────────────

mkdir -p "$HOME/dev"
print_ok "~/dev ready"

# ─────────────────────────────────────────────────────────────────────────────
# ZSH AS DEFAULT SHELL
# ─────────────────────────────────────────────────────────────────────────────

print_section "Setting zsh as default shell"

ZSH_PATH="$(command -v zsh)"
if [[ "$SHELL" != "$ZSH_PATH" ]]; then
    sudo chsh -s "$ZSH_PATH" "$USER"
    print_ok "Default shell set to zsh (takes effect on next login)"
else
    print_ok "zsh is already the default shell"
fi

# ─────────────────────────────────────────────────────────────────────────────
# DONE
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║                       ✓  Setup complete!                                 ║"
echo "╠══════════════════════════════════════════════════════════════════════════╣"
echo "║                                                                          ║"
echo "║  Next steps:                                                             ║"
echo "║                                                                          ║"
echo "║  1. REBOOT                                                               ║"
echo "║                                                                          ║"
echo "║  2. SET UP HIBERNATION (swapfile method):                                ║"
echo "║                                                                          ║"
echo "║     a) Get the swap partition UUID:                                      ║"
echo "║          findmnt -no UUID -T /swapfile                                   ║"
echo "║                                                                          ║"
echo "║     b) Get the swap file offset:                                         ║"
echo "║          sudo filefrag -v /swapfile | awk 'NR==4{print $4}'              ║"
echo "║                                                                          ║"
echo "║     c) Add kernel boot parameters (replace <UUID> and <OFFSET>):         ║"
echo "║          sudo grubby --update-kernel=ALL \                               ║"
echo "║            --args='resume=UUID=<UUID> resume_offset=<OFFSET>'            ║"
echo "║                                                                          ║"
echo "║     d) Rebuild initramfs:                                                ║"
echo "║          sudo dracut --regenerate-all --force                            ║"
echo "║                                                                          ║"
echo "║     e) Reboot and test:  systemctl hibernate                             ║"
echo "║                                                                          ║"
echo "║  3. Ensure these are in your PATH (bun installer usually adds them):     ║"
echo "║       ~/.bun/bin  |  ~/.local/share/pnpm  |  ~/.cargo/bin                ║"
echo "║                                                                          ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo ""
