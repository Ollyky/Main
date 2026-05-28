#!/usr/bin/env bash
# ==============================================================================
# Fedora 44 Minimal → labwc + Noctalia Shell
# Instalador e configurador completo, modular e com validação defensiva.
#
# O que este script faz:
#   - Atualiza o sistema
#   - Habilita o repositório Terra para Noctalia
#   - Instala SDDM e força Wayland
#   - Define labwc-session como sessão padrão
#   - Instala Noctalia Shell + runtime via Terra
#   - Instala apps RPM escolhidos
#   - Instala GNOME Keyring + GNOME Online Accounts
#   - Compila o Fastfetch a partir do GitHub via wget + CMake
#   - Instala WhiteSur GTK Theme + WhiteSur Icon Theme via GitHub oficial
#   - Escreve os ficheiros completos de ~/.config/labwc/
#   - Prepara wallpapers com scaffold de download
#   - Ativa serviços do sistema e organiza serviços de usuário
#
# Uso:
#   sudo bash ./fedora44-labwc-noctalia-installer.sh
# ==============================================================================

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

# ------------------------------------------------------------------------------
# Configuração global
# ------------------------------------------------------------------------------
readonly SCRIPT_NAME="${0##*/}"
readonly LOG_FILE="/var/log/fedora44-labwc-noctalia-install.log"
readonly SDDM_CONF_DIR="/etc/sddm.conf.d"
readonly VSCODE_REPO_FILE="/etc/yum.repos.d/vscode.repo"
readonly VSCODE_REPO_URL="https://packages.microsoft.com/yumrepos/vscode/config.repo"
readonly TERRA_REPO_URL="https://repos.fyralabs.com/terra"
readonly FASTFETCH_API_URL="https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest"
readonly FASTFETCH_SOURCE_BASE="https://github.com/fastfetch-cli/fastfetch/archive/refs/tags"

# ------------------------------------------------------------------------------
# Usuário alvo
# ------------------------------------------------------------------------------
readonly TARGET_USER="${SUDO_USER:-}"
readonly TARGET_HOME="$(getent passwd "${TARGET_USER:-root}" | cut -d: -f6 2>/dev/null || true)"
readonly TARGET_UID="$(id -u "${SUDO_USER:-root}" 2>/dev/null || true)"

# ------------------------------------------------------------------------------
# Preferências do utilizador
# ------------------------------------------------------------------------------
readonly DEFAULT_TERMINAL="alacritty"
readonly LABWC_THEME_NAME="WhiteSur"
readonly ICONS_THEME_NAME="WhiteSur"
readonly GTK_THEME_REPO="https://github.com/vinceliuice/WhiteSur-gtk-theme.git"
readonly ICON_THEME_REPO="https://github.com/vinceliuice/WhiteSur-icon-theme.git"
readonly WALLPAPERS_DIR="${TARGET_HOME}/Pictures/Wallpapers"
readonly FASTFETCH_BUILD_DIR="/tmp/fastfetch-build"

# ------------------------------------------------------------------------------
# URLs e scaffolds editáveis pelo usuário
# ------------------------------------------------------------------------------
THEME_URL=""   # INSERIR LINK DO TEMA AQUI
ICONS_URL=""   # INSERIR LINK DO PACK DE ÍCONES AQUI

# Se quiseres automatizar downloads de wallpapers depois, preenche os vazios.
WALLPAPER_URLS=(
  "https://4kwallpapers.com/images/wallpapers/sage-green-abstract-5120x3413-26355.jpg"
  "https://4kwallpapers.com/images/wallpapers/sage-green-abstract-5120x3413-26354.jpg"
  "https://4kwallpapers.com/images/wallpapers/mountain-landscape-5120x2880-24317.jpg"
  "https://4kwallpapers.com/images/wallpapers/shinra-kusakabe-3840x2160-18916.jpg"
  "https://4kwallpapers.com/images/wallpapers/alucard-8k-hellsing-7680x4320-13839.png"
  "https://4kwallpapers.com/images/wallpapers/alucard-hellsing-5120x2880-13882.png"
  "https://4kwallpapers.com/images/wallpapers/iridescent-spheres-5120x5120-26346.jpg"
  ""
)


# ------------------------------------------------------------------------------
# Pacotes RPM do Fedora 44
# ------------------------------------------------------------------------------
PKGS_CORE=(
  labwc
  labwc-session
  sddm
  lxqt-policykit
  pipewire
  pipewire-pulseaudio
  wireplumber
  bluez
  blueman
  power-profiles-daemon
  brightnessctl
  udisks2
  udiskie
  xdg-desktop-portal
  xdg-desktop-portal-wlr
  xdg-desktop-portal-gtk
  accountsservice
  git
  curl
  wget
  tar
  ca-certificates
  dnf-plugins-core
  gnome-keyring
  gnome-keyring-pam
  seahorse
  gnome-online-accounts
  gnome-online-accounts-gtk
  gvfs-goa
  sassc
  glib2-devel
  optipng
  inkscape
  cmake
  gcc
  gcc-c++
  make
  ninja-build
  pkgconf-pkg-config
)

PKGS_APPS=(
  alacritty
  konsole
  gnome-terminal
  dolphin
  nautilus
  kate
  nano
  spectacle
  firefox
)

PKGS_VSCODE_REPO_DEPS=(
  ca-certificates
  curl
  dnf-plugins-core
)

PKGS_FASTFETCH_BUILD_DEPS=(
  cmake
  gcc
  gcc-c++
  make
  ninja-build
  wget
  tar
  pkgconf-pkg-config
)

# ------------------------------------------------------------------------------
# Logging e utilidades
# ------------------------------------------------------------------------------
ERROS=0

log_ts() { date '+%Y-%m-%d %H:%M:%S'; }
ok()     { printf '[OK]  %s\n' "$*"; }
info()   { printf '[..]  %s\n' "$*"; }
warn()   { printf '[!!]  %s\n' "$*"; }
err()    { printf '[ERRO] %s\n' "$*"; }

on_error() {
  local line="$1"
  local cmd="$2"
  printf '[%s] ERRO na linha %s: %s\n' "$(log_ts)" "${line}" "${cmd}" >> "${LOG_FILE}"
  warn "Falha na linha ${line}: ${cmd}"
  ((ERROS++)) || true
}
trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "Execute com sudo: sudo bash ./${SCRIPT_NAME}"
    exit 1
  fi
}

require_user() {
  if [[ -z "${TARGET_USER}" || "${TARGET_USER}" == "root" ]]; then
    err "Não consegui identificar o usuário alvo. Execute o script via sudo a partir da tua conta normal."
    exit 1
  fi

  if [[ -z "${TARGET_HOME}" || ! -d "${TARGET_HOME}" ]]; then
    err "Home do usuário alvo não encontrada: ${TARGET_HOME}"
    exit 1
  fi
}

init_log() {
  mkdir -p "$(dirname "${LOG_FILE}")"
  {
    echo "================================================================"
    echo " Fedora 44 Minimal → labwc + Noctalia Shell"
    echo " Data: $(log_ts)"
    echo " Usuário alvo: ${TARGET_USER}"
    echo " Home alvo: ${TARGET_HOME}"
    echo "================================================================"
  } > "${LOG_FILE}"
}

run() {
  local desc="$1"
  shift
  info "${desc}"
  if "$@" >> "${LOG_FILE}" 2>&1; then
    ok "${desc}"
    return 0
  fi
  warn "${desc} falhou (ver log)"
  ((ERROS++)) || true
  return 1
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

backup_if_exists() {
  local path="$1"
  if [[ -e "${path}" ]]; then
    local backup="${path}.bak.$(date +%Y%m%d_%H%M%S)"
    cp -a -- "${path}" "${backup}"
    info "Backup criado: ${backup}"
  fi
}

set_owner() {
  local path="$1"
  chown -R "${TARGET_USER}:${TARGET_USER}" "${path}" 2>/dev/null || true
}

dnf_install_many() {
  local title="$1"
  shift
  local pkgs=("$@")

  info "Instalando: ${title}"
  for pkg in "${pkgs[@]}"; do
    if rpm -q "${pkg}" >/dev/null 2>&1; then
      ok "${pkg} já está instalado"
      continue
    fi

    if dnf install -y "${pkg}" >> "${LOG_FILE}" 2>&1; then
      ok "${pkg}"
    else
      warn "${pkg} falhou"
      ((ERROS++)) || true
    fi
  done
}

download_file() {
  local url="$1"
  local dest="$2"

  if [[ -z "${url}" ]]; then
    return 1
  fi

  mkdir -p "$(dirname "${dest}")"

  if have_cmd wget; then
    wget -q --show-progress --https-only -O "${dest}" "${url}"
  elif have_cmd curl; then
    curl -fL --retry 3 --retry-delay 2 -o "${dest}" "${url}"
  else
    return 1
  fi
}

ensure_user_dirs() {
  mkdir -p \
    "${TARGET_HOME}/.config/labwc" \
    "${TARGET_HOME}/.config/autostart" \
    "${TARGET_HOME}/.local/share/themes" \
    "${TARGET_HOME}/.local/share/icons" \
    "${TARGET_HOME}/.config/systemd/user/default.target.wants" \
    "${TARGET_HOME}/Pictures/Wallpapers" \
    "${TARGET_HOME}/Screenshots"

  set_owner "${TARGET_HOME}/.config"
  set_owner "${TARGET_HOME}/.local"
  set_owner "${TARGET_HOME}/Pictures"
  set_owner "${TARGET_HOME}/Screenshots"
}

install_vscode_repo() {
  if rpm -q code >/dev/null 2>&1; then
    ok "code já está instalado"
    return 0
  fi

  dnf_install_many "Dependências do repositório do VS Code" "${PKGS_VSCODE_REPO_DEPS[@]}"

  info "Configurando repositório oficial da Microsoft para VS Code"
  local tmp_repo="${VSCODE_REPO_FILE}.tmp"
  if have_cmd wget; then
    wget -qO "${tmp_repo}" "${VSCODE_REPO_URL}"
  elif have_cmd curl; then
    curl -fsSL "${VSCODE_REPO_URL}" -o "${tmp_repo}"
  else
    warn "curl/wget indisponíveis para configurar o repositório do VS Code"
    ((ERROS++)) || true
    return 1
  fi

  mv -f "${tmp_repo}" "${VSCODE_REPO_FILE}"
  chmod 0644 "${VSCODE_REPO_FILE}"
  ok "Repositório do VS Code configurado"

  run "Instalando code" dnf install -y code
}

install_terra_repo_and_noctalia() {
  info "Habilitando Terra (Fyra Labs)"
  local FEDORA_VERSION
  FEDORA_VERSION="$(rpm -E %fedora)"
  if dnf install -y --nogpgcheck --repofrompath "terra,${TERRA_REPO_URL}${FEDORA_VERSION}" terra-release >> "${LOG_FILE}" 2>&1; then
    ok "terra-release instalado"
  else
    warn "Falha ao instalar terra-release"
    ((ERROS++)) || true
    return 1
  fi

  info "Instalando noctalia-shell"
  if dnf install -y noctalia-shell >> "${LOG_FILE}" 2>&1; then
    ok "noctalia-shell instalado"
  else
    warn "Falha ao instalar noctalia-shell"
    ((ERROS++)) || true
    return 1
  fi

  if rpm -q noctalia-qs >/dev/null 2>&1; then
    ok "noctalia-qs presente como runtime"
  else
    warn "noctalia-qs não apareceu como instalado; verifique o repositório Terra"
    ((ERROS++)) || true
  fi
}

build_fastfetch_from_github() {
  if rpm -q fastfetch >/dev/null 2>&1; then
    ok "fastfetch já está instalado"
    return 0
  fi

  dnf_install_many "Dependências de build do Fastfetch" "${PKGS_FASTFETCH_BUILD_DEPS[@]}"

  local api_json="/tmp/fastfetch-latest.json"
  local tag=""
  if have_cmd wget; then
    wget -qO "${api_json}" "${FASTFETCH_API_URL}"
  elif have_cmd curl; then
    curl -fsSL "${FASTFETCH_API_URL}" -o "${api_json}"
  else
    warn "curl/wget indisponíveis para obter a versão do Fastfetch"
    ((ERROS++)) || true
    return 1
  fi

  tag="$(sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' "${api_json}" | head -n1)"
  if [[ -z "${tag}" ]]; then
    warn "Não consegui identificar a tag mais recente do Fastfetch"
    ((ERROS++)) || true
    return 1
  fi

  local workdir
  local source_tar
  local source_url
  local source_dir
  workdir="$(mktemp -d)"
  source_tar="${workdir}/fastfetch.tar.gz"
  source_url="${FASTFETCH_SOURCE_BASE}/${tag}.tar.gz"

  info "Baixando Fastfetch ${tag}"
  if ! wget -q --show-progress --https-only -O "${source_tar}" "${source_url}"; then
    warn "Falha ao baixar o Fastfetch"
    rm -rf "${workdir}"
    ((ERROS++)) || true
    return 1
  fi

  rm -rf "${FASTFETCH_BUILD_DIR}"
  mkdir -p "${FASTFETCH_BUILD_DIR}"
  tar -xf "${source_tar}" -C "${workdir}"

  source_dir="$(find "${workdir}" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  if [[ -z "${source_dir}" || ! -d "${source_dir}" ]]; then
    warn "Não encontrei o diretório-fonte extraído do Fastfetch"
    rm -rf "${workdir}"
    ((ERROS++)) || true
    return 1
  fi

  info "Compilando Fastfetch com CMake + Ninja"
  if cmake -S "${source_dir}" -B "${FASTFETCH_BUILD_DIR}" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr >> "${LOG_FILE}" 2>&1 \
    && ninja -C "${FASTFETCH_BUILD_DIR}" >> "${LOG_FILE}" 2>&1 \
    && ninja -C "${FASTFETCH_BUILD_DIR}" install >> "${LOG_FILE}" 2>&1; then
    ok "Fastfetch compilado e instalado"
  else
    warn "Falha ao compilar/instalar Fastfetch"
    rm -rf "${workdir}" "${FASTFETCH_BUILD_DIR}"
    ((ERROS++)) || true
    return 1
  fi

  if command -v fastfetch >/dev/null 2>&1; then
    ok "fastfetch disponível globalmente"
  else
    warn "fastfetch não apareceu no PATH após a instalação"
    ((ERROS++)) || true
  fi

  rm -rf "${workdir}" "${FASTFETCH_BUILD_DIR}" "${api_json}"
}

install_whitesur_gtk_theme() {
  info "Instalando WhiteSur GTK Theme"
  local tmp="/tmp/WhiteSur-gtk-theme"
  rm -rf "${tmp}"

  if ! git clone --depth=1 "${GTK_THEME_REPO}" "${tmp}" >> "${LOG_FILE}" 2>&1; then
    warn "Falha ao clonar WhiteSur GTK Theme"
    ((ERROS++)) || true
    return 1
  fi

  if ! sudo -u "${TARGET_USER}" env HOME="${TARGET_HOME}" bash -lc "cd '${tmp}' && ./install.sh" >> "${LOG_FILE}" 2>&1; then
    warn "Falha ao executar o instalador do WhiteSur GTK Theme"
    ((ERROS++)) || true
    rm -rf "${tmp}"
    return 1
  fi

  mkdir -p "${TARGET_HOME}/.local/share/themes"
  if [[ -d "${TARGET_HOME}/.themes/WhiteSur" ]]; then
    ln -sfn "${TARGET_HOME}/.themes/WhiteSur" "${TARGET_HOME}/.local/share/themes/WhiteSur"
  fi
  if [[ -d "${TARGET_HOME}/.themes/WhiteSur-dark" ]]; then
    ln -sfn "${TARGET_HOME}/.themes/WhiteSur-dark" "${TARGET_HOME}/.local/share/themes/WhiteSur-dark"
  fi

  set_owner "${TARGET_HOME}/.themes"
  set_owner "${TARGET_HOME}/.local/share/themes"
  ok "WhiteSur GTK Theme instalado"
  rm -rf "${tmp}"
}

install_whitesur_icon_theme() {
  info "Instalando WhiteSur Icon Theme"
  local tmp="/tmp/WhiteSur-icon-theme"
  rm -rf "${tmp}"

  if ! git clone --depth=1 "${ICON_THEME_REPO}" "${tmp}" >> "${LOG_FILE}" 2>&1; then
    warn "Falha ao clonar WhiteSur Icon Theme"
    ((ERROS++)) || true
    return 1
  fi

  if ! sudo -u "${TARGET_USER}" env HOME="${TARGET_HOME}" bash -lc "cd '${tmp}' && ./install.sh -n '${ICONS_THEME_NAME}'" >> "${LOG_FILE}" 2>&1; then
    warn "Falha ao executar o instalador do WhiteSur Icon Theme"
    ((ERROS++)) || true
    rm -rf "${tmp}"
    return 1
  fi

  set_owner "${TARGET_HOME}/.local/share/icons"
  ok "WhiteSur Icon Theme instalado"
  rm -rf "${tmp}"
}

write_labwc_autostart() {
  local file="${TARGET_HOME}/.config/labwc/autostart"
  backup_if_exists "${file}"

  cat > "${file}" <<'EOF'
#!/usr/bin/env bash
# labwc autostart
# Ordem pedida:
#   1) lxqt-policykit-agent
#   2) blueman-applet
#   3) udiskie
#   4) gnome-keyring-daemon --start
#   5) propagação de variáveis para D-Bus/systemd
#   6) Noctalia Shell

# Agente Polkit do LXQt (caminho correto no Fedora)
if command -v /usr/libexec/lxqt-policykit-agent >/dev/null 2>&1; then
  /usr/libexec/lxqt-policykit-agent &
fi

# Bluetooth tray
blueman-applet &

# Automontagem de discos e USB
udiskie -t &

# GNOME Keyring para segredos, SSH e chaves
if command -v gnome-keyring-daemon >/dev/null 2>&1; then
  eval "$(gnome-keyring-daemon --start --components=secrets,pkcs11,ssh)"
fi

# Propaga variáveis da sessão para o systemd --user e D-Bus
systemctl --user import-environment \
  WAYLAND_DISPLAY \
  XDG_CURRENT_DESKTOP \
  XDG_SESSION_TYPE \
  DESKTOP_SESSION \
  QT_QPA_PLATFORM \
  GDK_BACKEND \
  MOZ_ENABLE_WAYLAND \
  ELECTRON_OZONE_PLATFORM_HINT \
  SDL_VIDEODRIVER \
  GNOME_KEYRING_CONTROL \
  GNOME_KEYRING_PID \
  SSH_AUTH_SOCK >/dev/null 2>&1 &

dbus-update-activation-environment --systemd \
  WAYLAND_DISPLAY \
  XDG_CURRENT_DESKTOP \
  XDG_SESSION_TYPE \
  DESKTOP_SESSION \
  QT_QPA_PLATFORM \
  GDK_BACKEND \
  MOZ_ENABLE_WAYLAND \
  ELECTRON_OZONE_PLATFORM_HINT \
  SDL_VIDEODRIVER \
  GNOME_KEYRING_CONTROL \
  GNOME_KEYRING_PID \
  SSH_AUTH_SOCK >/dev/null 2>&1 &

# Noctalia Shell
qs -c noctalia-shell &
EOF

  chmod +x "${file}"
  set_owner "${file}"
  ok "Criado: ${file}"
}

write_labwc_environment() {
  local file="${TARGET_HOME}/.config/labwc/environment"
  backup_if_exists "${file}"

  cat > "${file}" <<EOF
# labwc environment — carregado antes do autostart

# Tema de ícones para o Noctalia Shell (Qt/QML)
QS_ICON_THEME=${ICONS_THEME_NAME}

# Wayland por padrão para apps gráficas
QT_QPA_PLATFORM=wayland
GDK_BACKEND=wayland
ELECTRON_OZONE_PLATFORM_HINT=wayland
SDL_VIDEODRIVER=wayland
MOZ_ENABLE_WAYLAND=1
GTK_USE_PORTAL=1

# Contexto da sessão
XDG_CURRENT_DESKTOP=labwc
XDG_SESSION_TYPE=wayland
DESKTOP_SESSION=labwc

# Cursor
XCURSOR_THEME=Adwaita
XCURSOR_SIZE=24
EOF

  set_owner "${file}"
  ok "Criado: ${file}"
}

write_labwc_menu() {
  local file="${TARGET_HOME}/.config/labwc/menu.xml"
  backup_if_exists "${file}"

  cat > "${file}" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
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

  <menu id="root-menu" label="labwc">
    <item label="Terminal">
      <action name="Execute"><command>alacritty</command></action>
    </item>
    <item label="Konsole">
      <action name="Execute"><command>konsole</command></action>
    </item>
    <item label="GNOME Terminal">
      <action name="Execute"><command>gnome-terminal</command></action>
    </item>
    <separator/>
    <item label="Ficheiros (Dolphin)">
      <action name="Execute"><command>dolphin</command></action>
    </item>
    <item label="Ficheiros (Nautilus)">
      <action name="Execute"><command>nautilus</command></action>
    </item>
    <item label="Navegador (Firefox)">
      <action name="Execute"><command>firefox</command></action>
    </item>
    <item label="Captura de Tela (Spectacle)">
      <action name="Execute"><command>spectacle</command></action>
    </item>
    <separator/>
    <item label="Recarregar Configuração">
      <action name="Reconfigure"/>
    </item>
    <item label="Sair">
      <action name="Exit"/>
    </item>
  </menu>

</openbox_menu>
EOF

  set_owner "${file}"
  ok "Criado: ${file}"
}

write_labwc_rc_xml() {
  local file="${TARGET_HOME}/.config/labwc/rc.xml"
  backup_if_exists "${file}"

  cat > "${file}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<labwc_config>

  <!-- Tema de janelas: use um tema Openbox/labwc compatível com o nome abaixo -->
  <theme>
    <name>${LABWC_THEME_NAME}</name>
    <titlebar>
      <!-- Semáforo do lado esquerdo: Close, Minimize, Maximize -->
      <layout>Close,Iconify,Maximize:Title</layout>
    </titlebar>
    <font place="ActiveWindow">
      <name>Inter</name>
      <size>10</size>
    </font>
  </theme>

  <!-- Comportamento geral -->
  <core>
    <decoration>server</decoration>
    <gap>8</gap>
    <adaptiveSync>yes</adaptiveSync>
  </core>

  <!-- Foco -->
  <focus>
    <followMouse>yes</followMouse>
    <raiseOnFocus>no</raiseOnFocus>
  </focus>

  <!-- Teclado -->
  <keyboard>
    <keybind key="Super-Return">
      <action name="Execute"><command>alacritty</command></action>
    </keybind>

    <keybind key="Super-Shift-Return">
      <action name="Execute"><command>konsole</command></action>
    </keybind>

    <keybind key="Super-Ctrl-Return">
      <action name="Execute"><command>gnome-terminal</command></action>
    </keybind>

    <keybind key="Super-e">
      <action name="Execute"><command>dolphin</command></action>
    </keybind>

    <keybind key="Super-n">
      <action name="Execute"><command>nautilus</command></action>
    </keybind>

    <keybind key="Super-b">
      <action name="Execute"><command>firefox</command></action>
    </keybind>

    <keybind key="Print">
      <action name="Execute"><command>spectacle</command></action>
    </keybind>

    <keybind key="XF86MonBrightnessUp">
      <action name="Execute"><command>brightnessctl set +5%</command></action>
    </keybind>

    <keybind key="XF86MonBrightnessDown">
      <action name="Execute"><command>brightnessctl set 5%-</command></action>
    </keybind>

    <keybind key="Super-q">
      <action name="Close"/>
    </keybind>

    <keybind key="Super-Shift-r">
      <action name="Reconfigure"/>
    </keybind>
  </keyboard>

  <!-- Mouse -->
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
    </context>
  </mouse>

</labwc_config>
EOF

  set_owner "${file}"
  ok "Criado: ${file}"
}

write_sddm_wayland_conf() {
  mkdir -p "${SDDM_CONF_DIR}"

  local file="${SDDM_CONF_DIR}/10-labwc-wayland.conf"
  backup_if_exists "${file}"

  cat > "${file}" <<'EOF'
[General]
# SDDM em Wayland
DisplayServer=wayland

# Sessão padrão preselecionada
DefaultSession=labwc.desktop

[Autologin]
# Mantido aqui para compatibilidade com ambientes que leem o valor da sessão.
Session=labwc.desktop
EOF

  chmod 0644 "${file}"
  ok "Criado: ${file}"
}

write_wallpaper_scaffold() {
  local dir="${WALLPAPERS_DIR}"
  mkdir -p "${dir}"

  local scaffold="${dir}/download-wallpapers.sh"
  backup_if_exists "${scaffold}"

  cat > "${scaffold}" <<'EOF'
#!/usr/bin/env bash
# INSERIR LINK DO WALLPAPER AQUI
# Exemplo:
# wget -O "$HOME/Pictures/Wallpapers/wallpaper-01.jpg" ""
# curl -L "" -o "$HOME/Pictures/Wallpapers/wallpaper-01.jpg"
#
# O script principal já cria a pasta:
#   ~/Pictures/Wallpapers/
#
# Só descomenta e cola os teus links diretos aqui quando quiseres.
EOF

  chmod +x "${scaffold}"
  set_owner "${dir}"
  set_owner "${scaffold}"
  ok "Pasta de wallpapers pronta: ${dir}"
}

download_optional_placeholders() {
  mkdir -p "${TARGET_HOME}/.local/share/themes" "${TARGET_HOME}/.local/share/icons"
  set_owner "${TARGET_HOME}/.local/share/themes"
  set_owner "${TARGET_HOME}/.local/share/icons"

  if [[ -n "${THEME_URL}" ]]; then
    info "THEME_URL definida; aqui seria o ponto para download manual de um tema Openbox/labwc"
  else
    info "THEME_URL vazia — conforme pedido, a URL do tema ficou em branco"
  fi

  if [[ -n "${ICONS_URL}" ]]; then
    info "ICONS_URL definida; aqui seria o ponto para download manual de um pack de ícones"
  else
    info "ICONS_URL vazia — conforme pedido, a URL dos ícones ficou em branco"
  fi
}

enable_services() {
  info "Ativando serviços de sistema"
  systemctl enable --now sddm >> "${LOG_FILE}" 2>&1 || { warn "Falha ao ativar sddm"; ((ERROS++)) || true; }
  systemctl enable --now bluetooth >> "${LOG_FILE}" 2>&1 || { warn "Falha ao ativar bluetooth"; ((ERROS++)) || true; }
  systemctl enable --now power-profiles-daemon >> "${LOG_FILE}" 2>&1 || { warn "Falha ao ativar power-profiles-daemon"; ((ERROS++)) || true; }

  info "Organizando serviços do PipeWire/WirePlumber no escopo do usuário"
  local user_unit_dir="${TARGET_HOME}/.config/systemd/user/default.target.wants"
  mkdir -p "${user_unit_dir}"

  local units=(
    pipewire.socket
    pipewire-pulse.socket
    wireplumber.service
  )

  for unit in "${units[@]}"; do
    local unit_path="/usr/lib/systemd/user/${unit}"
    if [[ -e "${unit_path}" ]]; then
      ln -sf "${unit_path}" "${user_unit_dir}/${unit}"
      ok "Habilitado (user): ${unit}"
    else
      warn "Unit de usuário não encontrada: ${unit_path}"
      ((ERROS++)) || true
    fi
  done
}

install_base_packages() {
  dnf_install_many "Pacotes base do sistema e desktop" "${PKGS_CORE[@]}"
  dnf_install_many "Aplicações escolhidas" "${PKGS_APPS[@]}"
}

print_summary() {
  echo
  echo "================================================================"
  if [[ "${ERROS}" -eq 0 ]]; then
    ok "Instalação concluída sem erros."
  else
    warn "Instalação concluída com ${ERROS} erro(s)."
  fi
  echo "Log: ${LOG_FILE}"
  echo
  echo "Próximos passos:"
  echo "  - Confirmar a presença do tema labwc em ~/.local/share/themes/${LABWC_THEME_NAME}"
  echo "  - Confirmar o pack de ícones WhiteSur em ~/.local/share/icons/${ICONS_THEME_NAME}"
  echo "  - Fazer login via SDDM e escolher labwc se necessário"
  echo "  - Abrir Nautilus e adicionar Google no GNOME Online Accounts"
  echo "  - O keyring fica disponível via gnome-keyring + PAM + autostart"
  echo "  - Fastfetch fica globalmente disponível no terminal"
  echo "================================================================"
}

main() {
  require_root
  require_user
  init_log

  echo "================================================================"
  echo " Fedora 44 Minimal → labwc + Noctalia Shell"
  echo " Usuário alvo: ${TARGET_USER}"
  echo " Log: ${LOG_FILE}"
  echo "================================================================"

  ensure_user_dirs
  run "Atualizando sistema (dnf upgrade)" dnf upgrade -y
  install_base_packages
  install_vscode_repo
  install_terra_repo_and_noctalia
  build_fastfetch_from_github
  install_whitesur_gtk_theme
  install_whitesur_icon_theme

  # Scaffolds pedidos pelo utilizador
  download_optional_placeholders
  write_wallpaper_scaffold

  # Configuração do labwc e do SDDM
  write_labwc_autostart
  write_labwc_menu
  write_labwc_environment
  write_labwc_rc_xml
  write_sddm_wayland_conf

  # Serviços
  enable_services

  print_summary
}

main "$@"
