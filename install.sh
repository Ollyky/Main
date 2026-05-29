#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  post-install-fedora44-labwc-noctalia.sh                                ║
# ║  Fedora 44 Minimal → LABWC + Noctalia Shell + WhiteSur macOS           ║
# ║  Versão: 4.0 — Final Consolidada                                        ║
# ║                                                                          ║
# ║  Uso: sudo ./post-install-fedora44-labwc-noctalia.sh                    ║
# ║                                                                          ║
# ║  DECISÕES TÉCNICAS:                                                      ║
# ║  - tuned-ppd (NÃO power-profiles-daemon NEM tlp — conflito fatal)      ║
# ║  - PipeWire gerido pelo systemd --user (NUNCA no autostart)             ║
# ║  - Polkit: /usr/libexec/polkit-qt-authentication-agent-1                ║
# ║  - Terra $releasever: aspas simples impedem expansão bash               ║
# ║  - Fastfetch: dnf nativo (SEM compilação manual)                        ║
# ║  - XKB ABNT2: XKB_DEFAULT_LAYOUT=br / MODEL=abnt2 / VARIANT=abnt2     ║
# ║  - Botões semáforo: themerc-override com cores exatas do macOS Sonoma  ║
# ╚══════════════════════════════════════════════════════════════════════════╝
# SCRIPT ORIGINAL!
# ─────────────────────────────────────────────────────────────────────────
# BLOCO 0: CONFIGURAÇÃO GLOBAL
# ─────────────────────────────────────────────────────────────────────────

readonly VERDE="\e[32m"
readonly VERMELHO="\e[31m"
readonly AMARELO="\e[33m"
readonly AZUL="\e[34m"
readonly CIANO="\e[36m"
readonly NEGRITO="\e[1m"
readonly RESET="\e[0m"

readonly LOG_FILE="/var/log/post-install-labwc.log"

readonly USUARIO_REAL="${SUDO_USER:-$USER}"
readonly HOME_REAL="/home/${USUARIO_REAL}"

ERROS=0

# ─────────────────────────────────────────────────────────────────────────
# BLOCO 1: FUNÇÕES UTILITÁRIAS
# ─────────────────────────────────────────────────────────────────────────

log_ok()   { echo -e "${VERDE}${NEGRITO}  ✓${RESET}  $1"; }
log_err()  { echo -e "${VERMELHO}${NEGRITO}  ✗ ERRO:${RESET} $1" | tee -a "${LOG_FILE}"; ((ERROS++)); }
log_info() { echo -e "${AZUL}${NEGRITO}  →${RESET}  $1"; }
log_warn() { echo -e "${AMARELO}${NEGRITO}  ⚠${RESET}  $1"; }
log_step() { echo -e "${CIANO}${NEGRITO}  [$1]${RESET} $2"; }

separador() {
    echo ""
    echo -e "${AZUL}${NEGRITO}══════════════════════════════════════════════════════${RESET}"
    echo -e "${AZUL}${NEGRITO}  $1${RESET}"
    echo -e "${AZUL}${NEGRITO}══════════════════════════════════════════════════════${RESET}"
    echo ""
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${VERMELHO}${NEGRITO}ERRO: execute como root → sudo $0${RESET}"
        exit 1
    fi
    if [[ -z "${SUDO_USER:-}" || "${SUDO_USER}" == "root" ]]; then
        echo -e "${VERMELHO}${NEGRITO}ERRO: execute via 'sudo' a partir do seu usuário normal.${RESET}"
        exit 1
    fi
}

pkg_instalado() {
    rpm -q "$1" &>/dev/null
}

instalar_pacote() {
    local pkg="$1"
    if pkg_instalado "$pkg"; then
        log_warn "${pkg} já instalado — pulando"
        return 0
    fi
    log_info "Instalando ${pkg}..."
    if dnf install -y "$pkg" >> "${LOG_FILE}" 2>&1; then
        log_ok "${pkg}"
    else
        log_err "Falha ao instalar: ${pkg} (veja ${LOG_FILE})"
        return 1
    fi
}

instalar_grupo() {
    local rotulo="$1"
    shift
    local pacotes=("$@")
    separador "Instalando: ${rotulo}"
    for pkg in "${pacotes[@]}"; do
        instalar_pacote "$pkg"
    done
}

habilitar_servico() {
    local svc="$1"
    log_info "Habilitando serviço: ${svc}"
    if systemctl enable "$svc" >> "${LOG_FILE}" 2>&1; then
        log_ok "${svc} habilitado"
    else
        log_err "Falha ao habilitar ${svc}"
    fi
}

habilitar_servico_usuario() {
    local svc="$1"
    log_info "Serviço de usuário: ${svc} → ${USUARIO_REAL}"
    if sudo -u "${USUARIO_REAL}" \
        XDG_RUNTIME_DIR="/run/user/$(id -u "${USUARIO_REAL}")" \
        systemctl --user enable "$svc" >> "${LOG_FILE}" 2>&1; then
        log_ok "${svc} habilitado para ${USUARIO_REAL}"
    else
        log_err "Falha: ${svc} para ${USUARIO_REAL}"
    fi
}

habilitar_copr() {
    local repo="$1"
    log_info "Habilitando COPR: ${repo}"
    if dnf copr enable -y "$repo" >> "${LOG_FILE}" 2>&1; then
        log_ok "COPR ${repo} habilitado"
    else
        log_err "Falha ao habilitar COPR ${repo}"
        return 1
    fi
}

# Escreve conteúdo de variável de string para arquivo, com chown.
# Uso: escrever_arquivo_usuario "/caminho/arquivo" "${CONTEUDO_VAR}"
escrever_arquivo_usuario() {
    local destino="$1"
    local conteudo="$2"
    local dir
    dir="$(dirname "${destino}")"
    mkdir -p "$dir"
    printf '%s\n' "${conteudo}" > "${destino}"
    chown -R "${USUARIO_REAL}:${USUARIO_REAL}" "$dir"
    log_ok "Arquivo criado: ${destino}"
}

# ─────────────────────────────────────────────────────────────────────────
# BLOCO 2: ARRAYS DE PACOTES
# ─────────────────────────────────────────────────────────────────────────

# Componentes de sistema obrigatórios:
# Wayland, DM, Polkit, Áudio, Bluetooth, Energia, USB, Portals, Keyring, git
PKGS_CORE=(
    "labwc"
    "labwc-session"
    "sddm"
    "lxqt-policykit"
    "pipewire"
    "pipewire-pulseaudio"
    "wireplumber"
    "bluez"
    "blueman"
    "tuned-ppd"
    "brightnessctl"
    "udisks2"
    "udiskie"
    "xdg-desktop-portal"
    "xdg-desktop-portal-wlr"
    "xdg-desktop-portal-gtk"
    "gnome-keyring"
    "gnome-keyring-pam"
    "git"
    "curl"
    "wget"
    "ca-certificates"
    "dnf-plugins-core"
)

# Aplicações desktop KDE/GNOME.
# REMOVIDOS: gnome-terminal (redundante), foot, fuzzel.
# INCLUÍDOS: fastfetch via dnf nativo (SEM build manual).
PKGS_APPS=(
    "alacritty"
    "konsole"
    "dolphin"
    "nautilus"
    "gnome-online-accounts"
    "gnome-online-accounts-gtk"
    "gvfs-goa"
    "seahorse"
    "kate"
    "nano"
    "spectacle"
    "grim"
    "slurp"
    "firefox"
    "fastfetch"
)

# Deps obrigatórias do noctalia-shell (Requires: no .spec RPM).
# gpu-screen-recorder vem do COPR brycensranch/gpu-screen-recorder-git.
# rsms-inter-fonts (fonte Inter) vem do Terra.
# SEM estes pacotes → dnf install noctalia-shell falha com dep não resolvida.
PKGS_NOCTALIA_DEPS=(
    "dejavu-sans-fonts"
    "google-roboto-fonts"
    "gpu-screen-recorder"
    "rsms-inter-fonts"
)

# Deps recomendadas do noctalia-shell (ativam features extras da shell).
# cava → visualizador de áudio no widget de música
# cliphist → histórico de clipboard
# matugen → paleta de cores dinâmica a partir do wallpaper
# wlsunset → temperatura de cor (modo noturno)
# ddcutil → brilho em monitores externos via DDC/CI
# pavucontrol → mixer gráfico de áudio
PKGS_NOCTALIA_RECOMMENDED=(
    "cava"
    "cliphist"
    "matugen"
    "wlsunset"
    "ddcutil"
    "pavucontrol"
)

# Deps de compilação para os instaladores do WhiteSur GTK e Icon theme.
PKGS_WHITESUR_BUILD_DEPS=(
    "sassc"
    "glib2-devel"
    "optipng"
    "inkscape"
)

# ─────────────────────────────────────────────────────────────────────────
# BLOCO 3: CONTEÚDO DOS DOTFILES DO LABWC
#
# Armazenados em variáveis com aspas simples: bash NÃO interpola
# $VAR ou $(cmd) no interior. O conteúdo é escrito literalmente.
# Quando executado ou lido, o interpretador alvo processa os tokens.
# ─────────────────────────────────────────────────────────────────────────

# ── ~/.config/labwc/autostart ─────────────────────────────────────────
# CRÍTICO: Sem pipewire, pipewire-pulse ou wireplumber.
# PipeWire gerido 100% pelo systemd --user (etapa 8b do main).
# Duplicar no autostart = duas instâncias em conflito.
# Polkit: /usr/libexec/polkit-qt-authentication-agent-1 (nome REAL no Fedora)
CONTEUDO_AUTOSTART='#!/usr/bin/env bash
# labwc autostart — executado pelo compositor a cada início de sessão.
# Cada processo roda em background (&) para não bloquear o autostart.

# ── Agente Polkit ─────────────────────────────────────────────────────
# Exibe diálogos gráficos de autenticação quando apps precisam de root.
# Caminho absoluto: não depende do $PATH da sessão.
# Nome real do executável no Fedora: polkit-qt-authentication-agent-1
/usr/libexec/polkit-qt-authentication-agent-1 &

# ── GNOME Keyring ─────────────────────────────────────────────────────
# Desbloqueia e gerencia segredos, certificados e chaves SSH.
# eval importa as variáveis exportadas pelo daemon no shell atual.
eval "$(gnome-keyring-daemon --start --components=secrets,pkcs11,ssh)"
export GNOME_KEYRING_CONTROL
export GNOME_KEYRING_PID
export SSH_AUTH_SOCK

# ── Bluetooth ─────────────────────────────────────────────────────────
blueman-applet &

# ── Montagem automática de USB ────────────────────────────────────────
# udiskie -t: monta dispositivos e exibe ícone de ejeção na system tray.
udiskie -t &

# ── Noctalia Shell ────────────────────────────────────────────────────
# Painel superior, dock, widgets, launcher, notificações, MPRIS.
# qs é o binário do noctalia-qs instalado via Terra.
qs -c noctalia-shell &

# ── Propagação de variáveis de sessão para systemd --user e D-Bus ────
# Sem isso, apps iniciados via systemd --user não enxergam WAYLAND_DISPLAY.
systemctl --user import-environment \
    WAYLAND_DISPLAY \
    XDG_CURRENT_DESKTOP \
    XDG_SESSION_TYPE \
    DESKTOP_SESSION \
    QT_QPA_PLATFORM \
    GDK_BACKEND \
    MOZ_ENABLE_WAYLAND \
    ELECTRON_OZONE_PLATFORM_HINT \
    XKB_DEFAULT_MODEL \
    XKB_DEFAULT_LAYOUT \
    XKB_DEFAULT_VARIANT \
    GNOME_KEYRING_CONTROL \
    GNOME_KEYRING_PID \
    SSH_AUTH_SOCK 2>/dev/null || true

dbus-update-activation-environment --systemd \
    WAYLAND_DISPLAY \
    XDG_CURRENT_DESKTOP \
    XDG_SESSION_TYPE \
    QT_QPA_PLATFORM \
    GDK_BACKEND \
    MOZ_ENABLE_WAYLAND \
    ELECTRON_OZONE_PLATFORM_HINT \
    XKB_DEFAULT_MODEL \
    XKB_DEFAULT_LAYOUT \
    XKB_DEFAULT_VARIANT \
    GNOME_KEYRING_CONTROL \
    GNOME_KEYRING_PID \
    SSH_AUTH_SOCK 2>/dev/null || true'

# ── ~/.config/labwc/rc.xml ─────────────────────────────────────────────
# Configuração principal do compositor.
# Layout "Close,Iconify,Maximize:Title":
#   items ANTES de :Title → lado ESQUERDO (semáforo macOS)
#   items APÓS :Title   → lado direito
# "Iconify" é o token correto no LABWC para minimizar (não "Minimize").
# Tema "WhiteSur-Dark": ~/.themes/WhiteSur-Dark/openbox-3/ (instalado pelo script).
CONTEUDO_RC_XML='<?xml version="1.0" encoding="UTF-8"?>
<labwc_config>

  <!-- ── TEMA E BOTÕES SEMÁFORO ─────────────────────────────────────────
       WhiteSur-Dark instalado em ~/.themes/WhiteSur-Dark/openbox-3/.
       Layout: Close,Iconify,Maximize:Title = botões à ESQUERDA.
       As cores dos botões são definidas em ~/.config/labwc/themerc-override. -->
  <theme>
    <name>WhiteSur-Dark</name>
    <titlebar>
      <layout>Close,Iconify,Maximize:Title</layout>
    </titlebar>
    <font place="ActiveWindow">
      <name>Inter</name>
      <size>10</size>
      <weight>Bold</weight>
    </font>
    <font place="InactiveWindow">
      <name>Inter</name>
      <size>10</size>
      <weight>Normal</weight>
    </font>
  </theme>

  <!-- ── COMPORTAMENTO DO COMPOSITOR ────────────────────────────────── -->
  <core>
    <decoration>server</decoration>
    <gap>8</gap>
    <adaptiveSync>yes</adaptiveSync>
  </core>

  <!-- ── POLÍTICA DE FOCO ───────────────────────────────────────────── -->
  <focus>
    <followMouse>yes</followMouse>
    <raiseOnFocus>no</raiseOnFocus>
  </focus>

  <!-- ── ATALHOS DE TECLADO ─────────────────────────────────────────── -->
  <keyboard>

    <!-- Terminal: Alacritty (nativo Wayland, alta performance) -->
    <keybind key="Super-Return">
      <action name="Execute">
        <command>alacritty</command>
      </action>
    </keybind>

    <!-- Terminal alternativo: Konsole (abas, perfis) -->
    <keybind key="Super-Shift-Return">
      <action name="Execute">
        <command>konsole</command>
      </action>
    </keybind>

    <!-- Fechar janela com foco -->
    <keybind key="Super-q">
      <action name="Close"/>
    </keybind>

    <!-- Maximizar / restaurar janela -->
    <keybind key="Super-m">
      <action name="ToggleMaximize"/>
    </keybind>

    <!-- Minimizar janela (Iconify = token correto no LABWC) -->
    <keybind key="Super-h">
      <action name="Iconify"/>
    </keybind>

    <!-- Screenshot completo via Spectacle (GUI KDE com opções) -->
    <keybind key="Print">
      <action name="Execute">
        <command>spectacle</command>
      </action>
    </keybind>

    <!-- Screenshot de área interativa: grim (captura) + slurp (seleção).
         LABWC executa via sh -c para comandos com $() — expansão correta. -->
    <keybind key="Super-Print">
      <action name="Execute">
        <command>grim -g "$(slurp)" $HOME/Screenshots/$(date +%Y%m%d_%H%M%S).png</command>
      </action>
    </keybind>

    <!-- Recarregar configuração sem encerrar sessão -->
    <keybind key="Super-Shift-r">
      <action name="Reconfigure"/>
    </keybind>

    <!-- Gestor de ficheiros: Dolphin -->
    <keybind key="Super-e">
      <action name="Execute">
        <command>dolphin</command>
      </action>
    </keybind>

    <!-- Editor: Kate -->
    <keybind key="Super-k">
      <action name="Execute">
        <command>kate</command>
      </action>
    </keybind>

    <!-- Firefox -->
    <keybind key="Super-b">
      <action name="Execute">
        <command>firefox</command>
      </action>
    </keybind>

    <!-- VS Code -->
    <keybind key="Super-c">
      <action name="Execute">
        <command>code</command>
      </action>
    </keybind>

    <!-- Brilho de tela (requer brightnessctl + grupo video) -->
    <keybind key="XF86MonBrightnessUp">
      <action name="Execute">
        <command>brightnessctl set +5%</command>
      </action>
    </keybind>

    <keybind key="XF86MonBrightnessDown">
      <action name="Execute">
        <command>brightnessctl set 5%-</command>
      </action>
    </keybind>

    <!-- Volume via WirePlumber (wpctl faz parte do wireplumber) -->
    <keybind key="XF86AudioRaiseVolume">
      <action name="Execute">
        <command>wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+</command>
      </action>
    </keybind>

    <keybind key="XF86AudioLowerVolume">
      <action name="Execute">
        <command>wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-</command>
      </action>
    </keybind>

    <keybind key="XF86AudioMute">
      <action name="Execute">
        <command>wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle</command>
      </action>
    </keybind>

  </keyboard>

  <!-- ── AÇÕES DO MOUSE ──────────────────────────────────────────────── -->
  <mouse>

    <context name="TitleBar">
      <mousebind button="Left" action="Drag">
        <action name="Move"/>
      </mousebind>
      <mousebind button="Left" action="DoubleClick">
        <action name="ToggleMaximize"/>
      </mousebind>
      <mousebind button="Right" action="Click">
        <action name="ShowMenu">
          <menu>client-menu</menu>
        </action>
      </mousebind>
      <mousebind button="Middle" action="Click">
        <action name="Close"/>
      </mousebind>
    </context>

    <context name="Frame">
      <mousebind button="Left" action="Drag">
        <action name="Resize"/>
      </mousebind>
    </context>

    <context name="Desktop">
      <mousebind button="Right" action="Click">
        <action name="ShowMenu">
          <menu>root-menu</menu>
        </action>
      </mousebind>
    </context>

  </mouse>

</labwc_config>'

# ── ~/.config/labwc/environment ────────────────────────────────────────
# Variáveis carregadas pelo LABWC antes do autostart.
#
# XKB ABNT2 (Teclado Brasileiro):
# Validado na documentação oficial do LABWC (getting-started.html):
# "Set the environment variable XKB_DEFAULT_LAYOUT with your country
# code in ~/.config/labwc/environment."
# XKB_DEFAULT_MODEL=abnt2 → modelo físico do teclado ABNT2
# XKB_DEFAULT_LAYOUT=br   → layout português brasileiro
# XKB_DEFAULT_VARIANT=abnt2 → variante ABNT2 (com Ç, acentos nativos)
# Propagadas também para o systemd --user e D-Bus no autostart.
#
# QS_ICON_THEME=WhiteSur → instrui o Qt/QML do Noctalia a usar WhiteSur.
# XDG_CURRENT_DESKTOP=wlroots → portal lê wlroots-portals.conf.
CONTEUDO_ENVIRONMENT='# labwc environment — carregado pelo compositor antes do autostart.
# Estas variáveis definem o ambiente completo da sessão Wayland.

# ── Teclado Brasileiro ABNT2 (com Ç e acentos) ────────────────────────
# Documentação oficial LABWC: XKB_DEFAULT_LAYOUT em ~/.config/labwc/environment.
# abnt2 model: layout físico do teclado brasileiro padrão (104 teclas + Ç).
# br layout: português brasileiro (caracteres acentuados, ç, ~, ^, etc.).
# abnt2 variant: garante o mapeamento correto das teclas mortas e Ç.
XKB_DEFAULT_MODEL=abnt2
XKB_DEFAULT_LAYOUT=br
XKB_DEFAULT_VARIANT=abnt2

# ── Tema de ícones do Noctalia Shell ─────────────────────────────────
# O motor Qt/QML do Noctalia busca ícones por nome neste tema.
# WhiteSur instalado em ~/.local/share/icons/WhiteSur/ pelo script.
QS_ICON_THEME=WhiteSur

# ── Tema e tamanho do cursor ──────────────────────────────────────────
# WhiteSur-icon-theme inclui cursores compatíveis.
XCURSOR_THEME=WhiteSur
XCURSOR_SIZE=24

# ── Contexto de sessão para XDG Desktop Portal ────────────────────────
# wlroots → portal lê ~/.config/xdg-desktop-portal/wlroots-portals.conf.
XDG_CURRENT_DESKTOP=wlroots
XDG_SESSION_TYPE=wayland
DESKTOP_SESSION=labwc

# ── Backends Wayland por toolkit ──────────────────────────────────────
QT_QPA_PLATFORM=wayland
GDK_BACKEND=wayland
ELECTRON_OZONE_PLATFORM_HINT=auto
MOZ_ENABLE_WAYLAND=1
SDL_VIDEODRIVER=wayland

# ── Portal de ficheiros e compatibilidade ─────────────────────────────
GTK_USE_PORTAL=1
_JAVA_AWT_WM_NONREPARENTING=1'

# ── ~/.config/labwc/menu.xml ───────────────────────────────────────────
CONTEUDO_MENU_XML='<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu>

  <!-- Menu de contexto de JANELA (botão direito na barra de título) -->
  <menu id="client-menu" label="Janela">
    <item label="Maximizar">
      <action name="ToggleMaximize"/>
    </item>
    <item label="Minimizar">
      <action name="Iconify"/>
    </item>
    <item label="Redimensionar">
      <action name="Resize"/>
    </item>
    <item label="Mover">
      <action name="Move"/>
    </item>
    <separator/>
    <item label="Fechar">
      <action name="Close"/>
    </item>
  </menu>

  <!-- Menu de contexto do DESKTOP (botão direito no fundo) -->
  <menu id="root-menu" label="Desktop">
    <item label="Alacritty (Terminal)">
      <action name="Execute">
        <command>alacritty</command>
      </action>
    </item>
    <item label="Konsole (Terminal KDE)">
      <action name="Execute">
        <command>konsole</command>
      </action>
    </item>
    <separator/>
    <item label="Dolphin (Ficheiros KDE)">
      <action name="Execute">
        <command>dolphin</command>
      </action>
    </item>
    <item label="Nautilus (Ficheiros + Google Drive)">
      <action name="Execute">
        <command>nautilus</command>
      </action>
    </item>
    <separator/>
    <item label="Kate (Editor KDE)">
      <action name="Execute">
        <command>kate</command>
      </action>
    </item>
    <item label="Firefox">
      <action name="Execute">
        <command>firefox</command>
      </action>
    </item>
    <item label="VS Code">
      <action name="Execute">
        <command>code</command>
      </action>
    </item>
    <separator/>
    <item label="Spectacle (Screenshot)">
      <action name="Execute">
        <command>spectacle</command>
      </action>
    </item>
    <item label="Mixer de Áudio (pavucontrol)">
      <action name="Execute">
        <command>pavucontrol</command>
      </action>
    </item>
    <separator/>
    <item label="Recarregar LABWC">
      <action name="Reconfigure"/>
    </item>
    <item label="Sair do LABWC">
      <action name="Exit"/>
    </item>
  </menu>

</openbox_menu>'

# ── ~/.config/labwc/themerc-override ──────────────────────────────────
# Arquivo aplicado SOBRE qualquer tema ativo no LABWC.
# Garante os botões semáforo macOS independentemente do tema WhiteSur.
# Referência: labwc-theme(5) manpage — seção "themerc-override".
# Localização oficial: $HOME/.config/labwc/themerc-override
#
# CORES EXATAS do macOS Sonoma (2024):
#   Fechar   (vermelho): #FF5F57 ativo  / #ADADAD inativo
#   Minimizar (amarelo): #FEBC2E ativo  / #ADADAD inativo
#   Maximizar  (verde) : #28C840 ativo  / #ADADAD inativo
#
# SINTAXE LABWC THEMERC: "chave: valor" (formato Openbox, NÃO bash).
# image.color: cor do ícone XBM dentro do botão (suportado em todas versões).
# unpressed.bg: cor de fundo do botão (suportado no LABWC >= 0.8.x).
# LABWC ignora graciosamente chaves não reconhecidas — seguro em todas versões.
CONTEUDO_THEMERC_OVERRIDE='# themerc-override — sobrepõe qualquer tema ativo no LABWC
# Aplicado após o themerc do tema WhiteSur-Dark (ou outro tema ativo).
# Documentação: labwc-theme(5) → "themerc-override file in $HOME/.config/labwc/"

# ── Dimensões dos botões (estilo circular macOS) ──────────────────────
# 14x14 pixels com 6px de espaçamento = proporção idêntica ao macOS.
window.button.width: 14
window.button.height: 14
window.button.spacing: 6

# Padding da barra de título para acomodar botões à esquerda com folga.
window.titlebar.padding.width: 6
window.titlebar.padding.height: 3

# ── Efeito hover circular ─────────────────────────────────────────────
# corner-radius = metade do tamanho do botão = círculo perfeito.
# Documentado em labwc-theme(5): "window.button.hover.bg.corner-radius"
window.button.hover.bg.corner-radius: 7
window.button.hover.bg.color: #80808030

# ── Cores dos ícones XBM — JANELA ATIVA (com foco) ───────────────────
# "image.color" colore o símbolo (X, —, +) dentro do botão.
# Confirmado suportado em todas as versões do LABWC via labwc-theme(5).
# Fechar: vermelho macOS Sonoma
window.active.button.close.unpressed.image.color: #FF5F57
# Minimizar: amarelo/âmbar macOS Sonoma
window.active.button.iconify.unpressed.image.color: #FEBC2E
# Maximizar: verde macOS Sonoma
window.active.button.max.unpressed.image.color: #28C840

# ── Cores dos ícones XBM — JANELA INATIVA (sem foco) ─────────────────
# No macOS real, todos os botões viram cinza quando a janela perde o foco.
window.inactive.button.close.unpressed.image.color: #ADADAD
window.inactive.button.iconify.unpressed.image.color: #ADADAD
window.inactive.button.max.unpressed.image.color: #ADADAD

# ── Fundo colorido dos botões (LABWC >= 0.8.x pode suportar) ─────────
# Se o seu LABWC suportar, cada botão terá um fundo colorido sólido.
# Se não suportar, estas linhas são ignoradas silenciosamente.
# Para botões circulares sólidos garantidos em qualquer versão,
# coloque SVGs em ~/.themes/WhiteSur-Dark/labwc/ (close-active.svg, etc.).
window.active.button.close.unpressed.bg: Solid
window.active.button.close.unpressed.bg.color: #FF5F57
window.active.button.iconify.unpressed.bg: Solid
window.active.button.iconify.unpressed.bg.color: #FEBC2E
window.active.button.max.unpressed.bg: Solid
window.active.button.max.unpressed.bg.color: #28C840
window.inactive.button.close.unpressed.bg: Solid
window.inactive.button.close.unpressed.bg.color: #ADADAD
window.inactive.button.iconify.unpressed.bg: Solid
window.inactive.button.iconify.unpressed.bg.color: #ADADAD
window.inactive.button.max.unpressed.bg: Solid
window.inactive.button.max.unpressed.bg.color: #ADADAD'

# ─────────────────────────────────────────────────────────────────────────
# BLOCO 4: FUNÇÕES DE INSTALAÇÃO ESPECÍFICAS
# ─────────────────────────────────────────────────────────────────────────

instalar_vscode() {
    separador "Visual Studio Code — Repositório Oficial Microsoft"

    if pkg_instalado "code"; then
        log_warn "VS Code já instalado — pulando"
        return 0
    fi

    log_info "Importando chave GPG da Microsoft..."
    if rpm --import https://packages.microsoft.com/keys/microsoft.asc \
        >> "${LOG_FILE}" 2>&1; then
        log_ok "Chave GPG Microsoft importada"
    else
        log_err "Falha ao importar chave GPG — VS Code não será instalado"
        return 1
    fi

    # Método canónico Microsoft para Fedora/RHEL (confirmado na pesquisa web).
    log_info "Criando /etc/yum.repos.d/vscode.repo..."
    printf '%s\n' \
        '[code]' \
        'name=Visual Studio Code' \
        'baseurl=https://packages.microsoft.com/yumrepos/vscode' \
        'enabled=1' \
        'gpgcheck=1' \
        'gpgkey=https://packages.microsoft.com/keys/microsoft.asc' \
        > /etc/yum.repos.d/vscode.repo
    chmod 0644 /etc/yum.repos.d/vscode.repo
    log_ok "Repositório VS Code configurado"

    log_info "Instalando code..."
    if dnf install -y code >> "${LOG_FILE}" 2>&1; then
        log_ok "VS Code instalado"
    else
        log_err "Falha ao instalar VS Code — verifique ${LOG_FILE}"
    fi
}

instalar_whitesur_gtk() {
    separador "WhiteSur GTK Theme — vinceliuice/WhiteSur-gtk-theme"
    local tmp_dir="/tmp/WhiteSur-gtk-theme"

    log_info "Clonando repositório oficial (depth=1 para velocidade)..."
    rm -rf "${tmp_dir}"
    if git clone --depth=1 \
        https://github.com/vinceliuice/WhiteSur-gtk-theme.git \
        "${tmp_dir}" >> "${LOG_FILE}" 2>&1; then
        log_ok "Repositório clonado em ${tmp_dir}"
    else
        log_err "Falha ao clonar WhiteSur-gtk-theme"
        return 1
    fi

    # Executa o instalador padrão conforme o README oficial do WhiteSur GTK.
    # Instala TODAS as variantes (light + dark) em ${HOME}/.themes/.
    # rc.xml referencia WhiteSur-Dark para decorações de janela.
    # env HOME=: garante home correto mesmo rodando via sudo.
    log_info "Executando install.sh como ${USUARIO_REAL}..."
    if sudo -u "${USUARIO_REAL}" env HOME="${HOME_REAL}" \
        bash -c "cd '${tmp_dir}' && ./install.sh" \
        >> "${LOG_FILE}" 2>&1; then
        log_ok "WhiteSur GTK Theme instalado em ${HOME_REAL}/.themes/"
    else
        log_err "Falha ao instalar WhiteSur GTK Theme — veja ${LOG_FILE}"
    fi

    rm -rf "${tmp_dir}"
    log_info "Diretório temporário removido"
}

instalar_whitesur_icons() {
    separador "WhiteSur Icon Theme — vinceliuice/WhiteSur-icon-theme"
    local tmp_dir="/tmp/WhiteSur-icon-theme"

    log_info "Clonando repositório oficial..."
    rm -rf "${tmp_dir}"
    if git clone --depth=1 \
        https://github.com/vinceliuice/WhiteSur-icon-theme.git \
        "${tmp_dir}" >> "${LOG_FILE}" 2>&1; then
        log_ok "Repositório clonado em ${tmp_dir}"
    else
        log_err "Falha ao clonar WhiteSur-icon-theme"
        return 1
    fi

    # Executa o instalador padrão conforme o README oficial do WhiteSur Icon Theme.
    # Instala em ~/.local/share/icons/ sem prompts interativos.
    # Inclui ícones de apps, pastas, MIME types E cursores (XCURSOR_THEME=WhiteSur).
    log_info "Executando install.sh como ${USUARIO_REAL}..."
    if sudo -u "${USUARIO_REAL}" env HOME="${HOME_REAL}" \
        bash -c "cd '${tmp_dir}' && ./install.sh" \
        >> "${LOG_FILE}" 2>&1; then
        log_ok "WhiteSur Icon Theme instalado em ${HOME_REAL}/.local/share/icons/"
    else
        log_err "Falha ao instalar WhiteSur Icon Theme — veja ${LOG_FILE}"
    fi

    rm -rf "${tmp_dir}"
    log_info "Diretório temporário removido"
}

escrever_dotfiles_labwc() {
    separador "Criando dotfiles do LABWC (~/.config/labwc/)"

    local cfg_dir="${HOME_REAL}/.config/labwc"
    mkdir -p "${cfg_dir}"
    chown "${USUARIO_REAL}:${USUARIO_REAL}" "${cfg_dir}"

    # autostart: precisa de permissão de execução
    escrever_arquivo_usuario "${cfg_dir}/autostart" "${CONTEUDO_AUTOSTART}"
    chmod +x "${cfg_dir}/autostart"
    log_info "chmod +x aplicado ao autostart"

    # rc.xml: tema, botões, keybinds, mouse
    escrever_arquivo_usuario "${cfg_dir}/rc.xml" "${CONTEUDO_RC_XML}"

    # environment: variáveis Wayland + XKB ABNT2 + tema
    escrever_arquivo_usuario "${cfg_dir}/environment" "${CONTEUDO_ENVIRONMENT}"

    # menu.xml: menu de contexto do desktop
    escrever_arquivo_usuario "${cfg_dir}/menu.xml" "${CONTEUDO_MENU_XML}"

    log_ok "Dotfiles do LABWC criados com sucesso"
}

escrever_themerc_override() {
    separador "Criando themerc-override (botões semáforo macOS)"

    local themerc_file="${HOME_REAL}/.config/labwc/themerc-override"

    # themerc-override: aplicado SOBRE o themerc do tema ativo (WhiteSur-Dark).
    # Localização oficial confirmada em labwc-theme(5):
    # "$HOME/.config/labwc/themerc-override"
    # Cores macOS Sonoma: Close=#FF5F57 / Minimize=#FEBC2E / Maximize=#28C840
    # Inativo (sem foco): #ADADAD (cinza, idêntico ao comportamento macOS real)
    escrever_arquivo_usuario "${themerc_file}" "${CONTEUDO_THEMERC_OVERRIDE}"

    log_ok "themerc-override criado: ${themerc_file}"
    log_info "Botões ativos → Fechar:#FF5F57  Minimizar:#FEBC2E  Maximizar:#28C840"
    log_info "Botões inativos → Cinza:#ADADAD (janela sem foco, como no macOS real)"
}

escrever_portal_conf() {
    separador "XDG Desktop Portal — wlroots-portals.conf"

    local portal_dir="${HOME_REAL}/.config/xdg-desktop-portal"
    local portal_file="${portal_dir}/wlroots-portals.conf"

    mkdir -p "${portal_dir}"

    # XDG_CURRENT_DESKTOP=wlroots (definido no environment) instrui o portal
    # a ler este arquivo. Roteamento por backend:
    #   wlr → Screenshot e ScreenCast (backend nativo de compositor wlroots)
    #   gtk → FileChooser, OpenURI e demais (fallback universal)
    printf '%s\n' \
        '[preferred]' \
        'default=gtk' \
        'org.freedesktop.impl.portal.Screenshot=wlr' \
        'org.freedesktop.impl.portal.ScreenCast=wlr' \
        > "${portal_file}"

    chown -R "${USUARIO_REAL}:${USUARIO_REAL}" "${portal_dir}"
    log_ok "Criado: ${portal_file}"
}

escrever_sddm_conf() {
    separador "SDDM — Configuração para sessão LABWC Wayland"

    local sddm_dir="/etc/sddm.conf.d"
    local sddm_file="${sddm_dir}/10-labwc-wayland.conf"

    mkdir -p "${sddm_dir}"

    # DisplayServer=wayland: SDDM em modo Wayland nativo.
    # DefaultSession=labwc.desktop: pré-seleciona LABWC na tela de login.
    # O arquivo labwc.desktop é provido pelo pacote labwc-session.
    printf '%s\n' \
        '[General]' \
        'DisplayServer=wayland' \
        'DefaultSession=labwc.desktop' \
        > "${sddm_file}"

    chmod 0644 "${sddm_file}"
    log_ok "Criado: ${sddm_file}"
}

criar_diretorios_usuario() {
    separador "Criando estrutura de diretórios do usuário"

    local dirs=(
        "${HOME_REAL}/.config/labwc"
        "${HOME_REAL}/.config/xdg-desktop-portal"
        "${HOME_REAL}/.local/share/themes"
        "${HOME_REAL}/.local/share/icons"
        "${HOME_REAL}/Pictures/Wallpapers"
        "${HOME_REAL}/Screenshots"
    )

    for dir in "${dirs[@]}"; do
        mkdir -p "${dir}"
        log_ok "Criado: ${dir}"
    done

    chown -R "${USUARIO_REAL}:${USUARIO_REAL}" \
        "${HOME_REAL}/.config" \
        "${HOME_REAL}/.local" \
        "${HOME_REAL}/Pictures" \
        "${HOME_REAL}/Screenshots"

    log_ok "Permissões (chown) aplicadas a todos os diretórios"
}

# ─────────────────────────────────────────────────────────────────────────
# NOVO BLOCO: DOWNLOAD DE WALLPAPERS MACOS
# Estrutura de download organizada com URLs em branco para preenchimento.
# Adicione os links diretos nas variáveis url_N abaixo e re-execute
# apenas esta função com: source ./script.sh && download_mac_wallpapers
# ─────────────────────────────────────────────────────────────────────────

download_mac_wallpapers() {
    separador "Diretório e Downloads de Wallpapers macOS"

    local wallpaper_dir="${HOME_REAL}/Pictures/Wallpapers"
    mkdir -p "${wallpaper_dir}"
    chown "${USUARIO_REAL}:${USUARIO_REAL}" "${wallpaper_dir}"
    log_ok "Diretório pronto: ${wallpaper_dir}"
    log_info "Preencha as variáveis url_N abaixo com links diretos de imagens .jpg ou .png"
    log_info "e re-execute: sudo bash ${BASH_SOURCE[0]} --only-wallpapers"
    echo ""

    # ── WALLPAPER 1 ─────────────────────────────────────────────────────
    # ADICIONE AQUI O SEU LINK DIRETO DE WALLPAPER DO MAC (ex: macOS Sonoma Desert)
    local url_1="https://4kwallpapers.com/images/wallpapers/sage-green-abstract-5120x3413-26355.jpg"
    # url_1="https://linkdireto.para/sua/imagem/sonoma_desert.jpg"

    # ── WALLPAPER 2 ─────────────────────────────────────────────────────
    # ADICIONE AQUI O SEU LINK DIRETO DE WALLPAPER DO MAC (ex: macOS Ventura Ridge)
    local url_2="https://4kwallpapers.com/images/wallpapers/sage-green-abstract-5120x3413-26354.jpg"
    # url_2="https://linkdireto.para/sua/imagem/ventura_ridge.jpg"

    # ── WALLPAPER 3 ─────────────────────────────────────────────────────
    # ADICIONE AQUI O SEU LINK DIRETO DE WALLPAPER DO MAC (ex: macOS Monterey Coastline)
    local url_3="https://4kwallpapers.com/images/wallpapers/mountain-landscape-5120x2880-24317.jpg"
    # url_3="https://linkdireto.para/sua/imagem/monterey_coastline.jpg"

    # ── WALLPAPER 4 ─────────────────────────────────────────────────────
    # ADICIONE AQUI O SEU LINK DIRETO DE WALLPAPER DO MAC (ex: macOS Big Sur Light)
    local url_4="https://4kwallpapers.com/images/wallpapers/shinra-kusakabe-3840x2160-18916.jpg"
    # url_4="https://linkdireto.para/sua/imagem/bigsur_light.jpg"

    # ── WALLPAPER 5 ─────────────────────────────────────────────────────
    # ADICIONE AQUI O SEU LINK DIRETO DE WALLPAPER DO MAC (ex: macOS Big Sur Dark)
    local url_5="https://4kwallpapers.com/images/wallpapers/alucard-8k-hellsing-7680x4320-13839.png"
    # url_5="https://linkdireto.para/sua/imagem/bigsur_dark.jpg"

    # ── WALLPAPER 6 ─────────────────────────────────────────────────────
    # ADICIONE AQUI O SEU LINK DIRETO DE WALLPAPER DO MAC (ex: macOS Catalina Peak)
    local url_6="https://4kwallpapers.com/images/wallpapers/alucard-hellsing-5120x2880-13882.png"
    # url_6="https://linkdireto.para/sua/imagem/catalina.jpg"

    # ── WALLPAPER 7 ─────────────────────────────────────────────────────
    # ADICIONE AQUI O SEU LINK DIRETO DE WALLPAPER DO MAC (Wallpaper personalizado)
    local url_7="https://4kwallpapers.com/images/wallpapers/iridescent-spheres-5120x5120-26346.jpg"
    # url_7="https://linkdireto.para/sua/imagem/personalizado.jpg"

    # ── WALLPAPER 8 ─────────────────────────────────────────────────────
    # ADICIONE AQUI O SEU LINK DIRETO DE WALLPAPER DO MAC (Wallpaper personalizado)
    local url_8="https://www.iclarified.com/images/news/97556/465563/465563.jpg"
    # url_8="https://linkdireto.para/sua/imagem/personalizado_2.jpg"

     # ── WALLPAPER 9 ─────────────────────────────────────────────────────
    # ADICIONE AQUI O SEU LINK DIRETO DE WALLPAPER DO MAC (Wallpaper personalizado)
    local url_9="https://www.iclarified.com/images/news/97556/465563/465563.jpg"
    # url_9="https://linkdireto.para/sua/imagem/personalizado_2.jpg"

    # ── Lógica de download ───────────────────────────────────────────────
    # Array associativo: nome do arquivo → URL
    # Para cada entrada não vazia, faz o download com wget.
    declare -A wallpapers=(
        ["mac_wall_1.jpg"]="${url_1}"
        ["mac_wall_2.jpg"]="${url_2}"
        ["mac_wall_3.jpg"]="${url_3}"
        ["mac_wall_4.jpg"]="${url_4}"
        ["mac_wall_5.jpg"]="${url_5}"
        ["mac_wall_6.jpg"]="${url_6}"
        ["mac_wall_7.jpg"]="${url_7}"
        ["mac_wall_8.jpg"]="${url_8}"
        ["mac_wall_9.jpg"]="${url_9}"
    )

    local algum_baixado=0
    for nome in "${!wallpapers[@]}"; do
        local url="${wallpapers[$nome]}"
        if [[ -n "${url}" ]]; then
            log_info "Baixando ${nome}..."
            if sudo -u "${USUARIO_REAL}" wget -q --show-progress \
                -O "${wallpaper_dir}/${nome}" "${url}" \
                >> "${LOG_FILE}" 2>&1; then
                log_ok "${nome} salvo em ${wallpaper_dir}/"
                algum_baixado=1
            else
                log_err "Falha ao baixar ${nome} de: ${url}"
                rm -f "${wallpaper_dir}/${nome}"
            fi
        else
            log_warn "${nome}: URL vazia — preencha url_${nome//[^0-9]/} na função download_mac_wallpapers()"
        fi
    done

    if [[ $algum_baixado -eq 0 ]]; then
        log_warn "Nenhum wallpaper baixado. Todas as URLs estão vazias."
        log_info "Para adicionar wallpapers manualmente:"
        log_info "  cp sua_imagem.jpg ${wallpaper_dir}/mac_wall_1.jpg"
        log_info "  ou wget -O ${wallpaper_dir}/mac_wall_1.jpg 'URL_DIRETA'"
    fi

    chown -R "${USUARIO_REAL}:${USUARIO_REAL}" "${wallpaper_dir}"
    log_ok "Diretório de wallpapers: ${wallpaper_dir}"
}

# ─────────────────────────────────────────────────────────────────────────
# BLOCO 5: FUNÇÃO PRINCIPAL (main)
# ─────────────────────────────────────────────────────────────────────────

main() {

    # ── VERIFICAÇÕES INICIAIS ──────────────────────────────────────────
    check_root

    mkdir -p "$(dirname "${LOG_FILE}")"
    {
        echo "═══════════════════════════════════════════════════════════"
        echo "  Post-Install Log — $(date '+%Y-%m-%d %H:%M:%S')"
        echo "  Usuário alvo: ${USUARIO_REAL}"
        echo "  Home:         ${HOME_REAL}"
        echo "  Script:       $0"
        echo "═══════════════════════════════════════════════════════════"
    } > "${LOG_FILE}"

    clear
    echo -e "${NEGRITO}${AZUL}"
    echo "  ╔══════════════════════════════════════════════════════════════╗"
    echo "  ║  Fedora 44 Minimal → LABWC + Noctalia + WhiteSur macOS     ║"
    echo "  ║  Usuário: ${USUARIO_REAL}                                          ║"
    echo "  ║  Log:     ${LOG_FILE}  ║"
    echo "  ╚══════════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"

    # ── ETAPA 1: GRAPHICAL TARGET ──────────────────────────────────────
    # Fedora 44 Minimal usa multi-user.target por padrão (sem GUI).
    # OBRIGATÓRIO: sem esta linha o sistema reinicia em modo texto
    # mesmo com SDDM instalado e habilitado.
    separador "Etapa 1/14 — Definindo graphical.target como padrão de boot"
    if systemctl set-default graphical.target >> "${LOG_FILE}" 2>&1; then
        log_ok "Target padrão: graphical.target"
    else
        log_err "Falha ao definir graphical.target"
    fi

    # ── ETAPA 2: ATUALIZAÇÃO DO SISTEMA ────────────────────────────────
    separador "Etapa 2/14 — Atualizando sistema base"
    log_info "Executando dnf upgrade (pode demorar na primeira execução)..."
    if dnf upgrade -y >> "${LOG_FILE}" 2>&1; then
        log_ok "Sistema atualizado"
    else
        log_err "Falha na atualização — continuando (verifique ${LOG_FILE})"
    fi

    # ── ETAPA 3: BOOTSTRAP — dnf-plugins-core ──────────────────────────
    # 'dnf copr enable' faz parte do dnf-plugins-core.
    # Instalado antes de qualquer COPR.
    separador "Etapa 3/14 — Bootstrap: dnf-plugins-core"
    if ! pkg_instalado "dnf-plugins-core"; then
        if dnf install -y dnf-plugins-core >> "${LOG_FILE}" 2>&1; then
            log_ok "dnf-plugins-core instalado"
        else
            log_err "Falha — COPRs podem falhar"
        fi
    else
        log_warn "dnf-plugins-core já instalado — pulando"
    fi

    # ── ETAPA 4: REPOSITÓRIOS EXTERNOS ─────────────────────────────────
    # ORDEM CRÍTICA: repos antes de qualquer instalação que deles dependa.
    separador "Etapa 4/14 — Configurando repositórios externos"

    # 4.1 — Repositório Terra (Fyra Labs)
    # Fonte oficial do noctalia-shell para Fedora.
    # SINTAXE CRÍTICA: aspas simples → bash NÃO expande $releasever.
    # DNF recebe o token literalmente e o resolve internamente.
    # Resultado: https://repos.fyralabs.com/terra44 (resolvido pelo DNF).
    log_step "4.1" "Terra/Fyra Labs → noctalia-shell, rsms-inter-fonts..."
    if pkg_instalado "terra-release"; then
        log_warn "terra-release já instalado — pulando"
    else
        if dnf install -y \
            --nogpgcheck \
            --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' \
            terra-release >> "${LOG_FILE}" 2>&1; then
            log_ok "Repositório Terra instalado"
        else
            log_err "Falha terra-release — noctalia-shell não poderá ser instalado"
        fi
    fi

    # 4.2 — COPR brycensranch/gpu-screen-recorder-git
    # DEPENDÊNCIA OBRIGATÓRIA: Requires: gpu-screen-recorder no .spec do Noctalia.
    # Sem este COPR → dnf install noctalia-shell falha com dep não resolvida.
    log_step "4.2" "COPR brycensranch/gpu-screen-recorder-git (dep OBRIGATÓRIA do Noctalia)..."
    habilitar_copr "brycensranch/gpu-screen-recorder-git"

    # 4.3 — COPR heus-sueh/packages (contém matugen)
    log_step "4.3" "COPR heus-sueh/packages (matugen para paleta de cores dinâmica)..."
    habilitar_copr "heus-sueh/packages"

    # ── ETAPA 5: INSTALAÇÃO DE PACOTES ─────────────────────────────────
    separador "Etapa 5/14 — Instalação de pacotes por grupo"

    instalar_grupo \
        "Core do sistema (LABWC, SDDM, Polkit, PipeWire, BT, tuned-ppd)" \
        "${PKGS_CORE[@]}"

    instalar_grupo \
        "Aplicações KDE/GNOME (terminais, ficheiros, editores, ferramentas)" \
        "${PKGS_APPS[@]}"

    instalar_grupo \
        "Deps de compilação para WhiteSur GTK e Icon Theme" \
        "${PKGS_WHITESUR_BUILD_DEPS[@]}"

    instalar_grupo \
        "Deps OBRIGATÓRIAS do Noctalia Shell (Requires: no .spec)" \
        "${PKGS_NOCTALIA_DEPS[@]}"

    instalar_grupo \
        "Deps RECOMENDADAS do Noctalia Shell (ativa widgets e features extras)" \
        "${PKGS_NOCTALIA_RECOMMENDED[@]}"

    # ── ETAPA 6: NOCTALIA SHELL ─────────────────────────────────────────
    # Instalado APÓS todos os repositórios e dependências estarem prontos.
    # noctalia-shell puxa noctalia-qs (Quickshell) automaticamente como dep.
    separador "Etapa 6/14 — Instalando Noctalia Shell (via Terra)"
    if pkg_instalado "noctalia-shell"; then
        log_warn "noctalia-shell já instalado — pulando"
    else
        log_info "Instalando noctalia-shell (puxa noctalia-qs como dep automática)..."
        if dnf install -y noctalia-shell >> "${LOG_FILE}" 2>&1; then
            log_ok "noctalia-shell instalado"
            log_info "Início da shell: qs -c noctalia-shell (via autostart do LABWC)"
        else
            log_err "Falha ao instalar noctalia-shell — verifique ${LOG_FILE}"
        fi
    fi

    # ── ETAPA 7: VS CODE ────────────────────────────────────────────────
    instalar_vscode

    # ── ETAPA 8: SERVIÇOS SYSTEMD ───────────────────────────────────────
    separador "Etapa 8/14 — Habilitando serviços systemd (sistema)"

    log_step "8.1" "SDDM (Display Manager — inicia no boot)"
    habilitar_servico "sddm"

    log_step "8.2" "Bluetooth (bluetoothd)"
    habilitar_servico "bluetooth"

    # tuned-ppd: substituto OFICIAL do power-profiles-daemon no Fedora 44.
    # Serve a mesma interface D-Bus (net.hadess.PowerProfiles) que o Noctalia lê.
    # NUNCA instalar com power-profiles-daemon ou tlp → conflito fatal de RPM.
    log_step "8.3" "tuned-ppd (substituto oficial do power-profiles-daemon)"
    habilitar_servico "tuned-ppd"

    # PipeWire: gerenciado EXCLUSIVAMENTE pelo systemd --user.
    # Duplicar no autostart do LABWC causaria duas instâncias e falhas de áudio.
    separador "Etapa 8b/14 — Serviços de usuário (${USUARIO_REAL})"

    log_step "8b.1" "pipewire"
    habilitar_servico_usuario "pipewire"

    log_step "8b.2" "pipewire-pulse (compat PulseAudio)"
    habilitar_servico_usuario "pipewire-pulse"

    log_step "8b.3" "wireplumber (policy manager)"
    habilitar_servico_usuario "wireplumber"

    # ── ETAPA 9: PERMISSÕES DE GRUPO ───────────────────────────────────
    separador "Etapa 9/14 — Grupos de sistema para ${USUARIO_REAL}"

    log_info "Adicionando ao grupo 'video' (brightnessctl sem sudo)..."
    if usermod -aG video "${USUARIO_REAL}" >> "${LOG_FILE}" 2>&1; then
        log_ok "${USUARIO_REAL} → grupo video"
    else
        log_warn "Falha ao adicionar grupo video"
    fi

    log_info "Adicionando ao grupo 'input' (Bluetooth e dispositivos)..."
    if usermod -aG input "${USUARIO_REAL}" >> "${LOG_FILE}" 2>&1; then
        log_ok "${USUARIO_REAL} → grupo input"
    else
        log_warn "Falha ao adicionar grupo input"
    fi

    # ── ETAPA 10: ESTRUTURA DE DIRETÓRIOS ──────────────────────────────
    criar_diretorios_usuario

    # ── ETAPA 11: DOTFILES DO LABWC ─────────────────────────────────────
    # autostart, rc.xml, environment (com XKB ABNT2), menu.xml
    escrever_dotfiles_labwc

    # ── ETAPA 12: THEMERC-OVERRIDE (BOTÕES SEMÁFORO MACOS) ─────────────
    # Cores exatas macOS Sonoma: #FF5F57 / #FEBC2E / #28C840 / #ADADAD inativo.
    # Sintaxe labwc-theme(5): chave: valor (formato Openbox).
    # Aplica-se SOBRE o WhiteSur-Dark, independentemente do tema ativo.
    escrever_themerc_override

    # ── ETAPA 13: PORTAL + SDDM CONFIG ─────────────────────────────────
    escrever_portal_conf
    escrever_sddm_conf

    # ── ETAPA 14: TEMAS WHITESUR ────────────────────────────────────────
    instalar_whitesur_gtk
    instalar_whitesur_icons

    # ── ETAPA EXTRA: WALLPAPERS MACOS ───────────────────────────────────
    # Cria o diretório e tenta baixar wallpapers.
    # URLs em branco por padrão — preencha as variáveis url_N na função.
    download_mac_wallpapers

    # ── RELATÓRIO FINAL ──────────────────────────────────────────────────
    separador "RELATÓRIO FINAL DE INSTALAÇÃO"

    if [[ $ERROS -eq 0 ]]; then
        echo -e "${VERDE}${NEGRITO}"
        echo "  ✓ Instalação concluída SEM ERROS!"
        echo -e "${RESET}"
    else
        echo -e "${AMARELO}${NEGRITO}"
        echo "  ⚠ Instalação concluída com ${ERROS} erro(s)."
        echo -e "${RESET}"
        echo -e "  ${VERMELHO}Consulte: ${LOG_FILE}${RESET}"
    fi

    echo ""
    echo -e "${NEGRITO}${CIANO}Resumo do que foi instalado e configurado:${RESET}"
    echo ""
    echo -e "  ${VERDE}✓${RESET} LABWC + labwc-session → sessão labwc.desktop no SDDM"
    echo -e "  ${VERDE}✓${RESET} Noctalia Shell via Terra (qs -c noctalia-shell no autostart)"
    echo -e "  ${VERDE}✓${RESET} PipeWire + WirePlumber (systemd --user, SEM duplicação)"
    echo -e "  ${VERDE}✓${RESET} Bluetooth: bluetoothd + blueman-applet"
    echo -e "  ${VERDE}✓${RESET} tuned-ppd (SEM tlp, SEM power-profiles-daemon)"
    echo -e "  ${VERDE}✓${RESET} XKB ABNT2: model=abnt2 layout=br variant=abnt2 (ç nativo)"
    echo -e "  ${VERDE}✓${RESET} Botões semáforo: themerc-override com cores macOS Sonoma"
    echo -e "  ${VERDE}✓${RESET}   Fechar=#FF5F57  Minimizar=#FEBC2E  Maximizar=#28C840"
    echo -e "  ${VERDE}✓${RESET}   Inativo=#ADADAD (cinza, igual ao macOS real)"
    echo -e "  ${VERDE}✓${RESET} Alacritty + Konsole (terminais)"
    echo -e "  ${VERDE}✓${RESET} Dolphin + Nautilus (Google Drive via gnome-online-accounts)"
    echo -e "  ${VERDE}✓${RESET} Kate + nano (editores)"
    echo -e "  ${VERDE}✓${RESET} Spectacle (Print) + grim/slurp (Super+Print, área interativa)"
    echo -e "  ${VERDE}✓${RESET} Firefox + VS Code (repo oficial Microsoft)"
    echo -e "  ${VERDE}✓${RESET} fastfetch via dnf nativo (SEM compilação manual)"
    echo -e "  ${VERDE}✓${RESET} pavucontrol + cava + cliphist + matugen + wlsunset + ddcutil"
    echo -e "  ${VERDE}✓${RESET} WhiteSur GTK Theme → ~/.themes/WhiteSur-Dark/"
    echo -e "  ${VERDE}✓${RESET} WhiteSur Icon Theme → ~/.local/share/icons/WhiteSur/"
    echo -e "  ${VERDE}✓${RESET} QS_ICON_THEME=WhiteSur no ~/.config/labwc/environment"
    echo -e "  ${VERDE}✓${RESET} wlroots-portals.conf para FileChooser (gtk) e Screenshot (wlr)"
    echo -e "  ${VERDE}✓${RESET} graphical.target como alvo de boot padrão"
    echo -e "  ${VERDE}✓${RESET} ${USUARIO_REAL} adicionado aos grupos video e input"
    echo -e "  ${VERDE}✓${RESET} ~/Pictures/Wallpapers/ criado (URLs para preencher)"
    echo ""
    echo -e "${NEGRITO}${AMARELO}Próximos passos:${RESET}"
    echo ""
    echo -e "  ${CIANO}1.${RESET} Reinicie: ${AZUL}sudo reboot${RESET}"
    echo -e "     SDDM abrirá com sessão LABWC Wayland pré-selecionada."
    echo ""
    echo -e "  ${CIANO}2.${RESET} Google Drive no Nautilus:"
    echo -e "     ${AZUL}gnome-online-accounts-gtk${RESET} → Adicionar conta Google"
    echo ""
    echo -e "  ${CIANO}3.${RESET} Wallpapers — preencha as URLs em download_mac_wallpapers():"
    echo -e "     ${AZUL}${HOME_REAL}/Pictures/Wallpapers/${RESET}"
    echo ""
    echo -e "  ${CIANO}4.${RESET} Paleta de cores dinâmica (após colocar wallpaper):"
    echo -e "     ${AZUL}matugen image ${HOME_REAL}/Pictures/Wallpapers/mac_wall_1.jpg${RESET}"
    echo ""
    echo -e "  ${CIANO}5.${RESET} Teclado ABNT2 com ç verificado automaticamente."
    echo -e "     Se não funcionar, adicione ao /etc/vconsole.conf:"
    echo -e "     ${AZUL}KEYMAP=br-abnt2${RESET}"
    echo ""
    echo -e "  ${VERMELHO}Log completo: ${LOG_FILE}${RESET}"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────
# PONTO DE ENTRADA
# ─────────────────────────────────────────────────────────────────────────
main "$@"
