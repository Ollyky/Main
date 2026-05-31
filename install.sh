#!/bin/bash
    # =============================================
    # Script de Pós-Instalação DEFINITIVO Fedora 44 Minimal → LABWC + Noctalia Shell
    # SRE Líder Validado - Completo, sem cortes, com todas as configurações solicitadas
    # =============================================

    # ==================== LISTAS EXATAS ====================
    RPMS=(
        "pipewire"
        "pipewire-pulseaudio"
        "wireplumber"
        "bluez"
        "bluez-utils"
        "blueman"
        "pavucontrol"
        "xdg-desktop-portal-wlr"
        "xdg-desktop-portal-gtk"
        "xdg-desktop-portal"
        "labwc"
        "labwc-session"
        "mesa-dri-drivers"
        "noctalia-shell"
        "ImageMagick"
        "brightnessctl"
        "ddcutil"
        "wl-clipboard"
        "wlsunset"
        "cava"
        "btop"
        "gnome-terminal"
        "gnome-terminal-nautilus"
        "kate"
        "nano"
        "dolphin"
        "nautilus"
        "gnome-disk-utility"
        "mediawriter"
        "menulibre"
        "filelight"
        "gedit"
        "gnome-logs"
        "setroubleshoot"
        "firefox"
        "haruna"
        "jstest-gtk"
        "kdenlive"
        "libreoffice"
        "mpv"
        "okular"
        "vlc"
        "shotcut"
        "gnome-boxes"
        "tuned-ppd"
        "udisks2"
        "udiskie"
        "sddm"
        "lxqt-policykit"
        "wget"
        "curl"
        "git"
        "sassc"
        "glib2-devel"
        "optipng"
        "inkscape"
        "gnome-online-accounts"
        "gnome-online-accounts-gtk"
        "gvfs-goa"
        "gnome-keyring"
        "gnome-keyring-pam"
        "seahorse"
    )

    FLATPAKS=(
        "chat.revolt.RevoltDesktop"
        "com.github.sdv43.whaler"
        "com.github.tchx84.Flatseal"
        "com.microsoft.Edge"
        "com.stremio.Stremio"
        "com.tonikelope.MegaBasterd"
        "dev.bragefuglseth.Keypunch"
        "io.github.kolunmi.Bazaar"
        "io.github.seadve.Kooha"
        "io.github.spacingbat3.webcord"
        "io.itch.itch"
        "io.mrarm.mcpelauncher"
        "it.mijorus.gearlever"
        "it.mijorus.smile"
        "org.adishatz.Screenshot"
        "org.flatpak.Builder"
        "org.gnome.NetworkDisplays"
        "org.ppsspp.PPSSPP"
        "org.pvermeer.WebAppHub"
        "org.telegram.desktop"
        "org.vinegarhq.Sober"
        "rocks.shy.VacuumTube"
    )

    # =============================================
    # ==================== SCRIPT ====================
    # =============================================

    if [ "$EUID" -ne 0 ]; then
        echo "❌ Execute este script com sudo ou como root."
        exit 1
    fi

    LOGFILE="/var/log/fedora-postinstall.log"
    exec > >(tee -a "$LOGFILE") 2>&1

    echo "=== Iniciando Script Definitivo Fedora 44 LABWC + Noctalia Shell ==="
    echo "Data: $(date)"

    echo "[1/12] Ativando repositórios oficiais..."
    dnf install -y fedora-workstation-repositories dnf-plugins-core

    echo "[2/12] Ativando repositório Terra (Noctalia Shell)..."
    dnf install -y --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release

    echo "[3/12] Ativando RPM Fusion Free + Nonfree..."
    dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm
    dnf install -y https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

    echo "[4/12] Atualizando metadados e sistema..."
    dnf makecache
    dnf upgrade -y

    echo "[5/12] Instalando todos os pacotes RPM..."
    dnf install -y "${RPMS[@]}"

    echo "[6/12] Configurando Flatpak + Flathub..."
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

    echo "[7/12] Instalando todos os Flatpaks..."
    if [ -n "$SUDO_USER" ]; then
        sudo -u "$SUDO_USER" flatpak install --noninteractive flathub "${FLATPAKS[@]}"
    else
        flatpak install --noninteractive flathub "${FLATPAKS[@]}"
    fi

    echo "[8/12] Ativando serviços essenciais..."
    systemctl enable --now sddm bluetooth tuned
    tuned-adm profile balanced

    # ==================== BLOCO DE WALLPAPERS ====================
    echo "[9/12] Criando pasta e baixando Wallpapers..."
    USER_HOME=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)
    WALLPAPER_DIR="$USER_HOME/wallpapers"
    mkdir -p "$WALLPAPER_DIR"
    cd "$WALLPAPER_DIR" || exit

    echo "   → Baixando 9 wallpapers..."

    curl -L -s -o "sage-green-abstract-01.jpg" "https://4kwallpapers.com/images/wallpapers/sage-green-abstract-5120x3413-26355.jpg"
    curl -L -s -o "sage-green-abstract-02.jpg" "https://4kwallpapers.com/images/wallpapers/sage-green-abstract-5120x3413-26354.jpg"
    curl -L -s -o "mountain-landscape.jpg" "https://4kwallpapers.com/images/wallpapers/mountain-landscape-5120x2880-24317.jpg"
    curl -L -s -o "shinra-kusakabe.jpg" "https://4kwallpapers.com/images/wallpapers/shinra-kusakabe-3840x2160-18916.jpg"
    curl -L -s -o "alucard-8k-hellsing.jpg" "https://4kwallpapers.com/images/wallpapers/alucard-8k-hellsing-7680x4320-13839.png"
    curl -L -s -o "alucard-hellsing.jpg" "https://4kwallpapers.com/images/wallpapers/alucard-hellsing-5120x2880-13882.png"
    curl -L -s -o "iridescent-spheres.jpg" "https://4kwallpapers.com/images/wallpapers/iridescent-spheres-5120x5120-26346.jpg"
    curl -L -s -o "macos-wallpaper-01.jpg" "https://www.iclarified.com/images/news/97556/465563/465563.jpg"
    curl -L -s -o "macos-wallpaper-02.jpg" "https://www.iclarified.com/images/news/97556/465563/465563.jpg"

    echo "   → Wallpapers baixados com sucesso!"

    # ==================== TEMA WHITESUR ====================
    echo "[10/12] Instalando Tema WhiteSur macOS..."
    cd /tmp
    git clone https://github.com/vinceliuice/WhiteSur-gtk-theme.git --depth=1
    cd WhiteSur-gtk-theme
    ./install.sh

    cd /tmp
    git clone https://github.com/vinceliuice/WhiteSur-icon-theme.git --depth=1
    cd WhiteSur-icon-theme
    ./install.sh -n WhiteSur

    # ==================== CONFIGURAÇÕES LABWC ====================
    echo "[11/12] Criando configurações completas do LABWC..."

    USER_HOME=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)
    LABWC_CONFIG_DIR="$USER_HOME/.config/labwc"
    mkdir -p "$LABWC_CONFIG_DIR"

    # environment
    cat << 'EOF' > "$LABWC_CONFIG_DIR/environment"
    # Configuração completa LABWC + Noctalia + WhiteSur
    XKB_DEFAULT_LAYOUT="br"
    XKB_DEFAULT_VARIANT="abnt2"
    XKB_DEFAULT_OPTIONS="terminate:ctrl_alt_bksp"
    MOZ_ENABLE_WAYLAND=1
    QT_QPA_PLATFORM=wayland
    GDK_BACKEND=wayland
    QT_STYLE_OVERRIDE=kvantum
    QS_ICON_THEME="WhiteSur"
    EOF

    # autostart
    cat << 'EOF' > "$LABWC_CONFIG_DIR/autostart"
    # Autostart LABWC + Noctalia Shell
    /usr/libexec/polkit-qt-authentication-agent-1 &
    blueman-applet &
    udiskie &
    # GNOME Keyring para senhas (Edge, Discord, etc.)
    gnome-keyring-daemon --start --components=secrets &
    # Noctalia Shell
    noctalia-qs -c noctalia-shell &
    EOF

    # rc.xml (configuração completa)
    cat << 'EOF' > "$LABWC_CONFIG_DIR/rc.xml"
    <?xml version="1.0"?>
    <labwc_config>
      <theme>
        <name>WhiteSur-Dark</name>
      </theme>
      <window>
        <serverDecoration>yes</serverDecoration>
        <titlebar>
          <layout>Close,Iconify,Maximize:Title</layout>
        </titlebar>
      </window>
      <keyboard>
        <keybind key="W-Return">
          <action name="Execute">
            <command>alacritty</command>
          </action>
        </keybind>
        <keybind key="W-t">
          <action name="Execute">
            <command>gnome-terminal</command>
          </action>
        </keybind>
        <keybind key="W-d">
          <action name="Execute">
            <command>dolphin</command>
          </action>
        </keybind>
        <keybind key="W-n">
          <action name="Execute">
            <command>nautilus</command>
          </action>
        </keybind>
        <keybind key="Print">
          <action name="Execute">
            <command>kooha</command>
          </action>
        </keybind>
      </keyboard>
    </labwc_config>
    EOF

    # Configuração do GNOME Keyring no PAM (para login)
    echo "[12/12] Configurando GNOME Keyring e serviços finais..."
    mkdir -p "$USER_HOME/.config/autostart"
    cat << 'EOF' > "$USER_HOME/.config/autostart/gnome-keyring-secrets.desktop"
    [Desktop Entry]
    Type=Application
    Name=GNOME Keyring Secrets
    Exec=gnome-keyring-daemon --start --components=secrets
    Hidden=false
    X-GNOME-Autostart-enabled=true
    EOF

    chown -R "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" "$USER_HOME/.config"

    echo ""
    echo "✅ Script Definitivo Finalizado com Sucesso!"
    echo "📄 Log completo: $LOGFILE"
    echo ""
    echo "Reinicie o sistema e selecione LABWC no SDDM."
    echo "Wallpapers em: ~/wallpapers/"
    echo "Tema WhiteSur instalado."
    echo "Google Drive: Use gnome-online-accounts + gvfs-goa no Nautilus (pode precisar de workaround no Fedora 44)."
