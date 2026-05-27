#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║  post-install.sh  —  Fedora 44 Minimal → labwc + Noctalia v4    ║
# ║  Uso: sudo ./post-install.sh                                     ║
# ║                                                                  ║
# ║  Fontes validadas:                                               ║
# ║  - docs.noctalia.dev/v4/getting-started/installation/           ║
# ║  - developer.fyralabs.com/terra/installing                       ║
# ║  - noctalia-shell.spec (Terra/COPR build)                        ║
# ║  - copr.fedorainfracloud.org/coprs/brycensranch/gpu-screen-…    ║
# ╚══════════════════════════════════════════════════════════════════╝

# ─────────────────────────────────────────────────────────────────────
# BLOCO 0: CONFIGURAÇÃO GLOBAL
# ─────────────────────────────────────────────────────────────────────

# Cores ANSI — definidas como readonly para proteção contra sobrescrita
readonly VERDE="\e[32m"
readonly VERMELHO="\e[31m"
readonly AMARELO="\e[33m"
readonly AZUL="\e[34m"
readonly CIANO="\e[36m"
readonly NEGRITO="\e[1m"
readonly RESET="\e[0m"

readonly LOG_FILE="/var/log/post-install-labwc.log"

# Contador global de erros não-fatais
ERROS=0

# Usuário real: SUDO_USER é setado pelo sudo automaticamente.
# A forma ${VAR:-fallback} usa fallback se VAR estiver vazia/indefinida.
readonly USUARIO_REAL="${SUDO_USER:-$USER}"
readonly HOME_REAL="/home/${USUARIO_REAL}"

# ─────────────────────────────────────────────────────────────────────
# BLOCO 1: FUNÇÕES UTILITÁRIAS
# ─────────────────────────────────────────────────────────────────────

log_ok()   { echo -e "${VERDE}${NEGRITO}  ✓${RESET}  $1"; }
log_err()  { echo -e "${VERMELHO}${NEGRITO}  ✗ ERRO:${RESET} $1" | tee -a "${LOG_FILE}"; ((ERROS++)); }
log_info() { echo -e "${AZUL}${NEGRITO}  →${RESET}  $1"; }
log_warn() { echo -e "${AMARELO}${NEGRITO}  ⚠${RESET}  $1"; }
log_step() { echo -e "${CIANO}${NEGRITO}  [$1]${RESET} $2"; }

separador() {
    echo ""
    echo -e "${AZUL}${NEGRITO}══════════════════════════════════════════════════${RESET}"
    echo -e "${AZUL}${NEGRITO}  $1${RESET}"
    echo -e "${AZUL}${NEGRITO}══════════════════════════════════════════════════${RESET}"
    echo ""
}

# Verifica se está rodando como root (EUID 0 = root)
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${VERMELHO}${NEGRITO}ERRO: execute como root → sudo $0${RESET}"
        exit 1
    fi
}

# Verifica se um pacote já está instalado — evita reinstalar o que já existe.
# rpm -q retorna 0 se instalado, 1 se não.
pkg_instalado() {
    rpm -q "$1" &>/dev/null
}

# Instala um único pacote com verificação de resultado.
# Redireciona saída bruta pro log; só exibe status limpo no terminal.
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
        log_err "Falha ao instalar: ${pkg}"
        return 1
    fi
}

# Instala um grupo de pacotes iterando sobre um array.
# Uso: instalar_grupo "Rótulo do Grupo" "${ARRAY[@]}"
#
# CONCEITO: 'shift' descarta o primeiro argumento ($1 = rótulo).
# Depois, "$@" contém só os pacotes. local pacotes=("$@") copia
# pra um array local com segurança contra espaços em nomes.
instalar_grupo() {
    local rotulo="$1"
    shift
    local pacotes=("$@")
    separador "Instalando: ${rotulo}"
    for pkg in "${pacotes[@]}"; do
        instalar_pacote "$pkg"
    done
}

# Habilita um serviço systemd no escopo de sistema (root)
habilitar_servico() {
    local svc="$1"
    log_info "Habilitando serviço: ${svc}"
    if systemctl enable "$svc" >> "${LOG_FILE}" 2>&1; then
        log_ok "${svc} habilitado"
    else
        log_err "Falha ao habilitar ${svc}"
    fi
}

# Habilita um serviço no escopo do USUÁRIO real (não root).
# Serviços de usuário rodam com --user: cada usuário tem sua própria
# instância do systemd, separada da instância root.
habilitar_servico_usuario() {
    local svc="$1"
    log_info "Serviço de usuário: ${svc} → ${USUARIO_REAL}"
    if sudo -u "${USUARIO_REAL}" \
        XDG_RUNTIME_DIR="/run/user/$(id -u ${USUARIO_REAL})" \
        systemctl --user enable "$svc" >> "${LOG_FILE}" 2>&1; then
        log_ok "${svc} habilitado para ${USUARIO_REAL}"
    else
        log_err "Falha: ${svc} para ${USUARIO_REAL}"
    fi
}

# Adiciona um repositório COPR com verificação de falha.
# O flag -y assume "yes" para a confirmação do dnf copr enable.
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

# Escreve um arquivo de texto como o usuário real (não root).
# Usa heredoc — forma de escrever conteúdo multi-linha sem
# enfileirar dezenas de echo. As aspas simples em 'EOF' impedem
# que o bash interpole variáveis dentro do bloco.
escrever_arquivo_usuario() {
    local destino="$1"
    local conteudo="$2"
    local dir
    dir="$(dirname "${destino}")"

    mkdir -p "$dir"
    echo "${conteudo}" > "${destino}"
    chown -R "${USUARIO_REAL}:${USUARIO_REAL}" "$dir"
    log_ok "Arquivo criado: ${destino}"
}

# ─────────────────────────────────────────────────────────────────────
# BLOCO 2: LISTAS DE PACOTES
#
# Cada array representa um grupo lógico. Separar assim permite
# comentar um grupo inteiro sem tocar nos outros, e facilita
# manutenção futura (adicionar/remover pacotes = mudar só o array).
# ─────────────────────────────────────────────────────────────────────

# Compositor Wayland + dependências de renderização
# labwc-session instala /usr/share/wayland-sessions/labwc.desktop
# — necessário para o SDDM exibir a sessão no seletor de login.
PKGS_WAYLAND=(
    "labwc"
    "labwc-session"
    "wlroots"
    "mesa-dri-drivers"
    "xdg-desktop-portal-wlr"
    "libinput"
)

# Display Manager (SDDM) + agente de autenticação Polkit (LXQt)
# lxqt-policykit = agente leve que mostra diálogos de senha root em GUI
PKGS_DM_POLKIT=(
    "sddm"
    "lxqt-policykit"
)

# Stack de áudio moderna (PipeWire substitui PulseAudio/JACK)
# wireplumber = policy manager, gerencia streams e dispositivos
# pipewire-pulseaudio = compatibilidade com apps que ainda usam PulseAudio API
# pavucontrol = mixer gráfico para controle fino de volumes e perfis de codec
PKGS_AUDIO=(
    "pipewire"
    "pipewire-pulseaudio"
    "wireplumber"
    "pavucontrol"
)

# Bluetooth: BlueZ = daemon + stack; Blueman = applet GTK para tray/gerenciamento
PKGS_BLUETOOTH=(
    "bluez"
    "blueman"
)

# Gestão de energia: tlp para bateria/CPU, power-profiles-daemon para seletor
# de perfis (integrado com o painel do Noctalia), brightnessctl para brilho via CLI
PKGS_ENERGIA=(
    "tlp"
    "power-profiles-daemon"
    "brightnessctl"
)

# Montagem automática de USB:
# udisks2 = daemon D-Bus para API de discos (geralmente já instalado)
# udiskie = cliente Python que monitora udev e monta dispositivos automaticamente
PKGS_DISCO=(
    "udisks2"
    "udiskie"
)

# ─────────────────────────────────────────────────────────────────────
# Dependências OBRIGATÓRIAS do noctalia-shell (extraídas do .spec file)
# Estes pacotes são Requires: no RPM — sem eles o noctalia não inicia.
# gpu-screen-recorder vem do COPR brycensranch/gpu-screen-recorder-git
# rsms-inter-fonts (fonte Inter) vem do repositório Terra (Fyra Labs)
# ─────────────────────────────────────────────────────────────────────
PKGS_NOCTALIA_DEPS=(
    "brightnessctl"
    "dejavu-sans-fonts"
    "google-roboto-fonts"
    "gpu-screen-recorder"
    "rsms-inter-fonts"
)

# Dependências RECOMENDADAS do noctalia-shell (Recommends: no .spec)
# São opcionais mas ativam funcionalidades extras da shell:
# cava       = visualizador de áudio para o widget de música
# cliphist   = histórico de clipboard (Ctrl+V avançado)
# matugen    = geração automática de paleta de cores a partir do wallpaper
# wlsunset   = ajuste de temperatura de cor (modo noturno/blue light filter)
# ddcutil    = controle de brilho em monitores externos via DDC/CI
PKGS_NOCTALIA_RECOMENDADOS=(
    "cava"
    "cliphist"
    "matugen"
    "wlsunset"
)

# ─────────────────────────────────────────────────────────────────────
# BLOCO 3: CONTEÚDO DOS DOTFILES
#
# Strings multi-linha que serão escritas como arquivos de configuração.
# Separar conteúdo do código de escrita deixa o main() mais limpo.
# ─────────────────────────────────────────────────────────────────────

# ~/.config/labwc/autostart
# Este arquivo é executado pelo labwc na inicialização da sessão.
# Cada linha é um comando rodado em background (&) para não bloquear.
CONTEUDO_AUTOSTART='#!/usr/bin/env bash
# labwc autostart — executado a cada início de sessão

# Agente Polkit: exibe diálogos de autenticação root
/usr/libexec/polkit-qt-authentication-agent-1 &

# Áudio: inicia PipeWire e WirePlumber (se não iniciados pelo systemd)
pipewire &
pipewire-pulse &
wireplumber &

# Bluetooth: applet na bandeja
blueman-applet &

# Montagem automática de USB (ícone na tray com -t)
udiskie -t &

# Noctalia Shell (compositor de barra/painel/widgets)
qs -c noctalia-shell &
'

# ~/.config/labwc/rc.xml (configuração mínima funcional)
# Inclui tema macOS, keybinds essenciais e posição dos botões semáforo.
# O nome do tema em <name> deve bater com a pasta em
# ~/.local/share/themes/<nome>/openbox-3/
CONTEUDO_RC_XML='<?xml version="1.0" encoding="UTF-8"?>
<labwc_config>

  <!-- TEMA: Openbox-style macOS (botões semáforo)
       Coloque o tema em ~/.local/share/themes/NOME/openbox-3/
       e atualize o <name> abaixo para o nome da pasta. -->
  <theme>
    <name>Gruvbox-Dark-B</name>
    <titlebar>
      <layout>Close,Iconify,Maximize:Title</layout>
    </titlebar>
    <font place="ActiveWindow">
      <name>Inter</name>
      <size>10</size>
    </font>
  </theme>

  <!-- COMPORTAMENTO GERAL -->
  <core>
    <decoration>server</decoration>
    <gap>8</gap>
    <adaptiveSync>yes</adaptiveSync>
  </core>

  <!-- MOUSE: foco segue o cursor -->
  <focus>
    <followMouse>yes</followMouse>
    <raiseOnFocus>no</raiseOnFocus>
  </focus>

  <!-- KEYBINDS ESSENCIAIS -->
  <keyboard>
    <!-- Terminal padrão: mude "foot" para o seu emulador -->
    <keybind key="Super-Return">
      <action name="Execute"><command>foot</command></action>
    </keybind>

    <!-- Fechar janela focada -->
    <keybind key="Super-q">
      <action name="Close"/>
    </keybind>

    <!-- Launcher (muda para o seu launcher: fuzzel, rofi, etc) -->
    <keybind key="Super-space">
      <action name="Execute"><command>fuzzel</command></action>
    </keybind>

    <!-- Screenshot de área (requer grim + slurp) -->
    <keybind key="Super-s">
      <action name="Execute">
        <command>grim -g "$(slurp)" ~/Screenshots/$(date +%Y%m%d_%H%M%S).png</command>
      </action>
    </keybind>

    <!-- Brilho (requer brightnessctl) -->
    <keybind key="XF86MonBrightnessUp">
      <action name="Execute"><command>brightnessctl set +5%</command></action>
    </keybind>
    <keybind key="XF86MonBrightnessDown">
      <action name="Execute"><command>brightnessctl set 5%-</command></action>
    </keybind>
  </keyboard>

  <!-- MOUSE: ações no título da janela -->
  <mouse>
    <context name="TitleBar">
      <mousebind button="Left" action="Drag">
        <action name="Move"/>
      </mousebind>
      <mousebind button="Left" action="DoubleClick">
        <action name="ToggleMaximize"/>
      </mousebind>
      <mousebind button="Right" action="Click">
        <action name="ShowMenu"><menu>client-menu</menu></action>
      </mousebind>
    </context>
  </mouse>

</labwc_config>
'

# ~/.config/labwc/environment
# Variáveis de ambiente carregadas pelo labwc na inicialização da sessão.
# QS_ICON_THEME: diz ao engine Qt/QML do Noctalia qual tema de ícones usar.
# Instale o pack em ~/.local/share/icons/NOME/ e atualize o valor abaixo.
CONTEUDO_ENVIRONMENT='# labwc environment — carregado antes do autostart

# Tema de ícones para o Noctalia Shell (Qt/QML)
# Instale o pack em ~/.local/share/icons/NOME/
# e substitua o valor abaixo pelo nome exato da pasta.
QS_ICON_THEME=Papirus-Dark

# Backend Wayland para apps Qt
QT_QPA_PLATFORM=wayland

# Backend Wayland para apps Electron/Chromium (ex: VS Code, Slack)
ELECTRON_OZONE_PLATFORM_HINT=auto

# Força aceleração de hardware em apps GTK4
GDK_BACKEND=wayland

# Desativa HiDPI automático do Java (evita janelas fora de escala)
_JAVA_AWT_WM_NONREPARENTING=1

# Cursor theme (instale o pack e ajuste o nome)
XCURSOR_THEME=Adwaita
XCURSOR_SIZE=24
'

# ~/.config/labwc/menu.xml (menu de contexto básico)
CONTEUDO_MENU_XML='<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu>

  <menu id="client-menu" label="Janela">
    <item label="Maximizar">
      <action name="ToggleMaximize"/>
    </item>
    <item label="Minimizar">
      <action name="Iconify"/>
    </item>
    <separator/>
    <item label="Fechar">
      <action name="Close"/>
    </item>
  </menu>

</openbox_menu>
'

# ─────────────────────────────────────────────────────────────────────
# BLOCO 4: FUNÇÃO PRINCIPAL
# ─────────────────────────────────────────────────────────────────────

main() {
    check_root

    # Inicializa log limpo
    mkdir -p "$(dirname "${LOG_FILE}")"
    {
        echo "════════════════════════════════════════════"
        echo "  Post-Install Log — $(date '+%Y-%m-%d %H:%M:%S')"
        echo "  Usuário: ${USUARIO_REAL} | Home: ${HOME_REAL}"
        echo "════════════════════════════════════════════"
    } > "${LOG_FILE}"

    # Banner
    clear
    echo -e "${NEGRITO}${AZUL}"
    echo "  ╔═══════════════════════════════════════════════════╗"
    echo "  ║  Fedora 44 Minimal → labwc + Noctalia Shell v4    ║"
    echo "  ║  Usuário: ${USUARIO_REAL}                              ║"
    echo "  ║  Log: ${LOG_FILE}          ║"
    echo "  ╚═══════════════════════════════════════════════════╝"
    echo -e "${RESET}"

    # ── ETAPA 1: Atualizar sistema base ─────────────────────────────
    separador "Etapa 1/7 — Atualização do sistema"
    log_info "Rodando dnf upgrade..."
    if dnf upgrade -y >> "${LOG_FILE}" 2>&1; then
        log_ok "Sistema atualizado"
    else
        log_err "Falha na atualização — verifique ${LOG_FILE}"
    fi

    # ── ETAPA 2: Adicionar repositórios externos ─────────────────────
    # ORDEM IMPORTA: Terra e COPRs precisam ser adicionados ANTES
    # de instalar os pacotes que dependem deles.
    separador "Etapa 2/7 — Repositórios externos"

    # Terra (Fyra Labs) — repositório oficial para noctalia-shell no Fedora
    # Fonte: docs.noctalia.dev/v4/getting-started/installation/ → seção Fedora
    # --nogpgcheck é necessário apenas na instalação do terra-release em si;
    # após isso, o repo usa sua própria chave GPG.
    log_step "2.1" "Instalando repositório Terra (Fyra Labs)..."
    if dnf install -y \
        --nogpgcheck \
        --repofrompath "terra,https://repos.fyralabs.com/terra\$releasever" \
        terra-release >> "${LOG_FILE}" 2>&1; then
        log_ok "Terra repository instalado"
    else
        log_err "Falha ao instalar Terra — noctalia-shell não poderá ser instalado via Terra"
    fi

    # COPR: gpu-screen-recorder (dependência OBRIGATÓRIA do noctalia-shell)
    # Fonte: noctalia-shell.spec → Requires: gpu-screen-recorder
    # Sem este COPR, o dnf não encontra o pacote gpu-screen-recorder.
    log_step "2.2" "COPR: brycensranch/gpu-screen-recorder-git (dep obrigatória)"
    habilitar_copr "brycensranch/gpu-screen-recorder-git"

    # COPR: matugen (geração de paleta de cores a partir do wallpaper)
    # Fonte: noctalia-shell.spec → Recommends: matugen
    log_step "2.3" "COPR: heus-sueh/packages (contém matugen)"
    habilitar_copr "heus-sueh/packages"

    # ── ETAPA 3: Instalar componentes de sistema ─────────────────────
    separador "Etapa 3/7 — Componentes de sistema"
    instalar_grupo "Wayland Compositor (labwc)" "${PKGS_WAYLAND[@]}"
    instalar_grupo "Display Manager + Polkit"   "${PKGS_DM_POLKIT[@]}"
    instalar_grupo "Áudio (PipeWire Stack)"     "${PKGS_AUDIO[@]}"
    instalar_grupo "Bluetooth"                  "${PKGS_BLUETOOTH[@]}"
    instalar_grupo "Energia + Brilho"           "${PKGS_ENERGIA[@]}"
    instalar_grupo "Montagem Automática (USB)"  "${PKGS_DISCO[@]}"

    # ── ETAPA 4: Dependências do Noctalia + Noctalia Shell ───────────
    separador "Etapa 4/7 — Noctalia Shell"

    # Deps obrigatórias (Requires: no .spec)
    instalar_grupo "Dependências obrigatórias do Noctalia" "${PKGS_NOCTALIA_DEPS[@]}"

    # Deps recomendadas (Recommends: no .spec)
    instalar_grupo "Dependências recomendadas do Noctalia" "${PKGS_NOCTALIA_RECOMENDADOS[@]}"

    # O pacote noctalia-shell (via Terra) puxa noctalia-qs automaticamente
    # como dependência. qs = binário do Quickshell customizado pelo Noctalia.
    log_step "4.x" "Instalando noctalia-shell (puxa noctalia-qs como dep)..."
    if dnf install -y noctalia-shell >> "${LOG_FILE}" 2>&1; then
        log_ok "noctalia-shell instalado"
        log_info "Inicialização: qs -c noctalia-shell"
    else
        log_err "Falha ao instalar noctalia-shell — veja ${LOG_FILE}"
    fi

    # ── ETAPA 5: Habilitar serviços systemd ─────────────────────────
    separador "Etapa 5/7 — Serviços systemd (sistema)"
    habilitar_servico "sddm"
    habilitar_servico "bluetooth"
    habilitar_servico "tlp"
    habilitar_servico "power-profiles-daemon"

    # Serviços de usuário (escopo --user do systemd)
    separador "Etapa 5b/7 — Serviços systemd (usuário: ${USUARIO_REAL})"
    habilitar_servico_usuario "pipewire"
    habilitar_servico_usuario "pipewire-pulse"
    habilitar_servico_usuario "wireplumber"

    # ── ETAPA 6: Dotfiles do labwc ───────────────────────────────────
    separador "Etapa 6/7 — Configuração do labwc (~/.config/labwc/)"

    local cfg_dir="${HOME_REAL}/.config/labwc"

    escrever_arquivo_usuario "${cfg_dir}/autostart"    "${CONTEUDO_AUTOSTART}"
    escrever_arquivo_usuario "${cfg_dir}/rc.xml"       "${CONTEUDO_RC_XML}"
    escrever_arquivo_usuario "${cfg_dir}/environment"  "${CONTEUDO_ENVIRONMENT}"
    escrever_arquivo_usuario "${cfg_dir}/menu.xml"     "${CONTEUDO_MENU_XML}"

    # Garante permissão de execução no autostart
    chmod +x "${cfg_dir}/autostart"

    # Cria diretório de screenshots (usado no keybind de screenshot)
    mkdir -p "${HOME_REAL}/Screenshots"
    chown "${USUARIO_REAL}:${USUARIO_REAL}" "${HOME_REAL}/Screenshots"
    log_ok "Diretório ~/Screenshots criado"

    # ── ETAPA 7: Configurações finais de sistema ─────────────────────
    separador "Etapa 7/7 — Configurações adicionais de sistema"

    # Define o target padrão como graphical.target
    # Necessário em installs mínimas que podem estar em multi-user.target
    log_info "Definindo graphical.target como padrão..."
    if systemctl set-default graphical.target >> "${LOG_FILE}" 2>&1; then
        log_ok "Target padrão: graphical.target"
    else
        log_err "Falha ao definir graphical.target"
    fi

    # Adiciona o usuário ao grupo 'video' para acesso a brightnessctl sem sudo
    log_info "Adicionando ${USUARIO_REAL} ao grupo 'video' (brightnessctl sem sudo)..."
    if usermod -aG video "${USUARIO_REAL}" >> "${LOG_FILE}" 2>&1; then
        log_ok "${USUARIO_REAL} adicionado ao grupo video"
    else
        log_warn "Falha ao adicionar ao grupo video — brilho pode exigir sudo"
    fi

    # Adiciona ao grupo 'input' para Bluetooth e dispositivos de entrada
    log_info "Adicionando ${USUARIO_REAL} ao grupo 'input'..."
    if usermod -aG input "${USUARIO_REAL}" >> "${LOG_FILE}" 2>&1; then
        log_ok "${USUARIO_REAL} adicionado ao grupo input"
    else
        log_warn "Falha ao adicionar ao grupo input"
    fi

    # ── RELATÓRIO FINAL ──────────────────────────────────────────────
    separador "Relatório Final"

    if [[ $ERROS -eq 0 ]]; then
        echo -e "${VERDE}${NEGRITO}"
        echo "  ✓ Instalação concluída sem erros!"
        echo -e "${RESET}"
    else
        echo -e "${AMARELO}${NEGRITO}"
        echo "  ⚠ Concluído com ${ERROS} erro(s)."
        echo -e "${RESET}"
        echo -e "  ${VERMELHO}Verifique: ${LOG_FILE}${RESET}"
    fi

    echo ""
    echo -e "${NEGRITO}Próximos passos manuais:${RESET}"
    echo ""
    echo -e "  ${CIANO}1.${RESET} Instale um tema macOS Openbox:"
    echo -e "     → Baixe ex: https://github.com/topics/openbox-theme"
    echo -e "     → Coloque em: ~/.local/share/themes/NOME/openbox-3/"
    echo -e "     → Edite ${HOME_REAL}/.config/labwc/rc.xml → <theme><name>"
    echo ""
    echo -e "  ${CIANO}2.${RESET} Instale pack de ícones macOS-like:"
    echo -e "     → Ex: Papirus: sudo dnf install papirus-icon-theme"
    echo -e "     → Ou La Capitaine: coloque em ~/.local/share/icons/"
    echo -e "     → Edite ${HOME_REAL}/.config/labwc/environment → QS_ICON_THEME"
    echo ""
    echo -e "  ${CIANO}3.${RESET} Instale um emulador de terminal:"
    echo -e "     → sudo dnf install foot  (leve, Wayland nativo)"
    echo -e "     → Ou: kitty, alacritty"
    echo ""
    echo -e "  ${CIANO}4.${RESET} Instale um launcher de apps:"
    echo -e "     → sudo dnf install fuzzel"
    echo ""
    echo -e "  ${CIANO}5.${RESET} Instale ferramentas de screenshot:"
    echo -e "     → sudo dnf install grim slurp"
    echo ""
    echo -e "  ${CIANO}6.${RESET} Reinicie para o SDDM carregar a sessão labwc."
    echo ""
    echo -e "  Log completo em: ${LOG_FILE}"
    echo ""
}

# Ponto de entrada: "$@" passa todos os args da linha de comando pro main.
main "$@"
