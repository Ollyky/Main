#!/bin/bash

# =============================================
# EDITE AS LISTAS ABAIXO COM SEUS APLICATIVOS
# =============================================

# Pacotes RPM (instala pelo dnf)
RPMS=(
    # --- Servidores de Áudio, Bluetooth e Comunicação (Wayland) ---
    "pipewire"
    "pipewire-pulseaudio"
    "wireplumber"
    "bluez"
    "bluez-utils"
    "pavucontrol"
    "xdg-desktop-portal-wlr"
    "xdg-desktop-portal-gtk"
    
    # --- Core da Interface Gráfica ---
    "labwc"
    "labwc-session"
    "mesa-dri-drivers"
    
    # --- Ecossistema Obrigatório e Backends do Noctalia Shell ---
    "noctalia-shell"
    "ImageMagick"
    "brightnessctl"
    "ddcutil"
    "wl-clipboard"
    "wlsunset"
    "cava"
    
    # --- Utilitários de Terminal e Desenvolvimento ---
    "btop"
    "gnome-terminal"
    "gnome-terminal-nautilus"
    "kate"
    "nano"
    
    # --- Gestores de Ficheiros e Sistema ---
    "dolphin"
    "nautilus"
    "gnome-disk-utility"
    "mediawriter"
    "menulibre"
    "filelight"
    "gedit"
    "gnome-logs"
    "setroubleshoot"
    
    # --- Produtividade, Multimédia e Virtualização ---
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
)

# Aplicativos Flatpak (instala pelo Flathub)
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
# NÃO PRECISA MEXER ABAIXO DAQUI
# =============================================

# Garante privilégios de root para a configuração de repositórios
if [ "$EUID" -ne 0 ]; then
    echo "Por favor, execute este script com sudo ou como root."
    exit 1
fi

echo "1. Ativando Repositórios de Terceiros Oficiais do Fedora..."
dnf install -y fedora-workstation-repositories

echo "2. Instalando o Repositório Oficial Terra (Noctalia Shell)..."
dnf install -y --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release

echo "3. Instalando o RPM Fusion (Codecs Multimédia adicionais)..."
dnf install -y https://rpmfusion.org(rpm -E %fedora).noarch.rpm \
               https://rpmfusion.org(rpm -E %fedora).noarch.rpm

echo "4. Atualizando os metadados dos repositórios..."
dnf check-update

echo "5. Instalando pacotes RPM do sistema..."
dnf install -y "${RPMS[@]}"

echo "6. Configurando o ecossistema Flatpak..."
flatpak remote-add --if-not-exists flathub https://flathub.org

echo "7. Instalando os aplicativos via Flathub..."
# Executado como utilizador comum via sudo -u se o script foi invocado por um user comum
if [ -n "$SUDO_USER" ]; then
    sudo -u "$SUDO_USER" flatpak install -y flathub "${FLATPAKS[@]}"
else
    flatpak install -y flathub "${FLATPAKS[@]}"
fi

echo "8. Ativando serviços essenciais do sistema..."
systemctl enable --now bluetooth

echo "Pronto! Infraestrutura, dependências do Noctalia e aplicativos instalados com sucesso."
