#!/usr/bin/env bash
    # ╔══════════════════════════════════════════════════════════════════════════╗
    # ║  install-apps-complementar.sh                                            ║
    # ║  Script COMPLEMENTAR ao INSTALADOR_DEFINITIVO_FEDORA44.sh               ║
    # ║                                                                          ║
    # ║  Execute APÓS o script principal:                                        ║
    # ║    sudo ./install-apps-complementar.sh                                   ║
    # ║                                                                          ║
    # ║  O que este script faz (sem duplicar o script mestre):                  ║
    # ║  1. Ativa RPM Fusion + Flathub e instala 22 Flatpaks                    ║
    # ║  2. Instala RPMs extras (VLC, haruna, kdenlive, virt-manager, etc.)     ║
    # ║  3. Injeta novos programas em submenus no menu.xml do LABWC             ║
    # ║                                                                          ║
    # ║  NÃO duplica: firefox, kate, spectacle, nano, alacritty, konsole,       ║
    # ║  dolphin, nautilus, fastfetch, grim, slurp (já no script mestre)        ║
    # ╚══════════════════════════════════════════════════════════════════════════╝
    
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
    
    # Log separado do script mestre para não misturar outputs
    readonly LOG_FILE="/var/log/post-install-complementar.log"
    
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
            echo -e "${VERMELHO}${NEGRITO}ERRO: execute via sudo a partir do seu usuário normal.${RESET}"
            exit 1
        fi
    }
    
    # Verifica se um pacote RPM já está instalado.
    pkg_rpm_instalado() {
        rpm -q "$1" &>/dev/null
    }
    
    # Verifica se um Flatpak já está instalado para o usuário real.
    flatpak_instalado() {
        sudo -u "${USUARIO_REAL}" flatpak list --app 2>/dev/null | grep -q "^$1"
    }
    
    # Instala um pacote RPM com verificação prévia.
    instalar_rpm() {
        local pkg="$1"
        if pkg_rpm_instalado "$pkg"; then
            log_warn "${pkg} já instalado (RPM) — pulando"
            return 0
        fi
        log_info "Instalando RPM: ${pkg}..."
        if dnf install -y "$pkg" >> "${LOG_FILE}" 2>&1; then
            log_ok "${pkg}"
        else
            log_err "Falha ao instalar RPM: ${pkg}"
            return 1
        fi
    }
    
    # ─────────────────────────────────────────────────────────────────────────
    # BLOCO 2: FUNÇÃO 1 — REPOSITÓRIOS + FLATPAKS
    #
    # Ativa RPM Fusion Free/Nonfree (para VLC) e Flathub (para todos os
    # Flatpaks), verificando se já estão configurados antes de tentar.
    # Instala 22 Flatpaks sem runtimes base (puxados automaticamente como deps).
    # ─────────────────────────────────────────────────────────────────────────
    
    configurar_repos_e_instalar_flatpaks() {
        separador "FUNÇÃO 1 — Repositórios externos + Flatpaks"
    
        # ── RPM Fusion Free (necessário para VLC) ──────────────────────────
        log_step "1.1" "RPM Fusion Free (VLC e codecs livres)..."
        if pkg_rpm_instalado "rpmfusion-free-release"; then
            log_warn "RPM Fusion Free já configurado — pulando"
        else
            local url_free="https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
            if dnf install -y "${url_free}" >> "${LOG_FILE}" 2>&1; then
                log_ok "RPM Fusion Free ativado"
            else
                log_err "Falha ao ativar RPM Fusion Free — VLC pode não instalar"
            fi
        fi
    
        # ── RPM Fusion Nonfree (drivers, codecs proprietários) ──────────────
        log_step "1.2" "RPM Fusion Nonfree (codecs e drivers proprietários)..."
        if pkg_rpm_instalado "rpmfusion-nonfree-release"; then
            log_warn "RPM Fusion Nonfree já configurado — pulando"
        else
            local url_nonfree="https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
            if dnf install -y "${url_nonfree}" >> "${LOG_FILE}" 2>&1; then
                log_ok "RPM Fusion Nonfree ativado"
            else
                log_err "Falha ao ativar RPM Fusion Nonfree"
            fi
        fi
    
        # ── Flathub ────────────────────────────────────────────────────────
        # Método oficial Fedora 44: flatpak remote-add --if-not-exists.
        # Seguro para re-execução: --if-not-exists evita erro se já configurado.
        log_step "1.3" "Flathub (repositório principal de Flatpaks)..."
        if sudo -u "${USUARIO_REAL}" \
            flatpak remote-list 2>/dev/null | grep -q "flathub"; then
            log_warn "Flathub já configurado — pulando"
        else
            if flatpak remote-add --if-not-exists flathub \
                https://dl.flathub.org/repo/flathub.flatpakrepo \
                >> "${LOG_FILE}" 2>&1; then
                log_ok "Flathub configurado"
            else
                log_err "Falha ao configurar Flathub"
            fi
        fi
    
        # ── Lista de Flatpaks ──────────────────────────────────────────────
        # IDs validados e confirmados no Flathub (veja auditoria no documento).
        # REMOVIDOS (runtimes — puxados automaticamente como dependências):
        #   io.gitlab.android_translation_layer.BaseApp
        #   io.qt.qtwebengine.BaseApp
        # ADICIONADO: it.mijorus.smile (emoji picker GTK4, ativo em 2025)
        local FLATPAKS=(
            # ── Comunicação ────────────────────────────────────────────────
            "chat.revolt.RevoltDesktop"          # Revolt — alternativa open-source ao Discord
            "io.github.spacingbat3.webcord"      # WebCord — cliente Discord não-oficial
            "org.telegram.desktop"               # Telegram — mensageiro seguro
            "com.microsoft.Edge"                 # Microsoft Edge — browser Chromium/Microsoft
    
            # ── Produtividade e Edição ──────────────────────────────────────
            "io.github.seadve.Kooha"             # Kooha — gravação de tela simples (Wayland nativo)
    
            # ── Jogos e Entretenimento ──────────────────────────────────────
            "com.stremio.Stremio"                # Stremio — agregador de streaming
            "io.itch.itch"                       # itch — cliente da plataforma indie itch.io
            "io.mrarm.mcpelauncher"              # Minecraft Bedrock Launcher
            "org.ppsspp.PPSSPP"                  # PPSSPP — emulador PSP
            "org.vinegarhq.Sober"                # Sober — cliente nativo de Roblox para Linux
            "rocks.shy.VacuumTube"               # VacuumTube — cliente de vídeo YouTube
    
            # ── Gestão de Apps e Sistema ────────────────────────────────────
            "com.github.tchx84.Flatseal"         # Flatseal — gestor de permissões Flatpak
            "it.mijorus.gearlever"               # Gear Lever — gestor e instalador de AppImages
            "io.github.kolunmi.Bazaar"           # Bazaar — browser alternativo de Flatpaks
            "org.flatpak.Builder"                # Flatpak Builder — ferramenta de empacotamento
    
            # ── Download e Armazenamento ────────────────────────────────────
            "com.tonikelope.MegaBasterd"         # MegaBasterd — downloader do Mega.nz
    
            # ── Utilitários ─────────────────────────────────────────────────
            "it.mijorus.smile"                   # Smile — emoji picker GTK4, Wayland nativo
                                                 # Flathub: https://flathub.org/en/apps/it.mijorus.smile
                                                 # Atalho sugerido no rc.xml: Super+Shift+e
                                                 # Comando: flatpak run it.mijorus.smile
            "dev.bragefuglseth.Keypunch"         # Keypunch — treino de digitação
            "org.pvermeer.WebAppHub"             # Web App Hub — cria web apps para o desktop
            "org.adishatz.Screenshot"            # Screenshot — captura de tela alternativa (GTK4)
            "org.gnome.NetworkDisplays"          # GNOME Network Displays — espelhamento Miracast
            "com.github.sdv43.whaler"            # Whaler — GUI para gestão de containers Docker
        )
    
        separador "Instalando ${#FLATPAKS[@]} Flatpaks do Flathub"
        log_info "Instalação em lote — o Flatpak gerencia deps e runtimes automaticamente."
        log_info "Cada app já instalado será pulado ou atualizado silenciosamente."
    
        # Instalação em lote (mais eficiente que instalar um por um).
        # flatpak install -y pula apps já instalados sem erro.
        if sudo -u "${USUARIO_REAL}" \
            flatpak install -y flathub "${FLATPAKS[@]}" >> "${LOG_FILE}" 2>&1; then
            log_ok "Todos os ${#FLATPAKS[@]} Flatpaks instalados com sucesso"
        else
            log_warn "Instalação em lote falhou — tentando individualmente..."
            local falhas=0
            for app in "${FLATPAKS[@]}"; do
                # Pula linhas de comentário (caso o array tenha strings vazias)
                [[ -z "${app}" ]] && continue
                [[ "${app}" == \#* ]] && continue
                log_info "Instalando: ${app}..."
                if sudo -u "${USUARIO_REAL}" \
                    flatpak install -y flathub "${app}" >> "${LOG_FILE}" 2>&1; then
                    log_ok "${app}"
                else
                    log_err "Falha: ${app}"
                    ((falhas++))
                fi
            done
            if [[ $falhas -eq 0 ]]; then
                log_ok "Todos instalados individualmente sem falhas"
            else
                log_err "${falhas} Flatpak(s) falharam — verifique ${LOG_FILE}"
            fi
        fi
    
        # ── Keybind sugerido para o Smile (emoji picker) ───────────────────
        log_info "DICA: Para ativar o Smile com atalho, adicione ao ~/.config/labwc/rc.xml:"
        log_info "  <keybind key=\"Super-Shift-e\">"
        log_info "    <action name=\"Execute\">"
        log_info "      <command>flatpak run it.mijorus.smile</command>"
        log_info "    </action>"
        log_info "  </keybind>"
    }
    
    # ─────────────────────────────────────────────────────────────────────────
    # BLOCO 3: FUNÇÃO 2 — RPMS EXTRAS
    #
    # Instala pacotes RPM que o script mestre NÃO instalou.
    # Verificação explícita antes de cada pacote para idempotência.
    # VLC separado (depende do RPM Fusion ativado na Função 1).
    # Virtualização: instalação individual (sem @virtualization group para
    # controle preciso do que entra no sistema).
    # ─────────────────────────────────────────────────────────────────────────
    
    instalar_rpms_extras() {
        separador "FUNÇÃO 2 — RPMs extras (sem duplicatas do script mestre)"
    
        # ── Utilitários de sistema ─────────────────────────────────────────
        # NÃO instalados: firefox, kate, spectacle, nano, fastfetch (já no mestre)
        log_step "2.1" "Utilitários de sistema e diagnóstico"
        local PKGS_SISTEMA=(
            "btop"               # Monitor de sistema moderno (htop avançado)
            "gnome-disk-utility" # GNOME Disks — gestão de discos e partições
            "mediawriter"        # Fedora Media Writer — criação de USBs bootáveis
            "filelight"          # Visualizador de uso de disco (mapa de árvore KDE)
            "gnome-logs"         # Navegador gráfico do journal systemd (GNOME nativo)
            "menulibre"          # Editor de menus .desktop — compatível com LABWC
                                 # Permite criar/editar entradas no menu de apps
            "wofi"               # Launcher Wayland (alternativa ao dmenu para LABWC)
                                 # Também usado como backend para emoji pickers CLI
        )
        for pkg in "${PKGS_SISTEMA[@]}"; do
            instalar_rpm "$pkg"
        done
    
        # ── Editores e produtividade ───────────────────────────────────────
        log_step "2.2" "Editores e produtividade"
        # NOTA: gedit está disponível no Fedora 44, mas o editor padrão do
        # GNOME 47 passou a ser gnome-text-editor. gedit ainda é funcional.
        local PKGS_PRODUTIVIDADE=(
            "gedit"       # Editor GNOME leve (ainda disponível no Fedora 44)
            "libreoffice" # Suite office completa (Writer, Calc, Impress, Draw)
        )
        for pkg in "${PKGS_PRODUTIVIDADE[@]}"; do
            instalar_rpm "$pkg"
        done
    
        # ── Multimídia ─────────────────────────────────────────────────────
        log_step "2.3" "Multimídia (haruna, mpv, okular, kdenlive, shotcut)"
        local PKGS_MIDIA=(
            "haruna"   # Player KDE baseado em mpv (interface moderna)
            "mpv"      # Player CLI/GPU de alta performance (backend de haruna)
            "okular"   # Leitor universal (PDF, ePub, cBZ, DjVu) KDE
            "kdenlive" # Editor de vídeo profissional KDE (timeline avançada)
            "shotcut"  # Editor de vídeo simples e direto (diferente do kdenlive)
        )
        for pkg in "${PKGS_MIDIA[@]}"; do
            instalar_rpm "$pkg"
        done
    
        # ── VLC (RPM Fusion Free) ──────────────────────────────────────────
        # Separado porque depende do RPM Fusion ativado na Função 1.
        # Instalado por último neste bloco para garantir que o repo está pronto.
        log_step "2.4" "VLC (RPM Fusion Free)"
        if pkg_rpm_instalado "vlc"; then
            log_warn "vlc já instalado — pulando"
        else
            log_info "Instalando vlc (necessita RPM Fusion Free — ativado na etapa 1.1)..."
            if dnf install -y vlc >> "${LOG_FILE}" 2>&1; then
                log_ok "vlc instalado com sucesso"
            else
                log_err "Falha ao instalar vlc — RPM Fusion Free está ativo?"
                log_warn "Verifique: rpm -q rpmfusion-free-release"
            fi
        fi
    
        # ── Diagnóstico SELinux ────────────────────────────────────────────
        log_step "2.5" "SELinux GUI (setroubleshoot + setroubleshoot-server)"
        # setroubleshoot: exibe alertas no GNOME quando SELinux bloqueia algo.
        # sealert: ferramenta CLI para analisar logs AVC do SELinux.
        # setroubleshoot-server: daemon de análise dos logs AVC.
        local PKGS_SELINUX=(
            "setroubleshoot"        # GUI de alertas integrada ao sistema
            "setroubleshoot-server" # Servidor de análise AVC (backend do GUI)
        )
        for pkg in "${PKGS_SELINUX[@]}"; do
            instalar_rpm "$pkg"
        done
    
        # ── Virtualização (KVM + QEMU + Virt-Manager) ─────────────────────
        log_step "2.6" "Virtualização — KVM, QEMU, libvirt, virt-manager, gnome-boxes"
        # Instalação individual (evita o @virtualization group que inclui extras
        # desnecessários como spice-server e outros servidores).
        local PKGS_VIRT=(
            "qemu-kvm"                      # Hypervisor KVM com aceleração de hardware
            "libvirt"                       # API de virtualização e daemon libvirtd
            "libvirt-daemon-config-network" # Rede NAT padrão (virbr0 — necessário)
            "libvirt-daemon-kvm"            # Suporte KVM específico para o libvirt daemon
            "virt-install"                  # Criação de VMs via linha de comando
            "virt-manager"                  # GUI completa para gestão de VMs (avançado)
            "virt-viewer"                   # Visor de consola SPICE/VNC para VMs
            "gnome-boxes"                   # GUI simplificada para VMs (uso casual)
        )
        for pkg in "${PKGS_VIRT[@]}"; do
            instalar_rpm "$pkg"
        done
    
        # Ativar o daemon libvirtd e adicionar o usuário aos grupos necessários.
        # OBRIGATÓRIO para que virt-manager e gnome-boxes acessem KVM sem sudo.
        log_info "Ativando serviço libvirtd..."
        if systemctl enable --now libvirtd >> "${LOG_FILE}" 2>&1; then
            log_ok "libvirtd habilitado e iniciado"
        else
            log_err "Falha ao ativar libvirtd"
        fi
    
        log_info "Adicionando ${USUARIO_REAL} ao grupo libvirt (acesso sem sudo ao virt-manager)..."
        if usermod -aG libvirt "${USUARIO_REAL}" >> "${LOG_FILE}" 2>&1; then
            log_ok "${USUARIO_REAL} → grupo libvirt"
        else
            log_warn "Falha ao adicionar ao grupo libvirt"
        fi
    
        log_info "Adicionando ${USUARIO_REAL} ao grupo kvm (acesso ao dispositivo /dev/kvm)..."
        if usermod -aG kvm "${USUARIO_REAL}" >> "${LOG_FILE}" 2>&1; then
            log_ok "${USUARIO_REAL} → grupo kvm"
        else
            log_warn "Grupo kvm inexistente — normal em algumas configs de Fedora"
        fi
    }
    
    # ─────────────────────────────────────────────────────────────────────────
    # BLOCO 4: FUNÇÃO 3 — INJEÇÃO NO MENU.XML DO LABWC
    #
    # Lê o menu.xml criado pelo script mestre e injeta os novos programas
    # organizados em submenus por categoria, sem apagar as entradas originais.
    #
    # Abordagem: Python3 com env var para o path (sem expansão bash no heredoc).
    # A âncora de injeção é a linha única "Recarregar LABWC" que o script
    # mestre sempre cria. O novo bloco é inserido ANTES dessa âncora.
    #
    # Submenus criados (inline no root-menu — compatível com LABWC):
    #   - Multimídia     (VLC, Haruna, mpv, Kooha, Stremio, VacuumTube)
    #   - Comunicacao    (Telegram, Revolt, WebCord, Edge)
    #   - Produtividade  (LibreOffice, gedit, Kdenlive, Shotcut, Okular)
    #   - Sistema        (Disks, Filelight, Media Writer, Virt, btop, SELinux)
    #   - Jogos          (itch, Minecraft, PPSSPP, Sober)
    #   - Utilitarios    (Flatseal, Gear Lever, Bazaar, Smile, etc.)
    # ─────────────────────────────────────────────────────────────────────────
    
    injetar_no_menu_xml() {
        separador "FUNÇÃO 3 — Injetando novos apps no menu.xml do LABWC"
    
        local MENU_XML="${HOME_REAL}/.config/labwc/menu.xml"
    
        # Verificar se o menu.xml existe (criado pelo script mestre)
        if [[ ! -f "${MENU_XML}" ]]; then
            log_err "menu.xml não encontrado em: ${MENU_XML}"
            log_warn "O script mestre deve ter sido executado primeiro."
            log_warn "Execute: sudo ./INSTALADOR_DEFINITIVO_FEDORA44.sh"
            return 1
        fi
    
        # Backup com timestamp — seguro para re-execução múltipla
        local BACKUP="${MENU_XML}.bak.$(date +%Y%m%d_%H%M%S)"
        cp "${MENU_XML}" "${BACKUP}"
        log_ok "Backup criado: ${BACKUP}"
    
        # Verificar se a âncora existe antes de prosseguir
        if ! grep -q 'label="Recarregar LABWC"' "${MENU_XML}"; then
            log_err "Âncora 'Recarregar LABWC' não encontrada no menu.xml"
            log_warn "O menu.xml pode ter estrutura diferente do esperado."
            log_warn "Restaure o backup e verifique: ${MENU_XML}"
            return 1
        fi
    
        # Verificar se a injeção já foi feita (idempotência)
        if grep -q 'id="complementar-midia"' "${MENU_XML}"; then
            log_warn "Injeção de submenus já realizada — pulando para evitar duplicação."
            log_info "Para re-injetar: restaure o backup com cp ${BACKUP} ${MENU_XML}"
            return 0
        fi
    
        log_info "Injetando submenus via Python3 (XML string replace)..."
    
        # TÉCNICA: HOME_REAL_PY é expandido pelo bash ANTES do heredoc.
        # O heredoc usa aspas simples ('PYEOF') → Python NÃO sofre expansão bash.
        # os.environ['HOME_REAL_PY'] passa o valor expandido para Python.
        HOME_REAL_PY="${HOME_REAL}" python3 << 'PYEOF'
    import os
    import sys
    
    home = os.environ.get('HOME_REAL_PY', '')
    if not home:
        print("ERRO: variável HOME_REAL_PY não definida")
        sys.exit(1)
    
    menu_path = home + '/.config/labwc/menu.xml'
    
    try:
        with open(menu_path, 'r', encoding='utf-8') as f:
            content = f.read()
    except FileNotFoundError:
        print(f"ERRO: arquivo não encontrado: {menu_path}")
        sys.exit(1)
    
    # Âncora exata — única no arquivo, criada pelo script mestre
    ANCHOR = '    <item label="Recarregar LABWC">'
    
    if ANCHOR not in content:
        print("ERRO: âncora 'Recarregar LABWC' não encontrada")
        sys.exit(1)
    
    # ─────────────────────────────────────────────────────────────────
    # BLOCO DE SUBMENUS A INJETAR
    # Submenus inline no root-menu — compatível com LABWC/Openbox.
    # id único por submenu para evitar conflitos com menus existentes.
    # Comandos Flatpak: "flatpak run APP_ID"
    # ─────────────────────────────────────────────────────────────────
    NOVO_BLOCO = """    <separator/>
    <!-- ═══ BLOCOS COMPLEMENTARES (instalados pelo script complementar) ═══ -->
    
    <!-- ── MULTIMÍDIA ───────────────────────────────────────────── -->
    <menu id="complementar-midia" label="Multimidia">
      <item label="VLC Media Player">
        <action name="Execute">
          <command>vlc</command>
        </action>
      </item>
      <item label="Haruna (Player mpv)">
        <action name="Execute">
          <command>haruna</command>
        </action>
      </item>
      <item label="mpv (Player CLI)">
        <action name="Execute">
          <command>mpv</command>
        </action>
      </item>
      <item label="Kooha (Gravacao de Tela)">
        <action name="Execute">
          <command>flatpak run io.github.seadve.Kooha</command>
        </action>
      </item>
      <item label="Stremio (Streaming)">
        <action name="Execute">
          <command>flatpak run com.stremio.Stremio</command>
        </action>
      </item>
      <item label="VacuumTube (YouTube)">
        <action name="Execute">
          <command>flatpak run rocks.shy.VacuumTube</command>
        </action>
      </item>
    </menu>
    
    <!-- ── COMUNICAÇÃO ────────────────────────────────────────────── -->
    <menu id="complementar-comunicacao" label="Comunicacao">
      <item label="Telegram">
        <action name="Execute">
          <command>flatpak run org.telegram.desktop</command>
        </action>
      </item>
      <item label="Revolt (Chat)">
        <action name="Execute">
          <command>flatpak run chat.revolt.RevoltDesktop</command>
        </action>
      </item>
      <item label="WebCord (Discord)">
        <action name="Execute">
          <command>flatpak run io.github.spacingbat3.webcord</command>
        </action>
      </item>
      <item label="Microsoft Edge">
        <action name="Execute">
          <command>flatpak run com.microsoft.Edge</command>
        </action>
      </item>
    </menu>
    
    <!-- ── PRODUTIVIDADE ──────────────────────────────────────────── -->
    <menu id="complementar-produtividade" label="Produtividade">
      <item label="LibreOffice Writer">
        <action name="Execute">
          <command>libreoffice --writer</command>
        </action>
      </item>
      <item label="LibreOffice Calc">
        <action name="Execute">
          <command>libreoffice --calc</command>
        </action>
      </item>
      <item label="LibreOffice Impress">
        <action name="Execute">
          <command>libreoffice --impress</command>
        </action>
      </item>
      <item label="gedit (Editor GNOME)">
        <action name="Execute">
          <command>gedit</command>
        </action>
      </item>
      <item label="Okular (Leitor PDF/ePub)">
        <action name="Execute">
          <command>okular</command>
        </action>
      </item>
      <item label="Kdenlive (Video Editor)">
        <action name="Execute">
          <command>kdenlive</command>
        </action>
      </item>
      <item label="Shotcut (Video Editor)">
        <action name="Execute">
          <command>shotcut</command>
        </action>
      </item>
    </menu>
    
    <!-- ── SISTEMA ────────────────────────────────────────────────── -->
    <menu id="complementar-sistema" label="Sistema">
      <item label="GNOME Disks (Discos)">
        <action name="Execute">
          <command>gnome-disks</command>
        </action>
      </item>
      <item label="Filelight (Uso de Disco)">
        <action name="Execute">
          <command>filelight</command>
        </action>
      </item>
      <item label="Fedora Media Writer">
        <action name="Execute">
          <command>mediawriter</command>
        </action>
      </item>
      <item label="Virt-Manager (VMs Avancado)">
        <action name="Execute">
          <command>virt-manager</command>
        </action>
      </item>
      <item label="GNOME Boxes (VMs Simples)">
        <action name="Execute">
          <command>gnome-boxes</command>
        </action>
      </item>
      <item label="btop (Monitor de Sistema)">
        <action name="Execute">
          <command>alacritty -e btop</command>
        </action>
      </item>
      <item label="SELinux Troubleshooter">
        <action name="Execute">
          <command>sealert -l "*"</command>
        </action>
      </item>
      <item label="Editor de Menus (menulibre)">
        <action name="Execute">
          <command>menulibre</command>
        </action>
      </item>
      <item label="Logs do Sistema (gnome-logs)">
        <action name="Execute">
          <command>gnome-logs</command>
        </action>
      </item>
    </menu>
    
    <!-- ── JOGOS E ENTRETENIMENTO ─────────────────────────────────── -->
    <menu id="complementar-jogos" label="Jogos e Entretenimento">
      <item label="itch.io">
        <action name="Execute">
          <command>flatpak run io.itch.itch</command>
        </action>
      </item>
      <item label="Minecraft Bedrock Launcher">
        <action name="Execute">
          <command>flatpak run io.mrarm.mcpelauncher</command>
        </action>
      </item>
      <item label="PPSSPP (Emulador PSP)">
        <action name="Execute">
          <command>flatpak run org.ppsspp.PPSSPP</command>
        </action>
      </item>
      <item label="Sober (Roblox para Linux)">
        <action name="Execute">
          <command>flatpak run org.vinegarhq.Sober</command>
        </action>
      </item>
    </menu>
    
    <!-- ── UTILITÁRIOS E FERRAMENTAS ──────────────────────────────── -->
    <menu id="complementar-util" label="Utilitarios e Ferramentas">
      <item label="Smile (Emoji Picker)">
        <action name="Execute">
          <command>flatpak run it.mijorus.smile</command>
        </action>
      </item>
      <item label="Flatseal (Permissoes Flatpak)">
        <action name="Execute">
          <command>flatpak run com.github.tchx84.Flatseal</command>
        </action>
      </item>
      <item label="Gear Lever (AppImages)">
        <action name="Execute">
          <command>flatpak run it.mijorus.gearlever</command>
        </action>
      </item>
      <item label="Bazaar (Loja Flatpak)">
        <action name="Execute">
          <command>flatpak run io.github.kolunmi.Bazaar</command>
        </action>
      </item>
      <item label="MegaBasterd (Mega.nz)">
        <action name="Execute">
          <command>flatpak run com.tonikelope.MegaBasterd</command>
        </action>
      </item>
      <item label="Screenshot (Captura Alternativa)">
        <action name="Execute">
          <command>flatpak run org.adishatz.Screenshot</command>
        </action>
      </item>
      <item label="Network Displays (Miracast)">
        <action name="Execute">
          <command>flatpak run org.gnome.NetworkDisplays</command>
        </action>
      </item>
      <item label="Keypunch (Treino Digitacao)">
        <action name="Execute">
          <command>flatpak run dev.bragefuglseth.Keypunch</command>
        </action>
      </item>
      <item label="Web App Hub">
        <action name="Execute">
          <command>flatpak run org.pvermeer.WebAppHub</command>
        </action>
      </item>
      <item label="Whaler (Docker GUI)">
        <action name="Execute">
          <command>flatpak run com.github.sdv43.whaler</command>
        </action>
      </item>
    </menu>
    <separator/>
    """
    
    # Substituição segura: replace() com count=1 garante que apenas a
    # primeira ocorrência da âncora seja substituída.
    new_content = content.replace(ANCHOR, NOVO_BLOCO + ANCHOR, 1)
    
    if new_content == content:
        print("AVISO: substituição não produziu mudança — verifique a âncora")
        sys.exit(1)
    
    try:
        with open(menu_path, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print(f"OK: menu.xml atualizado — {menu_path}")
    except IOError as e:
        print(f"ERRO ao escrever menu.xml: {e}")
        sys.exit(1)
PYEOF
    
        local exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            log_ok "menu.xml atualizado com 6 submenus de novos programas"
            log_info "Submenus adicionados: Multimidia, Comunicacao, Produtividade,"
            log_info "  Sistema, Jogos e Entretenimento, Utilitarios e Ferramentas"
            log_info "Para aplicar sem reiniciar: Super+Shift+r (Reconfigure no LABWC)"
            chown "${USUARIO_REAL}:${USUARIO_REAL}" "${MENU_XML}"
        else
            log_err "Falha na injeção do menu.xml (código: ${exit_code})"
            log_warn "Restaurando backup automático..."
            cp "${BACKUP}" "${MENU_XML}"
            log_info "Backup restaurado: ${BACKUP}"
        fi
    }
    
    # ─────────────────────────────────────────────────────────────────────────
    # BLOCO 5: FUNÇÃO PRINCIPAL (main)
    # ─────────────────────────────────────────────────────────────────────────
    
    main() {
        check_root
    
        # Inicializa log complementar
        mkdir -p "$(dirname "${LOG_FILE}")"
        {
            echo "═══════════════════════════════════════════════════════════"
            echo "  Script Complementar — $(date '+%Y-%m-%d %H:%M:%S')"
            echo "  Usuário alvo: ${USUARIO_REAL}"
            echo "  Home:         ${HOME_REAL}"
            echo "═══════════════════════════════════════════════════════════"
        } > "${LOG_FILE}"
    
        clear
        echo -e "${NEGRITO}${AZUL}"
        echo "  ╔══════════════════════════════════════════════════════════════╗"
        echo "  ║  Script Complementar — Fedora 44 LABWC + Apps               ║"
        echo "  ║  Usuário: ${USUARIO_REAL}                                         ║"
        echo "  ║  Log:     ${LOG_FILE}  ║"
        echo "  ╚══════════════════════════════════════════════════════════════╝"
        echo -e "${RESET}"
    
        # Verifica dependência do script mestre
        if [[ ! -f "${HOME_REAL}/.config/labwc/menu.xml" ]]; then
            log_warn "menu.xml não encontrado — o script mestre pode não ter rodado."
            log_warn "As Funções 1 e 2 rodarão normalmente; a Função 3 será ignorada."
        fi
    
        # Executar as três funções em ordem
        configurar_repos_e_instalar_flatpaks
        instalar_rpms_extras
        injetar_no_menu_xml
    
        # ── Relatório Final ───────────────────────────────────────────────
        separador "RELATÓRIO FINAL — Script Complementar"
    
        if [[ $ERROS -eq 0 ]]; then
            echo -e "${VERDE}${NEGRITO}  ✓ Script complementar concluído SEM ERROS!${RESET}"
        else
            echo -e "${AMARELO}${NEGRITO}  ⚠ Concluído com ${ERROS} erro(s).${RESET}"
            echo -e "  ${VERMELHO}Consulte: ${LOG_FILE}${RESET}"
        fi
    
        echo ""
        echo -e "${NEGRITO}${CIANO}O que foi instalado e configurado:${RESET}"
        echo ""
        echo -e "  ${VERDE}✓${RESET} RPM Fusion Free + Nonfree ativados"
        echo -e "  ${VERDE}✓${RESET} Flathub configurado"
        echo -e "  ${VERDE}✓${RESET} 22 Flatpaks instalados (Telegram, Revolt, WebCord, Stremio,"
        echo -e "       Kooha, MegaBasterd, Keypunch, Bazaar, itch, Minecraft Bedrock,"
        echo -e "       PPSSPP, Sober, VacuumTube, Edge, Flatseal, Gear Lever,"
        echo -e "       Screenshot, Net Displays, Web App Hub, Whaler, Flatpak Builder,"
        echo -e "       Smile emoji picker)"
        echo -e "  ${VERDE}✓${RESET} RPMs extras: btop, gnome-disks, mediawriter, filelight,"
        echo -e "       gedit, libreoffice, haruna, mpv, okular, kdenlive, shotcut, vlc,"
        echo -e "       setroubleshoot, menulibre, wofi"
        echo -e "  ${VERDE}✓${RESET} Virtualização: virt-manager + qemu-kvm + libvirt + gnome-boxes"
        echo -e "       libvirtd ativado | ${USUARIO_REAL} → grupos libvirt + kvm"
        echo -e "  ${VERDE}✓${RESET} menu.xml do LABWC: 6 submenus injetados:"
        echo -e "       Multimidia | Comunicacao | Produtividade"
        echo -e "       Sistema | Jogos | Utilitarios"
        echo ""
        echo -e "${NEGRITO}${AMARELO}Próximos passos:${RESET}"
        echo ""
        echo -e "  ${CIANO}1.${RESET} Reinicie a sessão para ativar grupos libvirt/kvm:"
        echo -e "     ${AZUL}sudo reboot${RESET}"
        echo ""
        echo -e "  ${CIANO}2.${RESET} Recarregue o LABWC para ver os novos submenus:"
        echo -e "     ${AZUL}Super+Shift+r${RESET} (Reconfigure, sem reiniciar a sessão)"
        echo ""
        echo -e "  ${CIANO}3.${RESET} Adicione atalho para o Smile (emoji picker) no rc.xml:"
        echo -e "     ${AZUL}kate ~/.config/labwc/rc.xml${RESET} → adicione:"
        echo -e "     ${AZUL}<keybind key=\"Super-Shift-e\">${RESET}"
        echo -e "     ${AZUL}  <action name=\"Execute\">${RESET}"
        echo -e "     ${AZUL}    <command>flatpak run it.mijorus.smile</command>${RESET}"
        echo -e "     ${AZUL}  </action>${RESET}"
        echo -e "     ${AZUL}</keybind>${RESET}"
        echo ""
        echo -e "  ${CIANO}4.${RESET} Para VMs: use ${AZUL}virt-manager${RESET} (avançado) ou ${AZUL}gnome-boxes${RESET} (simples)"
        echo ""
        echo -e "  ${VERMELHO}Log complementar: ${LOG_FILE}${RESET}"
        echo ""
    }
    
    # ─────────────────────────────────────────────────────────────────────────
    # PONTO DE ENTRADA
    # ─────────────────────────────────────────────────────────────────────────
    main "$@"
