#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
#   IRAN VPN SERVER READINESS TESTER  v4.1
#   Sources: iAghapour Digital Freedom + net4people/bbs + wartime Iran Apr 2026
#   USAGE: bash iran-server-tester-v4.sh [--quick|--html|--probe-server[=PORT]]
# ═══════════════════════════════════════════════════════════════════════════════

VERSION="4.1"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

SCORE=0
declare -a ISSUES ACTIONS INSTALL_CMDS
BEST_SNI=""; declare -a GOOD_SNIS
PROBE_PORT=9999; HTML_MODE=0; QUICK_MODE=0; PROBE_SERVER_MODE=0
MY_IP=""; HTML_BODY=""
HTML_FILE="/tmp/iran-report-$(date +%Y%m%d-%H%M%S).html"

for arg in "$@"; do
    case "$arg" in
        --probe-server)    PROBE_SERVER_MODE=1 ;;
        --probe-server=*)  PROBE_SERVER_MODE=1; PROBE_PORT="${arg#*=}" ;;
        --html)            HTML_MODE=1 ;;
        --quick)           QUICK_MODE=1 ;;
        --port=*)          PROBE_PORT="${arg#*=}" ;;
    esac
done

# ── All log functions return 0 explicitly (critical for || chaining) ──────
ok()       { echo -e "  ${GREEN}[✔]${NC} $1"; HTML_BODY+="<li class='ok'>✔ $1</li>"; return 0; }
fail()     { echo -e "  ${RED}[✖]${NC} $1"; ISSUES+=("$1"); HTML_BODY+="<li class='fail'>✖ $1</li>"; return 0; }
warn()     { echo -e "  ${YELLOW}[⚠]${NC} $1"; HTML_BODY+="<li class='warn'>⚠ $1</li>"; return 0; }
info()     { echo -e "  ${BLUE}[ℹ]${NC} $1"; HTML_BODY+="<li class='info'>ℹ $1</li>"; return 0; }
action()   { ACTIONS+=("$1"); return 0; }
cmd_note() { INSTALL_CMDS+=("$1"); return 0; }
add()      { SCORE=$((SCORE+$1)); return 0; }
sub()      { SCORE=$((SCORE-$1)); [[ $SCORE -lt 0 ]] && SCORE=0; return 0; }

section() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    printf "${CYAN}║${NC}  ${BOLD}%-54s${NC}  ${CYAN}║${NC}\n" "$1"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    HTML_BODY+="<h2>$1</h2><ul>"
    return 0  # always 0
}
section_end() { HTML_BODY+="</ul>"; return 0; }  # KEY FIX: explicit return 0

banner() {
    clear; echo -e "${CYAN}"
    cat << 'BANNER'
  ██╗██████╗  █████╗ ███╗   ██╗    ██╗   ██╗██████╗ ███╗   ██╗    ██╗   ██╗██╗  ██╗
  ██║██╔══██╗██╔══██╗████╗  ██║    ██║   ██║██╔══██╗████╗  ██║    ██║   ██║██║  ██║
  ██║██████╔╝███████║██╔██╗ ██║    ██║   ██║██████╔╝██╔██╗ ██║    ██║   ██║███████║
  ██║██╔══██╗██╔══██║██║╚██╗██║    ╚██╗ ██╔╝██╔═══╝ ██║╚██╗██║    ╚██╗ ██╔╝╚════██║
  ██║██║  ██║██║  ██║██║ ╚████║     ╚████╔╝ ██║     ██║ ╚████║     ╚████╔╝      ██║
  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝      ╚═══╝  ╚═╝     ╚═╝  ╚═══╝      ╚═══╝       ╚═╝
BANNER
    echo -e "${NC}"
    echo -e "  ${BOLD}${CYAN}Iran VPN Server Intelligence Tester  v${VERSION}${NC}"
    echo -e "  ${DIM}Sources: iAghapour + net4people/bbs + wartime Iran Apr 2026${NC}"
    echo -e "  ${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "  ${YELLOW}Phases: ASN · Install · Ports · Network · SNI · DNS · Protocol · System${NC}"
    echo ""
    return 0
}

install_deps() {
    local needed=0
    for tool in curl nc ping dig openssl mtr; do command -v "$tool" &>/dev/null || needed=1; done
    if [[ $needed -eq 1 ]]; then
        echo -e "  ${YELLOW}[→] Installing required tools...${NC}"
        apt-get update -qq 2>/dev/null && \
        apt-get install -yqq curl mtr netcat-openbsd iputils-ping dnsutils openssl 2>/dev/null || \
        yum install -yq curl nc bind-utils openssl mtr 2>/dev/null || true
    fi
    return 0
}

detect_my_ip() {
    local eps=("https://api.ipify.org" "https://icanhazip.com" \
                "https://checkip.amazonaws.com" "https://ifconfig.me")
    for ep in "${eps[@]}"; do
        local ip; ip=$(curl -s --max-time 6 "$ep" 2>/dev/null | tr -d '[:space:]')
        if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then MY_IP="$ip"; return 0; fi
    done
    return 1
}

# ═══════════════════════════════════════════════════════════════════════════
# PROBE SERVER MODE
# ═══════════════════════════════════════════════════════════════════════════
run_probe_server() {
    banner
    section "PROBE SERVER  Listening for Iran Clients"
    detect_my_ip || MY_IP="(unknown)"
    ufw allow "$PROBE_PORT"/tcp 2>/dev/null || \
        iptables -I INPUT -p tcp --dport "$PROBE_PORT" -j ACCEPT 2>/dev/null
    info "Server IP  : ${BOLD}$MY_IP${NC}"
    info "Probe port : ${BOLD}$PROBE_PORT${NC}"
    echo ""
    echo -e "  ${BOLD}On Windows PC inside Iran — run iran-probe-client.bat${NC}"
    echo -e "  ${CYAN}  Server IP  : ${BOLD}$MY_IP${NC}"
    echo -e "  ${CYAN}  Probe port : ${BOLD}$PROBE_PORT${NC}"
    echo -e "  ${YELLOW}  Listening... (Ctrl+C to stop)${NC}"
    echo ""
    local RESP="HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nX-Iran-Probe: v${VERSION}\r\n\r\nPROBE_OK|v=${VERSION}|ts=$(date +%s)\r\n"
    while true; do
        local RAW; RAW=$(printf '%b' "$RESP" | timeout 15 nc -l -p "$PROBE_PORT" -q 2 2>/dev/null)
        if [[ $? -eq 0 ]]; then
            local TS; TS=$(date '+%H:%M:%S')
            local ISP; ISP=$(echo "$RAW" | grep -oP 'isp=[^|&\r\n]+' | cut -d= -f2-)
            local LAT; LAT=$(echo "$RAW" | grep -oP 'lat=[^|&\r\n]+' | cut -d= -f2-)
            echo -e "  ${GREEN}${BOLD}[$TS] ✅ Connection from Iran received!${NC}"
            [[ -n "$ISP" ]] && echo -e "  ${CYAN}  ISP: $ISP${NC}"
            [[ -n "$LAT" ]] && echo -e "  ${CYAN}  RTT: ${LAT}ms${NC}"
            echo -e "  ${GREEN}  → THIS SERVER IS REACHABLE FROM IRAN ✅${NC}"; echo ""
        fi
        sleep 1
    done
}

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 1 — SERVER IDENTITY
# ═══════════════════════════════════════════════════════════════════════════
phase1_identity() {
    section "PHASE 1  SERVER IDENTITY & DATACENTER ANALYSIS"
    if ! detect_my_ip; then
        fail "Cannot detect server IP — internet unreachable from this server"
        section_end; return 1
    fi
    info "Server IP: ${BOLD}$MY_IP${NC}"
    local IPINFO; IPINFO=$(curl -s --max-time 8 "https://ipinfo.io/${MY_IP}/json" 2>/dev/null)
    local ASN CITY COUNTRY AS_NUM DC_NAME
    ASN=$(echo     "$IPINFO" | grep -o '"org":"[^"]*"'     | sed 's/"org":"//;s/"//g' | head -1)
    CITY=$(echo    "$IPINFO" | grep -o '"city":"[^"]*"'    | sed 's/"city":"//;s/"//g' | head -1)
    COUNTRY=$(echo "$IPINFO" | grep -o '"country":"[^"]*"' | sed 's/"country":"//;s/"//g' | head -1)
    AS_NUM=$(echo "$ASN" | grep -oP 'AS\d+' | head -1)
    DC_NAME=$(echo "$ASN" | sed 's/AS[0-9]* //' | head -1)
    info "Location : ${BOLD}${CITY:-(unknown)}, ${COUNTRY:-(unknown)}${NC}"
    info "ASN      : ${BOLD}${AS_NUM:-UNKNOWN} — ${DC_NAME:-(unknown)}${NC}"

    declare -A ASN_DB=(
        ["AS24940"]="Hetzner:1"       ["AS51167"]="Contabo:1"      ["AS34549"]="Neterra:1"
        ["AS9009"]="M247:1"           ["AS47583"]="Hostinger:1"    ["AS40676"]="Psychz:1"
        ["AS62240"]="Clouvider:1"     ["AS59253"]="Liteserver:1"   ["AS60781"]="Leaseweb-NL:1"
        ["AS24911"]="Frantech:1"      ["AS36352"]="ColoCrossing:1"
        ["AS14061"]="DigitalOcean:2"  ["AS20473"]="Vultr:2"        ["AS63949"]="Akamai-Linode:2"
        ["AS16125"]="Kamatera:2"      ["AS199599"]="NGSAS:2"       ["AS55720"]="Gigabit-NL:2"
        ["AS15169"]="Google-GCP:3"    ["AS16509"]="Amazon-AWS:3"   ["AS8075"]="Microsoft-Azure:3"
        ["AS20940"]="Akamai:3"        ["AS13335"]="Cloudflare:3"
        ["AS16276"]="OVH-France:BAD"  ["AS3215"]="OVH-Paris:BAD"   ["AS12322"]="OVH-EU:BAD"
        ["AS5577"]="Root-SA:BAD"      ["AS199524"]="GCore-Labs:BAD" ["AS209017"]="Quasinetworks:BAD"
    )
    local TIER="UNKNOWN" DC_LABEL=""
    if [[ -n "$AS_NUM" && -n "${ASN_DB[$AS_NUM]:-}" ]]; then
        TIER="${ASN_DB[$AS_NUM]##*:}"; DC_LABEL="${ASN_DB[$AS_NUM]%%:*}"
    fi
    case $TIER in
        1)   ok   "ASN ${AS_NUM} (${DC_LABEL}) — Tier 1 ✅ Best for Iran"; add 30 ;;
        2)   ok   "ASN ${AS_NUM} (${DC_LABEL}) — Tier 2: usually works"; add 18 ;;
        3)   warn "ASN ${AS_NUM} (${DC_LABEL}) — Tier 3: monitored by Iran DPI"; add 8 ;;
        BAD) fail "ASN ${AS_NUM} (${DC_LABEL}) — 🔴 KNOWN-BLOCKED in Iran"; sub 35
             action "CRITICAL: Change to Hetzner Finland (hetzner.com)" ;;
        *)   warn "ASN ${AS_NUM:-UNDETECTED} — Unknown datacenter"; add 10 ;;
    esac

    local GOOD_C=("DE" "FI" "SE" "NL" "CH" "AT" "CZ" "PL" "HU" "SK" "BG" "RO" "NO" "DK")
    local WARN_C=("AZ" "TR" "GE" "AM" "UA")
    local BAD_C=("RU" "CN" "IR" "KP")
    local IS_GOOD=0 IS_WARN=0 IS_BAD=0
    for c in "${GOOD_C[@]}"; do [[ "$COUNTRY" == "$c" ]] && IS_GOOD=1; done
    for c in "${WARN_C[@]}"; do [[ "$COUNTRY" == "$c" ]] && IS_WARN=1; done
    for c in "${BAD_C[@]}"; do [[ "$COUNTRY" == "$c" ]] && IS_BAD=1; done

    if   [[ $IS_GOOD -eq 1 ]];    then ok   "Location ${COUNTRY} — Optimal (Central/Northern Europe)"; add 15
    elif [[ "$COUNTRY" == "FR" ]]; then warn "France: OVH routing unreliable for Iran since 2025"; sub 8
    elif [[ $IS_WARN -eq 1 ]];    then warn "Location ${COUNTRY} (CIS/Caucasus): AZ-IX monitored by Iran DPI"; add 4
    elif [[ $IS_BAD -eq 1 ]];     then fail "Location ${COUNTRY} — High-risk zone"; sub 20
    else                               warn "Location ${COUNTRY}: unknown reliability"; add 8
    fi
    section_end; return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 2 — INSTALLATION REACHABILITY
# ═══════════════════════════════════════════════════════════════════════════
phase2_install() {
    section "PHASE 2  INSTALLATION REACHABILITY (CRITICAL)"
    info "Testing all package sources needed for deployment..."
    declare -A EP=(
        ["raw.githubusercontent (3X-UI)"]="https://raw.githubusercontent.com/mhsanaei/3x-ui/master/README.md"
        ["github.com"]="https://github.com"
        ["MasterDnsVPN script"]="https://raw.githubusercontent.com/masterking32/MasterDnsVPN/main/server_linux_install.sh"
        ["VayDNS script"]="https://raw.githubusercontent.com/net2share/vaydns/main/install.sh"
    )
    local ALL_OK=1
    for name in "${!EP[@]}"; do
        local ST; ST=$(curl -s --max-time 8 -o /dev/null -w "%{http_code}" "${EP[$name]}" 2>/dev/null)
        if [[ "$ST" =~ ^(200|301|302)$ ]]; then ok "$name — REACHABLE"; add 3
        else warn "$name — UNREACHABLE (${ST:-timeout})"; ALL_OK=0; fi
    done
    [[ $ALL_OK -eq 0 ]] && { warn "Fix DNS: printf 'nameserver 8.8.8.8\\n' > /etc/resolv.conf"; sub 8
        action "Fix DNS: printf 'nameserver 8.8.8.8\\nnameserver 1.1.1.1\\n' > /etc/resolv.conf"; } || \
        { ok "All sources reachable"; add 8; }
    local DNS_R; DNS_R=$(dig +short +time=3 github.com 2>/dev/null | grep -E '^[0-9]' | head -1)
    if [[ -n "$DNS_R" ]]; then ok "DNS healthy (github.com → $DNS_R)"
    else fail "DNS broken — fix before proceeding"; sub 15
         action "echo 'nameserver 8.8.8.8' > /etc/resolv.conf"; fi
    section_end; return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 3 — PORTS & SERVICES
# ═══════════════════════════════════════════════════════════════════════════
phase3_ports() {
    section "PHASE 3  PORT & SERVICE READINESS"
    local TLISTENING; TLISTENING=$(ss -tlnp 2>/dev/null)
    local ULISTENING; ULISTENING=$(ss -ulnp 2>/dev/null)
    echo "$TLISTENING" | grep -q ":443 " && \
        ok "Port 443 OPEN" && add 8 || { info "Port 443 available — ready for 3X-UI"; add 5; }
    echo "$TLISTENING" | grep -q ":80 "  && ok "Port 80 OPEN" || info "Port 80 available"
    local UDP53; UDP53=$(echo "$ULISTENING" | grep ":53 ")
    if [[ -n "$UDP53" ]]; then
        warn "Port 53 UDP in use — conflicts with MasterDNS/VayDNS"
        action "systemctl stop systemd-resolved && systemctl disable systemd-resolved"
    else ok "Port 53 UDP free — MasterDNS/VayDNS ready"; add 8; fi
    local RESOLVED; RESOLVED=$(systemctl is-active systemd-resolved 2>/dev/null)
    [[ "$RESOLVED" == "active" ]] && warn "systemd-resolved active — conflicts on port 53" && \
        action "systemctl stop systemd-resolved && systemctl disable systemd-resolved"
    if command -v x-ui &>/dev/null || systemctl list-units 2>/dev/null | grep -q "x-ui"; then
        ok "3X-UI panel installed"; add 8
        local XS; XS=$(systemctl is-active x-ui 2>/dev/null)
        [[ "$XS" == "active" ]] && ok "3X-UI RUNNING" || warn "3X-UI not running"
        local XB; XB=$(find /usr/local/x-ui /root -name "xray-linux-amd64" 2>/dev/null | head -1)
        if [[ -n "$XB" ]]; then
            local XV; XV=$("$XB" version 2>/dev/null | head -1)
            local XM; XM=$(echo "$XV" | grep -oP '\b1\.(\d+)\.' | grep -oP '\d+' | tail -1)
            info "Xray: $XV"
            [[ ${XM:-0} -ge 8 ]] && ok "Xray 1.8+ — XHTTP supported" && add 5 || \
                warn "Old Xray — upgrade: x-ui → option 2"
        fi
    else info "3X-UI not installed (fresh)"; fi
    local BBR; BBR=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
    [[ "$BBR" == "bbr" ]] && ok "BBR active" && add 8 || \
        { warn "BBR inactive (${BBR:-unknown}) — Iran throttles heavily without BBR"
          sub 5; action "Enable BBR: x-ui → option 24"; }
    local UFW; UFW=$(ufw status 2>/dev/null | head -1)
    if echo "$UFW" | grep -q "active"; then
        info "UFW active"
        local P443; P443=$(ufw status 2>/dev/null | grep -c "443" 2>/dev/null || echo 0)
        [[ ${P443:-0} -gt 0 ]] && ok "Port 443 allowed in UFW" || \
            { warn "Port 443 may be blocked"; action "ufw allow 443 && ufw allow 80 && ufw allow 53/udp && ufw reload"; }
    fi
    section_end; return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 4 — NETWORK & IRAN ROUTING
# ═══════════════════════════════════════════════════════════════════════════
phase4_network() {
    section "PHASE 4  NETWORK QUALITY & IRAN ROUTING"
    declare -A ISP=(
        ["185.51.201.1"]="MCI/Hamrah-Aval AS44244"
        ["5.200.200.200"]="IranCell AS44278"
        ["217.218.127.127"]="TIC Gateway AS12880"
        ["91.99.96.1"]="Shatel AS48159"
        ["78.39.193.1"]="Rightel AS49100"
    )
    local REACH=0
    for IP in "${!ISP[@]}"; do
        local R; R=$(ping -c 3 -W 2 "$IP" 2>/dev/null)
        if echo "$R" | grep -q "bytes from"; then
            local RTT; RTT=$(echo "$R" | grep "avg" | awk -F'/' '{printf "%.0f",$5}' 2>/dev/null)
            ok "${ISP[$IP]} — RTT: ${RTT:-?}ms"; REACH=$((REACH+1)); add 4
        else info "${ISP[$IP]} — not directly reachable (asymmetric routing normal)"; fi
    done
    [[ $REACH -ge 2 ]] && ok "Good bidirectional routing ($REACH ISPs reachable)" && add 5
    if [[ $QUICK_MODE -eq 0 ]]; then
        info "MTR trace to TIC gateway..."
        local MTR; MTR=$(mtr -r -c 3 -T -P 80 217.218.127.127 2>/dev/null | tail -8)
        [[ -n "$MTR" ]] && echo "$MTR" | while IFS= read -r l; do echo -e "  ${DIM}$l${NC}"; done
        echo "$MTR" | grep -qi "az-ix\|az\.net\|baku" && \
            warn "Route via AZ-IX (Azerbaijan) — Iran DPI monitors this peering point"
    fi
    local CFR; CFR=$(ping -c 3 -W 3 1.1.1.1 2>/dev/null | grep "avg" | awk -F'/' '{printf "%.0f",$5}')
    if [[ -n "$CFR" ]]; then
        info "Cloudflare (1.1.1.1): ${CFR}ms"
        if   [[ $CFR -lt 15 ]]; then ok  "Cloudflare proximity EXCELLENT (<15ms)"; add 10
        elif [[ $CFR -lt 40 ]]; then ok  "Cloudflare proximity GOOD (${CFR}ms)"; add 6
        elif [[ $CFR -lt 80 ]]; then warn "Cloudflare moderate (${CFR}ms)"; add 3
        else                         warn "High Cloudflare latency (${CFR}ms)"; fi
    fi
    info "Testing outbound ports..."
    for port in 443 80 8443 8080; do
        nc -w 3 -z 1.1.1.1 $port 2>/dev/null && ok "Outbound port $port — OPEN" || warn "Outbound port $port — blocked"
    done
    local MTU; MTU=$(ping -c 2 -M do -s 1400 8.8.8.8 2>/dev/null | grep -c "bytes from" 2>/dev/null || echo 0)
    [[ $MTU -gt 0 ]] && ok "MTU 1400 — OK" && add 3 || \
        { warn "MTU issues — add Fragment to xray config"
          action "Add to xray outbound: 'fragment':{'packets':'tlshello','length':'10-20'}"; }
    local IP6; IP6=$(ip -6 addr show 2>/dev/null | grep -v "::1\|fe80" | grep -c "inet6" 2>/dev/null || echo 0)
    [[ $IP6 -gt 0 ]] && ok "IPv6 available — some ISPs bypass DPI via IPv6" && add 3 || info "IPv4 only"
    section_end; return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 5 — SNI & TLS
# ═══════════════════════════════════════════════════════════════════════════
phase5_sni() {
    section "PHASE 5  SNI & TLS CAMOUFLAGE"
    info "Testing SNI domains for Reality config (Iran whitelist matching)..."
    echo ""
    declare -a SNI_LIST=(
        "www.microsoft.com:HIGH:Iran whitelist ★★★ TOP CHOICE"
        "www.bing.com:HIGH:Iran whitelist ★★★"
        "update.microsoft.com:HIGH:Microsoft update — whitelisted"
        "www.apple.com:HIGH:Apple CDN — whitelisted"
        "www.samsung.com:MED:Less monitored — good"
        "addons.mozilla.org:MED:Mozilla — often works"
        "www.amazon.com:MED:Amazon CDN"
        "www.google.com:MED:Sometimes allowed"
        "ajax.googleapis.com:MED:Google CDN"
        "www.speedtest.net:LOW:⚠️ NOW MONITORED — avoid"
    )
    printf "  ${BOLD}%-36s %-12s %s${NC}\n" "DOMAIN" "STATUS" "PRIORITY"
    echo -e "  $(printf '─%.0s' {1..68})"
    for entry in "${SNI_LIST[@]}"; do
        local DOMAIN="${entry%%:*}" rest="${entry#*:}" PRIO NOTE TLS_OK=0
        PRIO="${rest%%:*}"; NOTE="${rest##*:}"
        local TLS_OUT; TLS_OUT=$(echo "Q" | timeout 4 openssl s_client \
            -connect "${DOMAIN}:443" -servername "$DOMAIN" \
            -verify_return_error 2>/dev/null | head -3)
        echo "$TLS_OUT" | grep -q "CONNECTED" && TLS_OK=1
        if [[ $TLS_OK -eq 0 ]]; then
            local HC; HC=$(curl -s --max-time 4 -o /dev/null -w "%{http_code}" "https://$DOMAIN" 2>/dev/null)
            [[ "$HC" =~ ^(200|301|302|307|308)$ ]] && TLS_OK=1
        fi
        if [[ $TLS_OK -eq 1 ]]; then
            GOOD_SNIS+=("$DOMAIN")
            [[ -z "$BEST_SNI" && "$PRIO" == "HIGH" ]] && BEST_SNI="$DOMAIN"
            printf "  ${GREEN}[✔]${NC}  %-33s ${GREEN}%-12s${NC} ${DIM}%s${NC}\n" "$DOMAIN" "REACHABLE" "$PRIO→$NOTE"
        else
            printf "  ${RED}[✖]${NC}  %-33s ${RED}%-12s${NC} ${DIM}%s${NC}\n" "$DOMAIN" "UNREACHABLE" "$PRIO"
        fi
    done
    echo ""
    local SC=${#GOOD_SNIS[@]}
    if   [[ $SC -ge 6 ]]; then ok "$SC SNI candidates — excellent"; add 15
    elif [[ $SC -ge 3 ]]; then ok "$SC SNI candidates — adequate"; add 8
    elif [[ $SC -ge 1 ]]; then warn "Only $SC SNI — limited"; add 3
    else fail "No SNI reachable — server has egress restrictions"; sub 15; fi
    [[ -z "$BEST_SNI" && $SC -gt 0 ]] && BEST_SNI="${GOOD_SNIS[0]}"
    [[ -z "$BEST_SNI" ]] && BEST_SNI="www.microsoft.com"
    echo -e "\n  ${BOLD}Best SNI for Reality:${NC}"
    for sni in "${GOOD_SNIS[@]:0:3}"; do echo -e "  ${GREEN}  → sni=${sni}${NC}"; done
    section_end; return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 6 — DNS TUNNEL
# ═══════════════════════════════════════════════════════════════════════════
phase6_dns_tunnel() {
    section "PHASE 6  DNS TUNNEL (MasterDNS & VayDNS)"
    info "In wartime Iran Apr 2026 — DNS tunnel is the most stable method"
    echo ""
    local DR=0
    nc -w 2 -zu 8.8.8.8 53 2>/dev/null && \
        { ok "UDP port 53 outbound — WORKS"; DR=$((DR+1)); add 5; } || \
        warn "UDP port 53 outbound restricted"
    nc -w 3 -z 8.8.8.8 53 2>/dev/null && \
        { ok "TCP port 53 — WORKS (fallback)"; DR=$((DR+1)); add 5; } || \
        warn "TCP port 53 blocked"
    dig +short +timeout=3 "a.b.com" @8.8.8.8 &>/dev/null && \
        ok "Short DNS queries work — max-qname-len=101 will function" && add 5
    local DOH; DOH=$(curl -s --max-time 4 \
        "https://cloudflare-dns.com/dns-query?name=google.com&type=A" \
        -H "accept: application/dns-json" 2>/dev/null | grep -c "Answer" 2>/dev/null || echo 0)
    [[ $DOH -gt 0 ]] && ok "DoH works — usable as backup resolver" && add 3
    local DA; DA=$(dig +short +timeout=3 @"$MY_IP" google.com 2>/dev/null | grep -E '^[0-9]' | head -1)
    [[ -n "$DA" ]] && ok "Server acts as DNS resolver — MasterDNS/VayDNS ready" && add 8 || \
        info "DNS resolver not yet configured"
    echo ""
    local MS; MS=$(curl -s --max-time 6 -o /dev/null -w "%{http_code}" \
        "https://raw.githubusercontent.com/masterking32/MasterDnsVPN/main/server_linux_install.sh")
    [[ "$MS" == "200" ]] && \
        { ok "MasterDnsVPN install reachable"; add 5
          cmd_note "MasterDnsVPN: bash <(curl -Ls https://raw.githubusercontent.com/masterking32/MasterDnsVPN/main/server_linux_install.sh)"; } || \
        { warn "MasterDnsVPN unreachable — fix DNS first"
          action "Fix DNS then: bash <(curl -Ls https://raw.githubusercontent.com/masterking32/MasterDnsVPN/main/server_linux_install.sh)"; }
    local VS; VS=$(curl -s --max-time 6 -o /dev/null -w "%{http_code}" \
        "https://raw.githubusercontent.com/net2share/vaydns/main/install.sh")
    [[ "$VS" == "200" ]] && \
        { ok "VayDNS install reachable"
          cmd_note "VayDNS: bash <(curl -Ls https://raw.githubusercontent.com/net2share/vaydns/main/install.sh)"; } || \
        warn "VayDNS unreachable"
    [[ $DR -ge 2 ]] && ok "Server DNS TUNNEL READY" && add 10 || \
        warn "DNS tunnel prerequisites partial"
    echo ""
    echo -e "  ${BOLD}${CYAN}Critical settings (Apr 2026):${NC}"
    echo -e "  ${YELLOW}  • max-qname-len=101 (NOT 253) — Iran DPI drops queries >110 chars${NC}"
    echo -e "  ${YELLOW}  • Keep domain SHORT: v.ab.ir — not long.subdomain.domain.com${NC}"
    echo -e "  ${YELLOW}  • Stop systemd-resolved BEFORE install (port 53 conflict)${NC}"
    section_end; return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 7 — PROTOCOL & PANEL
# ═══════════════════════════════════════════════════════════════════════════
phase7_protocols() {
    section "PHASE 7  PROTOCOL & PANEL RECOMMENDATIONS"
    echo ""
    local SHOW_REALITY=1; [[ $SCORE -lt 45 ]] && SHOW_REALITY=0
    echo -e "  ${BOLD}${GREEN}═══ TIER 1 — Wartime Iran ═══${NC}"
    echo ""
    echo -e "  ${GREEN}[★★★★★]${NC} ${BOLD}VLESS + DNS Tunnel (MasterDnsVPN / VayDNS)${NC}"
    echo -e "         ${DIM}Only consistently stable method in extreme censorship${NC}"
    echo -e "         ${CYAN}max-qname-len=101 | short domain | stop systemd-resolved${NC}"
    echo ""
    echo -e "  ${GREEN}[★★★★☆]${NC} ${BOLD}VLESS + WebSocket + TLS via Cloudflare CDN${NC}"
    echo -e "         ${DIM}Hides real IP behind CF — proven stable long-term${NC}"
    echo -e "         ${CYAN}network=ws, security=tls, domain → CF proxied ON${NC}"
    echo ""
    echo -e "  ${BOLD}${YELLOW}═══ TIER 2 — Clean/Fresh IPs ═══${NC}"
    echo ""
    echo -e "  ${YELLOW}[★★★★☆]${NC} ${BOLD}VLESS + XHTTP (SplitHTTP) via Cloudflare CDN${NC}"
    echo -e "         ${DIM}Xray 1.8+ — beats WS fingerprinting in 2026${NC}"
    if [[ $SHOW_REALITY -eq 1 ]]; then
        echo ""
        echo -e "  ${YELLOW}[★★★☆☆]${NC} ${BOLD}VLESS + Reality + xtls-rprx-vision + uTLS=chrome${NC}"
        echo -e "         ${DIM}Works on fresh IPs — gets blocked quickly on popular DCs${NC}"
        echo -e "         ${CYAN}sni=${BEST_SNI} | flow=xtls-rprx-vision | fp=chrome${NC}"
    fi
    echo ""
    echo -e "  ${BOLD}${RED}═══ BLOCKED ═══${NC}"
    echo -e "  ${RED}  ✖ WireGuard / OpenVPN — blocked in <1 second${NC}"
    echo -e "  ${RED}  ✖ VLESS plain TCP — immediately detectable${NC}"
    echo ""
    echo -e "  ${BOLD}Panel Matrix:${NC}"
    printf "\n  ${BOLD}%-8s %-28s %-10s %s${NC}\n" "SCORE" "PANEL" "FIT" "REPO"
    echo -e "  $(printf '─%.0s' {1..70})"
    echo -e "  ${GREEN}★★★★★${NC}  3X-UI (mhsanaei)            ${GREEN}EXCELLENT${NC}  MHSanaei/3x-ui"
    echo -e "  ${GREEN}★★★★★${NC}  MasterDnsVPN                ${GREEN}EXCELLENT${NC}  masterking32/MasterDnsVPN"
    echo -e "  ${GREEN}★★★★☆${NC}  VayDNS                      ${GREEN}EXCELLENT${NC}  net2share/vaydns"
    echo -e "  ${YELLOW}★★★☆☆${NC}  Hiddify Panel               ${YELLOW}GOOD${NC}      hiddify/hiddify-manager"
    echo -e "  ${YELLOW}★★★☆☆${NC}  Marzban                     ${YELLOW}GOOD${NC}      Gozargah/Marzban"
    echo -e "  ${RED}★★☆☆☆${NC}  x-ui (alireza0)              ${RED}OUTDATED${NC}  use 3X-UI instead"
    section_end; return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 8 — SYSTEM
# ═══════════════════════════════════════════════════════════════════════════
phase8_system() {
    section "PHASE 8  SYSTEM RESOURCES"
    local OS; OS=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2)
    local RAM; RAM=$(free -m 2>/dev/null | awk '/Mem:/{print $2}')
    local DISK; DISK=$(df -h / 2>/dev/null | awk 'NR==2{print $4}')
    local CORES; CORES=$(nproc 2>/dev/null || echo "?")
    info "OS    : $OS"; info "CPU   : ${CORES} core(s)"
    info "RAM   : ${RAM:-?}MB"; info "Disk  : $DISK free"
    echo "$OS" | grep -qiE "Ubuntu 22|Ubuntu 24|Debian 11|Debian 12" && \
        { ok "OS fully supported"; add 5; } || warn "Non-standard OS"
    if   [[ ${RAM:-0} -ge 2048 ]]; then ok "RAM ${RAM}MB — sufficient for all services"; add 5
    elif [[ ${RAM:-0} -ge 1024 ]]; then ok "RAM ${RAM}MB — sufficient"; add 3
    elif [[ ${RAM:-0} -ge 512  ]]; then warn "RAM ${RAM}MB — minimal; run one service only"
    else fail "RAM ${RAM:-?}MB — too low"; sub 10; fi
    local KMJ; KMJ=$(uname -r | cut -d. -f1)
    local KMN; KMN=$(uname -r | cut -d. -f2)
    ([[ $KMJ -ge 5 ]] || [[ $KMJ -eq 4 && $KMN -ge 9 ]]) && ok "Kernel $(uname -r) — BBR eligible" || warn "Old kernel"
    local IP6; IP6=$(ip -6 addr show 2>/dev/null | grep -v "::1\|fe80" | grep -c "inet6" 2>/dev/null || echo 0)
    [[ $IP6 -gt 0 ]] && ok "Dual-stack IPv4+IPv6" && add 3 || info "IPv4 only"
    section_end; return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# FINAL VERDICT
# ═══════════════════════════════════════════════════════════════════════════
final_verdict() {
    section "FINAL VERDICT"
    [[ $SCORE -gt 100 ]] && SCORE=100; [[ $SCORE -lt 0 ]] && SCORE=0
    echo ""
    local BAR="" F=$((SCORE/5))
    for ((i=0;i<20;i++)); do [[ $i -lt $F ]] && BAR+="█" || BAR+="░"; done
    local C G V ADV
    if   [[ $SCORE -ge 80 ]]; then C=$GREEN;  G="A"; V="EXCELLENT — Deploy immediately"
         ADV="High probability. Install 3X-UI + MasterDNS. Reality as backup."
    elif [[ $SCORE -ge 65 ]]; then C=$GREEN;  G="B"; V="GOOD — Deploy with Cloudflare CDN"
         ADV="Good server. WS+TLS+Cloudflare primary, Reality secondary."
    elif [[ $SCORE -ge 50 ]]; then C=$YELLOW; G="C"; V="ACCEPTABLE — DNS tunnel only"
         ADV="DNS tunnel (MasterDNS) is most reliable option here."
    elif [[ $SCORE -ge 35 ]]; then C=$YELLOW; G="D"; V="RISKY — Consider Hetzner Finland"
         ADV="Low success. Try hetzner.com instead."
    else                            C=$RED;    G="F"; V="AVOID — Change server immediately"
         ADV="Very high failure probability."; fi

    echo -e "  ${BOLD}Score: ${C}${SCORE}/100${NC}  |  Grade: ${C}${BOLD}${G}${NC}"
    echo -e "  ${C}[${BAR}] ${SCORE}%${NC}"
    echo ""
    echo -e "  ${C}${BOLD}🎯 ${V}${NC}"
    echo -e "  ${DIM}${ADV}${NC}"

    if [[ ${#ISSUES[@]} -gt 0 ]]; then
        echo ""; echo -e "  ${BOLD}${RED}Issues:${NC}"
        for i in "${!ISSUES[@]}"; do echo -e "  ${RED}  $((i+1)). ${ISSUES[$i]}${NC}"; done
    fi
    if [[ ${#ACTIONS[@]} -gt 0 ]]; then
        echo ""; echo -e "  ${BOLD}${CYAN}Action plan:${NC}"
        local N=1; declare -A SEEN
        for act in "${ACTIONS[@]}"; do
            if [[ -z "${SEEN[$act]:-}" ]]; then
                echo -e "  ${CYAN}  $N. $act${NC}"; N=$((N+1)); SEEN[$act]=1; fi
        done
    fi

    section "DEPLOYMENT GUIDE"
    echo ""
    local SID; SID=$(openssl rand -hex 4 2>/dev/null || echo "a1b2c3d4")
    echo -e "  ${BOLD}Step 1 — Prepare:${NC}"
    echo -e "  ${CYAN}  systemctl stop systemd-resolved && systemctl disable systemd-resolved${NC}"
    echo -e "  ${CYAN}  printf 'nameserver 8.8.8.8\\nnameserver 1.1.1.1\\n' > /etc/resolv.conf${NC}"
    echo -e "  ${CYAN}  ufw allow 443 && ufw allow 80 && ufw allow 53/udp && ufw reload${NC}"
    echo ""
    echo -e "  ${BOLD}Step 2 — Install 3X-UI:${NC}"
    echo -e "  ${CYAN}  bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)${NC}"
    echo ""
    echo -e "  ${BOLD}Step 3 — Enable BBR: x-ui → option 24${NC}"
    echo ""
    echo -e "  ${BOLD}Step 4 — VLESS Reality inbound:${NC}"
    echo -e "  ${CYAN}  Protocol: VLESS | Port: 443 | Security: Reality${NC}"
    echo -e "  ${CYAN}  Flow: xtls-rprx-vision | uTLS: chrome | SNI: ${BEST_SNI:-www.microsoft.com}${NC}"
    echo -e "  ${CYAN}  Short ID: $SID${NC}"
    echo ""
    echo -e "  ${BOLD}Step 5 — Install MasterDnsVPN:${NC}"
    echo -e "  ${CYAN}  bash <(curl -Ls https://raw.githubusercontent.com/masterking32/MasterDnsVPN/main/server_linux_install.sh)${NC}"
    echo ""
    echo -e "  ${BOLD}Step 6 — Verify from Iran:${NC}"
    echo -e "  ${CYAN}  bash iran-server-tester-v4.sh --probe-server=${PROBE_PORT}${NC}"
    echo -e "  ${CYAN}  Then run iran-probe-client.bat on Windows inside Iran${NC}"
    echo ""
    for c in "${INSTALL_CMDS[@]}"; do echo -e "  ${CYAN}  → $c${NC}"; done
    echo ""
    echo -e "${CYAN}  ═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  v${VERSION} complete — آزادی اینترنت حق همه مردم ایران است${NC}"
    echo -e "${CYAN}  ═══════════════════════════════════════════════════════════${NC}"
    echo ""
    [[ $HTML_MODE -eq 1 ]] && generate_html_report
    return 0
}

generate_html_report() {
    local GC="green"; [[ $SCORE -lt 65 ]] && GC="orange"; [[ $SCORE -lt 35 ]] && GC="red"
    cat > "$HTML_FILE" << HTMLEOF
<!DOCTYPE html><html><head><meta charset="UTF-8">
<title>Iran Server Report v${VERSION} — $MY_IP</title>
<style>body{font-family:monospace;background:#0d1117;color:#e6edf3;margin:0;padding:20px}
h1{color:#58a6ff;border-bottom:1px solid #30363d;padding-bottom:8px}
h2{color:#79c0ff;margin-top:20px;border-left:4px solid #1f6feb;padding-left:10px}
li{padding:2px 0;list-style:none}.ok{color:#3fb950}.fail{color:#f85149}
.warn{color:#d29922}.info{color:#58a6ff}
.score-box{background:#161b22;border:1px solid #30363d;border-radius:8px;padding:20px;margin:15px 0}
.score{font-size:48px;font-weight:bold;color:${GC}}
.bar-w{background:#21262d;height:18px;border-radius:9px;margin:8px 0}
.bar-f{height:18px;border-radius:9px;width:${SCORE}%;background:linear-gradient(90deg,#238636,#3fb950)}
.cmd{background:#161b22;border:1px solid #30363d;padding:8px;margin:4px 0;border-radius:4px}
.meta{color:#8b949e;font-size:11px}</style></head><body>
<h1>🇮🇷 Iran Server Readiness Report v${VERSION}</h1>
<p class="meta">$(date) | $MY_IP</p>
<div class="score-box"><div class="score">${SCORE}/100 — Grade ${G:-?}</div>
<div class="bar-w"><div class="bar-f"></div></div>
<strong style="color:${GC}">${V:-}</strong><br><span class="meta">${ADV:-}</span></div>
${HTML_BODY}
<h2>Quick Install</h2>
<div class="cmd">systemctl stop systemd-resolved && systemctl disable systemd-resolved</div>
<div class="cmd">bash &lt;(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)</div>
<div class="cmd">bash &lt;(curl -Ls https://raw.githubusercontent.com/masterking32/MasterDnsVPN/main/server_linux_install.sh)</div>
<p class="meta">Iran VPN Server Tester v${VERSION}</p></body></html>
HTMLEOF
    echo -e "  ${GREEN}[✔] HTML report: $HTML_FILE${NC}"
}

# ── MAIN ──────────────────────────────────────────────────────────────────
main() {
    [[ $PROBE_SERVER_MODE -eq 1 ]] && { run_probe_server; exit 0; }
    banner
    install_deps

    # Explicit check: if phase1 returns 1 (no internet), abort
    phase1_identity
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[!] Server has no internet access. Aborting.${NC}"
        exit 1
    fi

    phase2_install
    phase3_ports
    phase4_network
    phase5_sni
    phase6_dns_tunnel
    if [[ $QUICK_MODE -eq 0 ]]; then
        phase7_protocols
        phase8_system
    fi
    final_verdict
}

main
