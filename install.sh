#!/bin/bash

# =============================================
# EDITE AS LISTAS ABAIXO COM SEUS APLICATIVOS
# =============================================

# Pacotes RPM (instala pelo dnf)
RPMS=(
    "pipewire"
    "pipewire-pulseaudio"
    "wireplumber"
    "btop"
    "pavucontrol"
    "bluez"
    "gnome-terminal"
    "gnome-terminal-nautilus"
    "dolphin"
    "nautilus"
    "kate"
    "nano"
    "firefox"
    "labwc-session"
    "labwc"
    "mesa-dri-drivers"
    "gnome-disk-utility"
    "mediawriter"
    "menulibre"
    "filelight"
    "gedit"
    "gnome-boxes"
    "haruna"
    "jstest-gtk"
    "kdenlive"
    "libreoffice"
    "mpv"
    "gnome-logs"
    "okular"
    "vlc"
    "shotcut"
    "setroubleshoot"
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

echo "Adicionando Flathub..."
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

echo ""
echo "Instalando pacotes RPM..."
sudo dnf install -y "${RPMS[@]}"

echo ""
echo "Instalando Flatpaks..."
flatpak install -y flathub "${FLATPAKS[@]}"

echo ""
echo "Pronto! Tudo instalado."
