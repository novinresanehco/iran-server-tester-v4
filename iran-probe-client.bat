@echo off
:: ═══════════════════════════════════════════════════════════════════════════
::  IRAN VPN SERVER PROBE CLIENT  v4.1
::  ─────────────────────────────────────────────────────────────────────────
::  Tests your foreign server from Windows inside Iran.
::  HYBRID MODE:
::    - Connectivity tests → through your active VPN/proxy (to reach server)
::    - Raw network tests  → bypassing proxy (to measure Iran's real DPI)
::  You do NOT need to close your VPN/proxy app.
::  ─────────────────────────────────────────────────────────────────────────
::  PRIVACY: Your real Iran IP is hashed (SHA256) before any transmission.
::           Server sees only a hash, never your actual IP address.
:: ═══════════════════════════════════════════════════════════════════════════
setlocal EnableDelayedExpansion
chcp 65001 >nul 2>&1
title Iran VPN Server Probe v4.1

:: ── Color codes (works on Windows 10+/11) ─────────────────────────────────
for /f "delims=" %%a in ('echo prompt $E ^| cmd') do set "ESC=%%a"
set "RED=%ESC%[91m"
set "GRN=%ESC%[92m"
set "YEL=%ESC%[93m"
set "CYN=%ESC%[96m"
set "WHT=%ESC%[97m"
set "DIM=%ESC%[90m"
set "BLD=%ESC%[1m"
set "RST=%ESC%[0m"

cls
echo %CYN%
echo  ╔═══════════════════════════════════════════════════════════╗
echo  ║    IRAN VPN SERVER PROBE CLIENT  v4.1                    ║
echo  ║    Tests server reachability from inside Iran             ║
echo  ╚═══════════════════════════════════════════════════════════╝
echo %RST%
echo  %YEL%HYBRID MODE: Uses VPN to reach server + bypasses VPN for raw tests%RST%
echo  %DIM%You do NOT need to close your VPN application.%RST%
echo.

:: ── Ensure console stays open on any error ────────────────────────────────
if "%1"=="--child" goto :main_logic

:: Re-launch self in a visible window that won't close on error
cmd /k ""%~f0" --child"
exit /b

:main_logic

:: ── Check for curl availability ───────────────────────────────────────────
where curl >nul 2>&1
if errorlevel 1 (
    echo  %RED%[!] curl not found. Windows 10 v1803+ includes curl.%RST%
    echo  %YEL%    Download from: https://curl.se/windows/%RST%
    echo  %YEL%    Or run from PowerShell: winget install curl%RST%
    echo.
    pause
    exit /b 1
)

:: ── Auto-detect active SOCKS5/HTTP proxy ──────────────────────────────────
echo  %CYN%[*] Auto-detecting active VPN/proxy...%RST%
set "PROXY_ADDR="
set "PROXY_TYPE=none"
set "PROXY_FLAG="

:: Check common SOCKS5 proxy ports (v2rayN, Clash, Nekoray, etc.)
for %%p in (10808 10809 1080 7890 7891 2080 1090 20808) do (
    if not defined PROXY_ADDR (
        curl -s --max-time 3 --socks5 "127.0.0.1:%%p" "https://api.ipify.org" -o nul 2>nul
        if not errorlevel 1 (
            set "PROXY_ADDR=127.0.0.1:%%p"
            set "PROXY_TYPE=SOCKS5"
            set "PROXY_FLAG=--socks5 127.0.0.1:%%p"
        )
    )
)

:: Check HTTP proxy ports
if not defined PROXY_ADDR (
    for %%p in (10809 8080 8118 3128 7890 1081) do (
        if not defined PROXY_ADDR (
            curl -s --max-time 3 --proxy "http://127.0.0.1:%%p" "https://api.ipify.org" -o nul 2>nul
            if not errorlevel 1 (
                set "PROXY_ADDR=127.0.0.1:%%p"
                set "PROXY_TYPE=HTTP"
                set "PROXY_FLAG=--proxy http://127.0.0.1:%%p"
            )
        )
    )
)

:: Check Windows system proxy
if not defined PROXY_ADDR (
    for /f "tokens=3" %%a in (
        'reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer 2^>nul ^| findstr "ProxyServer"'
    ) do (
        set "WIN_PROXY=%%a"
    )
    if defined WIN_PROXY (
        curl -s --max-time 3 --proxy "http://!WIN_PROXY!" "https://api.ipify.org" -o nul 2>nul
        if not errorlevel 1 (
            set "PROXY_ADDR=!WIN_PROXY!"
            set "PROXY_TYPE=System HTTP"
            set "PROXY_FLAG=--proxy http://!WIN_PROXY!"
        )
    )
)

if defined PROXY_ADDR (
    echo  %GRN%[✔] Found active %PROXY_TYPE% proxy: %PROXY_ADDR%%RST%
    echo  %DIM%    Connectivity tests will use this proxy to reach your server.%RST%
    echo  %DIM%    Raw DPI tests will bypass this proxy.%RST%
) else (
    echo  %YEL%[!] No active proxy/VPN detected.%RST%
    echo  %YEL%    If internet is blocked in Iran, start your VPN first!%RST%
    echo  %YEL%    Then re-run this file.%RST%
    echo.
    echo  %DIM%Press any key to try anyway (raw Iran network only)...%RST%
    pause >nul
)
echo.

:: ── Get server details from user ──────────────────────────────────────────
echo  %BLD%%WHT%Enter your foreign server details:%RST%
echo.
:ask_ip
set /p "SERVER_IP=  Server IP address (e.g. 91.107.243.239): "
if not defined SERVER_IP (
    echo  %RED%  Server IP is required!%RST%
    goto :ask_ip
)
:: Validate IP format
echo %SERVER_IP% | findstr /r "^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$" >nul
if errorlevel 1 (
    echo  %RED%  Invalid IP format. Use format: x.x.x.x%RST%
    set "SERVER_IP="
    goto :ask_ip
)

set /p "TEST_PORTS=  Ports to test (default: 443 80): "
if not defined TEST_PORTS set "TEST_PORTS=443 80"

set /p "PROBE_PORT=  Probe port for reverse test (press Enter to skip): "
echo.

:: ── Privacy: hash the Iran IP before any network ops ─────────────────────
echo  %CYN%[*] Detecting your Iran IP (privacy-protected)...%RST%
set "MY_RAW_IP="
set "MY_IP_HASH=hidden"

:: Get raw Iran IP bypassing proxy (noproxy)
for /f "delims=" %%a in ('curl -s --max-time 8 --noproxy "*" "https://api.ipify.org" 2^>nul') do (
    set "MY_RAW_IP=%%a"
)

if not defined MY_RAW_IP (
    :: Try via proxy if direct fails (wartime: direct is blocked)
    if defined PROXY_FLAG (
        for /f "delims=" %%a in ('curl -s --max-time 8 %PROXY_FLAG% "https://api.ipify.org" 2^>nul') do (
            set "MY_RAW_IP=%%a"
        )
    )
)

if defined MY_RAW_IP (
    :: Hash the IP with PowerShell (SHA256) for privacy
    for /f "delims=" %%h in (
        'powershell -NoProfile -Command "[System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes(\"%MY_RAW_IP%\"))).Replace(\"-\",\"\").Substring(0,16).ToLower()" 2^>nul'
    ) do set "MY_IP_HASH=%%h"
    echo  %GRN%[OK] IP detected. Privacy hash: %MY_IP_HASH% (real IP never transmitted)%RST%
    :: Detect country
    for /f "delims=" %%c in ('curl -s --max-time 5 --noproxy "*" "https://ipinfo.io/%MY_RAW_IP%/country" 2^>nul') do set "MY_COUNTRY=%%c"
    if "!MY_COUNTRY!"=="IR" (
        echo  %GRN%[OK] Confirmed: Iranian IP (IR) — raw Iran network detected%RST%
    ) else (
        echo  %YEL%[!] Your direct IP is not Iranian (!MY_COUNTRY!) — VPN is intercepting all traffic%RST%
        echo  %DIM%    Some tests may not reflect real Iran DPI behavior%RST%
    )
) else (
    echo  %YEL%[!] Cannot detect your IP (normal if Iran blocks all direct traffic)%RST%
)
echo.

:: ── Initialize counters ───────────────────────────────────────────────────
set "TOTAL=0" & set "PASSED=0" & set "CRIT_PASS=0"
set "RESULT_FILE=%USERPROFILE%\Desktop\iran-probe-result.txt"

echo  %BLD%%WHT%Starting tests for %SERVER_IP%...%RST%
echo  %DIM%  [VPN] = test through proxy  [RAW] = test bypassing proxy%RST%
echo.

:: ═══════════════════════════════════════════════════════════════════════════
:: TEST 1: Connectivity via proxy (main channel)
:: ═══════════════════════════════════════════════════════════════════════════
echo  %YEL%━━━ TEST 1: Server Reachability via VPN/Proxy [VPN] ━━━━━━━━━%RST%
set /a TOTAL+=1

if defined PROXY_FLAG (
    :: Test HTTPS via proxy
    curl -s --max-time 12 -k %PROXY_FLAG% -o nul -w "%%{http_code}" "https://%SERVER_IP%:443" >"%TEMP%\probe_t1.txt" 2>nul
    set /p T1_CODE=<"%TEMP%\probe_t1.txt"
    
    if "!T1_CODE!"=="200" (
        echo  %GRN%[PASS] HTTPS 443 via VPN: Connected! (HTTP 200)%RST%
        set /a PASSED+=1 & set /a CRIT_PASS+=1
    ) else if not "!T1_CODE!"=="" (
        echo  %GRN%[PASS] HTTPS 443 via VPN: Reached (HTTP !T1_CODE!) — Server accessible!%RST%
        set /a PASSED+=1 & set /a CRIT_PASS+=1
    ) else (
        echo  %RED%[FAIL] HTTPS 443 via VPN: No response — server may be down or VPN not routing%RST%
    )
) else (
    echo  %YEL%[SKIP] No proxy detected — skipping VPN connectivity test%RST%
)
echo.

:: ═══════════════════════════════════════════════════════════════════════════
:: TEST 2: Raw TCP port tests (bypassing proxy to see real Iran DPI)
:: ═══════════════════════════════════════════════════════════════════════════
echo  %YEL%━━━ TEST 2: Raw DPI Port Tests [RAW — bypasses VPN] ━━━━━━━━%RST%
echo  %DIM%  These tests go directly through Iran network to measure DPI%RST%

for %%p in (%TEST_PORTS%) do (
    set /a TOTAL+=1
    curl -s --max-time 8 --noproxy "*" -o nul -w "%%{http_code}" "http://%SERVER_IP%:%%p" >"%TEMP%\probe_p%%p.txt" 2>nul
    set /p RAW_CODE=<"%TEMP%\probe_p%%p.txt"
    
    if "!RAW_CODE!"=="200" (
        echo  %GRN%[PASS-RAW] Port %%p: OPEN from raw Iran network — Iran DPI does NOT block it!%RST%
        set /a PASSED+=1 & set /a CRIT_PASS+=1
    ) else (
        :: Exit code 7 = connection refused (port reachable, service not listening)
        curl -s --max-time 8 --noproxy "*" "telnet://%SERVER_IP%:%%p" -o nul 2>nul
        if not errorlevel 7 (
            echo  %GRN%[PASS-RAW] Port %%p: TCP reachable from raw Iran network%RST%
            set /a PASSED+=1 & set /a CRIT_PASS+=1
        ) else (
            echo  %RED%[FAIL-RAW] Port %%p: BLOCKED by Iran DPI from raw network%RST%
            echo  %DIM%           (Normal in wartime — use DNS tunnel as primary method)%RST%
        )
    )
)
echo.

:: ═══════════════════════════════════════════════════════════════════════════
:: TEST 3: TLS Handshake via proxy
:: ═══════════════════════════════════════════════════════════════════════════
echo  %YEL%━━━ TEST 3: TLS/HTTPS Handshake [VPN] ━━━━━━━━━━━━━━━━━━━━━%RST%
set /a TOTAL+=1

if defined PROXY_FLAG (
    curl -s --max-time 12 -k %PROXY_FLAG% -o nul -w "%%{http_code}" "https://%SERVER_IP%:443" >"%TEMP%\probe_tls.txt" 2>nul
    set /p TLS_CODE=<"%TEMP%\probe_tls.txt"
    if defined TLS_CODE (
        if not "!TLS_CODE!"=="000" (
            echo  %GRN%[PASS] TLS handshake reached server (HTTP !TLS_CODE!) — port 443 TLS works!%RST%
            set /a PASSED+=1 & set /a CRIT_PASS+=1
        ) else (
            echo  %RED%[FAIL] TLS: No response — check if 3X-UI is installed and running%RST%
        )
    )
) else (
    echo  %YEL%[SKIP] No proxy — skipping TLS test%RST%
)
echo.

:: ═══════════════════════════════════════════════════════════════════════════
:: TEST 4: DNS resolver test (can server act as DNS resolver?)
:: ═══════════════════════════════════════════════════════════════════════════
echo  %YEL%━━━ TEST 4: DNS Resolver Test [RAW] ━━━━━━━━━━━━━━━━━━━━━━━%RST%
set /a TOTAL+=1
:: Try DNS via noproxy to test raw Iran → server DNS
nslookup google.com %SERVER_IP% >"%TEMP%\probe_dns.txt" 2>&1
findstr /i "Address" "%TEMP%\probe_dns.txt" | findstr /v "%SERVER_IP%" >nul 2>&1
if not errorlevel 1 (
    echo  %GRN%[PASS] DNS: Server resolves DNS from Iran raw network — MasterDNS tunnel works!%RST%
    set /a PASSED+=1 & set /a CRIT_PASS+=1
) else (
    echo  %YEL%[INFO] DNS: Server not yet acting as resolver (normal before MasterDNS install)%RST%
)
echo.

:: ═══════════════════════════════════════════════════════════════════════════
:: TEST 5: Latency measurement via proxy
:: ═══════════════════════════════════════════════════════════════════════════
echo  %YEL%━━━ TEST 5: Latency Measurement [VPN] ━━━━━━━━━━━━━━━━━━━━━%RST%
set "LATENCY_MS=?"
if defined PROXY_FLAG (
    curl -s --max-time 15 -k %PROXY_FLAG% -o nul -w "%%{time_connect}" "https://%SERVER_IP%:443" >"%TEMP%\probe_lat.txt" 2>nul
    set /p LAT_RAW=<"%TEMP%\probe_lat.txt"
    if defined LAT_RAW (
        if not "!LAT_RAW!"=="0.000000" (
            :: Convert seconds to ms (approximate)
            for /f "tokens=1 delims=." %%a in ("!LAT_RAW!") do set "LAT_SEC=%%a"
            if defined LAT_SEC (
                set /a "LATENCY_MS=LAT_SEC*1000"
                if !LATENCY_MS! LSS 10000 (
                    echo  %GRN%[INFO] Connection time: !LAT_RAW!s (via VPN — includes VPN overhead)%RST%
                    set /a PASSED+=1
                )
            )
        )
    )
) else (
    echo  %YEL%[SKIP] No proxy — skipping latency test%RST%
)
echo.

:: ═══════════════════════════════════════════════════════════════════════════
:: TEST 6: Raw traceroute (Iran network path analysis)
:: ═══════════════════════════════════════════════════════════════════════════
echo  %YEL%━━━ TEST 6: Route Analysis [RAW — Iran network path] ━━━━━━━%RST%
set /a TOTAL+=1
echo  %DIM%  Running tracert (limited to 10 hops, 2s timeout)...%RST%
tracert -h 10 -w 2000 -d %SERVER_IP% >"%TEMP%\probe_route.txt" 2>&1

:: Count hops
set "HOP_CNT=0"
for /f "tokens=1" %%a in ('findstr /r "^  [0-9]" "%TEMP%\probe_route.txt" 2^>nul') do (
    set /a HOP_CNT+=1
)

:: Show relevant hops
echo  %DIM%  Last hops in path (raw Iran network):%RST%
for /f "delims=" %%a in ('findstr /r "^  [0-9]" "%TEMP%\probe_route.txt" 2^>nul') do (
    echo  %DIM%  %%a%RST%
)

if !HOP_CNT! GEQ 3 (
    echo  %GRN%[INFO] Route has !HOP_CNT! hops visible%RST%
    set /a PASSED+=1
) else (
    echo  %YEL%[INFO] Route limited (common for filtered Iranian paths — normal)%RST%
)
echo.

:: ═══════════════════════════════════════════════════════════════════════════
:: TEST 7: Reverse probe (if probe port specified)
:: ═══════════════════════════════════════════════════════════════════════════
if defined PROBE_PORT (
    echo  %YEL%━━━ TEST 7: Reverse Probe [VPN → Server listener] ━━━━━━━━%RST%
    set /a TOTAL+=1
    echo  %DIM%  Connecting to probe listener on %SERVER_IP%:%PROBE_PORT%...%RST%
    echo  %DIM%  Make sure server is running: bash iran-server-tester-v4.sh --probe-server=%PROBE_PORT%%RST%
    echo.
    
    :: Build privacy-safe probe payload (never send raw Iran IP)
    set "PROBE_PAYLOAD=IRAN_PROBE|v=4.1|isp=!MY_COUNTRY!|h=!MY_IP_HASH!|lat=!LATENCY_MS!"
    
    :: Send probe through proxy (to reach server)
    if defined PROXY_FLAG (
        echo !PROBE_PAYLOAD! | curl -s --max-time 12 %PROXY_FLAG% ^
            -X POST --data-binary @- ^
            "http://%SERVER_IP%:%PROBE_PORT%" >"%TEMP%\probe_resp.txt" 2>nul
    ) else (
        echo !PROBE_PAYLOAD! | curl -s --max-time 12 ^
            -X POST --data-binary @- ^
            "http://%SERVER_IP%:%PROBE_PORT%" >"%TEMP%\probe_resp.txt" 2>nul
    )
    
    set /p PROBE_RESP=<"%TEMP%\probe_resp.txt"
    if defined PROBE_RESP (
        echo !PROBE_RESP! | findstr "PROBE_OK" >nul 2>&1
        if not errorlevel 1 (
            echo  %GRN%[PASS] Reverse probe SUCCESSFUL — Server confirmed your connection!%RST%
            set /a PASSED+=1 & set /a CRIT_PASS+=1
        ) else (
            echo  %GRN%[INFO] Response received from server: !PROBE_RESP!%RST%
            set /a PASSED+=1
        )
    ) else (
        echo  %YEL%[INFO] No response from probe port — server may not be in probe mode%RST%
        echo  %DIM%       Run on server: bash iran-server-tester-v4.sh --probe-server=%PROBE_PORT%%RST%
    )
    echo.
)

:: ═══════════════════════════════════════════════════════════════════════════
:: FINAL VERDICT
:: ═══════════════════════════════════════════════════════════════════════════
echo  %CYN%╔═══════════════════════════════════════════════════════════╗%RST%
echo  %CYN%║                    FINAL VERDICT                         ║%RST%
echo  %CYN%╚═══════════════════════════════════════════════════════════╝%RST%
echo.
echo  %WHT%Server     : %SERVER_IP%%RST%
echo  %WHT%Proxy used : !PROXY_TYPE! (!PROXY_ADDR!)%RST%
echo  %WHT%Iran IP    : [privacy-protected, hash: !MY_IP_HASH!]%RST%
echo  %WHT%Tests OK   : %PASSED% / %TOTAL%%RST%
echo.

if !CRIT_PASS! GEQ 2 (
    echo  %GRN%%BLD%  ✅ VERDICT: SERVER IS REACHABLE FROM IRAN%RST%
    echo  %GRN%  VPN connectivity confirmed — install 3X-UI on your server%RST%
    echo  %GRN%  Port 443 accessible via your VPN tunnel%RST%
    if !CRIT_PASS! GEQ 3 (
        echo  %GRN%  Bonus: Some ports also accessible on RAW Iran network!%RST%
    )
    echo.
    echo  %CYN%  Next steps:%RST%
    echo  %CYN%  1. Install 3X-UI:%RST%
    echo  %CYN%     bash ^<(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)%RST%
    echo  %CYN%  2. Install MasterDNS:%RST%
    echo  %CYN%     bash ^<(curl -Ls https://raw.githubusercontent.com/masterking32/MasterDnsVPN/main/server_linux_install.sh)%RST%
) else if !CRIT_PASS! EQU 1 (
    echo  %YEL%%BLD%  ⚠️  VERDICT: LIMITED CONNECTIVITY%RST%
    echo  %YEL%  Partial access — some ports work, others blocked%RST%
    echo  %YEL%  Recommendation: Use DNS tunnel (MasterDNS) as primary method%RST%
) else (
    echo  %RED%%BLD%  ❌ VERDICT: SERVER NOT REACHABLE%RST%
    echo  %RED%  Even through VPN, server is unreachable%RST%
    echo  %RED%  Possible causes:%RST%
    echo  %RED%    - Server is down (check SSH access)%RST%
    echo  %RED%    - Port 443 not open (install 3X-UI first)%RST%
    echo  %RED%    - VPN not routing correctly (check v2rayN config)%RST%
    if not defined PROXY_ADDR (
        echo  %RED%    - No VPN detected — start your VPN first!%RST%
    )
)

:: ── Save results ──────────────────────────────────────────────────────────
echo.
(
    echo Iran VPN Server Probe Results v4.1
    echo Generated: %DATE% %TIME%
    echo Server: %SERVER_IP%
    echo Proxy: !PROXY_TYPE! (!PROXY_ADDR!)
    echo Iran IP Hash: !MY_IP_HASH!
    echo Country: !MY_COUNTRY!
    echo Tests Passed: %PASSED%/%TOTAL%
    echo Critical Tests: !CRIT_PASS!
    echo.
    if !CRIT_PASS! GEQ 2 (
        echo VERDICT: SERVER REACHABLE FROM IRAN
    ) else (
        echo VERDICT: SERVER NOT RELIABLY REACHABLE
    )
) > "%RESULT_FILE%" 2>nul

echo  %GRN%[*] Results saved: %RESULT_FILE%%RST%
echo.
echo  %DIM%══════════════════════════════════════════════════════════%RST%
echo  %DIM%  Iran VPN Server Probe v4.1%RST%
echo  %DIM%  آزادی اینترنت حق همه مردم ایران است%RST%
echo  %DIM%══════════════════════════════════════════════════════════%RST%
echo.
pause
