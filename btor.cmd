@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem =========================================================
rem BTor (Windows) – Tor service manager & proxy helper
rem Features:
rem  - Service: install/start/stop/restart/enable/disable/status
rem  - Browser proxy helpers (Firefox user.js/prefs.js edits)
rem  - Route test via PowerShell 7 with SOCKS5
rem  - Self-install to PATH so typing `btor` just works
rem  - Self-update: `btor update` fetches latest from BTOR_RAW_URL
rem =========================================================

rem -----------------------------
rem Config
rem -----------------------------
set "SERVICE_NAME=TorWinSvc"
set "SOCKS_HOST=127.0.0.1"
set "SOCKS_PORT=9050"
set "ALT_SOCKS_PORT=9150"
set "INSTALL_DIR=%ProgramFiles%\BTor"
set "TARGET=%INSTALL_DIR%\BTor.cmd"
set "BTOR_HOME=%ProgramData%\BTor"
set "TOR_DIR=%ProgramFiles%\Tor"
set "TOR_EXE=%TOR_DIR%\tor.exe"
set "TORRC=%ProgramData%\Tor\torrc"
set "POWERSHELL7=pwsh.exe"

rem IMPORTANT: set to your trusted raw HTTPS URL hosting this exact script
set "BTOR_RAW_URL=https://raw.githubusercontent.com/your-org/BTor/main/BTor.cmd"

if not exist "%BTOR_HOME%" mkdir "%BTOR_HOME%" >nul 2>&1

rem -----------------------------
rem Header / UI helpers
rem -----------------------------
:header
cls
echo ============================================
echo BTor (Windows) – Tor Manager and Proxy Helper
echo Service: %SERVICE_NAME%
echo Install Dir: %INSTALL_DIR%
echo ============================================
goto :eof

:require_admin
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo [err] Admin rights required. Right-click and "Run as administrator".
  pause
  exit /b 1
)
goto :eof

rem -----------------------------
rem PATH install (btor command)
rem -----------------------------
:ensure_on_path
rem Copy current script to INSTALL_DIR and add to user PATH if needed
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%" >nul 2>&1
copy /y "%~f0" "%TARGET%" >nul

for /f "usebackq tokens=* delims=" %%P in (`powershell -NoLogo -NoProfile -Command "[Environment]::GetEnvironmentVariable('Path','User')"`) do set "USERPATH=%%P"
echo %USERPATH% | find /I "%INSTALL_DIR%" >nul
if errorlevel 1 (
  powershell -NoLogo -NoProfile -Command "[Environment]::SetEnvironmentVariable('Path', (([Environment]::GetEnvironmentVariable('Path','User') ?? '') + ';%INSTALL_DIR%'), 'User')"
  echo [ok] Added %INSTALL_DIR% to user PATH. Open a new terminal to use 'btor'.
) else (
  echo [ok] Install dir already in PATH.
)
goto :eof

rem -----------------------------
rem Service operations
rem -----------------------------
:install
call :require_admin || exit /b 1
call :ensure_on_path

echo [i] Creating Tor directories...
if not exist "%TOR_DIR%" mkdir "%TOR_DIR%" >nul 2>&1
if not exist "%ProgramData%\Tor" mkdir "%ProgramData%\Tor" >nul 2>&1

echo [i] Place tor.exe in "%TOR_DIR%" (official Tor bundle or tor win service binary), then continue.
pause

if not exist "%TOR_EXE%" (
  echo [err] %TOR_EXE% not found. Put tor.exe in %TOR_DIR% and re-run.
  exit /b 1
)

if not exist "%TORRC%" (
  echo SocksPort %SOCKS_PORT%>"%TORRC%"
  echo DataDirectory "C:\ProgramData\Tor">>"%TORRC%"
)

echo [i] Installing service with sc.exe...
sc query "%SERVICE_NAME%" >nul 2>&1
if %errorlevel% neq 0 (
  sc create "%SERVICE_NAME%" binPath= "\"%TOR_EXE%\" -f \"%TORRC%\" --nt-service" start= auto DisplayName= "Tor (BTor)" >nul
  if %errorlevel% neq 0 (
    echo [warn] sc.exe failed to create service. If preferred, install with NSSM:
    echo        nssm install %SERVICE_NAME% "%TOR_EXE%" -f "%TORRC%"
    echo        nssm set %SERVICE_NAME% Start SERVICE_AUTO_START
  )
) else (
  echo [ok] Service already exists.
)

echo [i] Starting service...
sc start "%SERVICE_NAME%" >nul
timeout /t 2 >nul
sc query "%SERVICE_NAME%" | find /I "RUNNING" >nul && echo [ok] Service running. || echo [warn] Service not yet running.

echo [ok] Install finished. Type: btor
goto :eof

:uninstall
call :require_admin || exit /b 1
sc stop "%SERVICE_NAME%" >nul 2>&1
sc delete "%SERVICE_NAME%" >nul 2>&1
echo [ok] Service removed.
goto :eof

:start
call :require_admin || exit /b 1
sc start "%SERVICE_NAME%" >nul 2>&1
sc query "%SERVICE_NAME%" | find /I "RUNNING" >nul && echo [ok] Running. || echo [err] Not running.
goto :eof

:stop
call :require_admin || exit /b 1
sc stop "%SERVICE_NAME%" >nul 2>&1
echo [ok] Stop requested.
goto :eof

:restart
call :require_admin || exit /b 1
sc stop "%SERVICE_NAME%" >nul 2>&1
timeout /t 2 >nul
sc start "%SERVICE_NAME%" >nul 2>&1
echo [ok] Restart requested.
goto :eof

:enable
call :require_admin || exit /b 1
sc config "%SERVICE_NAME%" start= auto >nul 2>&1
echo [ok] Enabled (auto-start).
goto :eof

:disable
call :require_admin || exit /b 1
sc config "%SERVICE_NAME%" start= demand >nul 2>&1
echo [ok] Disabled (manual).
goto :eof

:status
sc query "%SERVICE_NAME%" | findstr /I "STATE NAME"
sc qc "%SERVICE_NAME%" | findstr /I "BINARY_PATH_NAME START_TYPE"
goto :eof

rem -----------------------------
rem Firefox proxy helpers
rem -----------------------------
:proxy_menu
:proxy_menu_loop
call :header
echo Proxy helpers (Firefox):
echo  1) Set Firefox SOCKS proxy %SOCKS_HOST%:%SOCKS_PORT%
echo  2) Remove Firefox proxy
echo  3) Open check.torproject.org in Firefox
echo  4) Back
set /p CH=Select [1-4]: 
if "%CH%"=="1" call :ff_set_proxy & pause & goto :proxy_menu_loop
if "%CH%"=="2" call :ff_unset_proxy & pause & goto :proxy_menu_loop
if "%CH%"=="3" call :open_check_site & pause & goto :proxy_menu_loop
goto :eof

:ff_set_proxy
echo [i] Applying Firefox proxy prefs...
set "FFDIR=%APPDATA%\Mozilla\Firefox\Profiles"
if not exist "%FFDIR%" (
  echo [warn] No Firefox profile found. Start Firefox once, then retry.
  exit /b 0
)
for /f "tokens=*" %%D in ('dir /b /ad "%FFDIR%"') do (
  set "P=%FFDIR%\%%D"
  set "USERJS=!P!\user.js"
  set "PREFS=!P!\prefs.js"
  if exist "!P!" (
    echo // BTor >> "!USERJS!"
    echo user_pref("network.proxy.type", 1);>>"!USERJS!"
    echo user_pref("network.proxy.socks", "%SOCKS_HOST%");>>"!USERJS!"
    echo user_pref("network.proxy.socks_port", %SOCKS_PORT%);>>"!USERJS!"
    echo user_pref("network.proxy.no_proxies_on", "localhost");>>"!USERJS!"
    echo user_pref("network.proxy.socks_remote_dns", true);>>"!USERJS!"
    if not exist "!PREFS!" type nul > "!PREFS!"
    >"!PREFS!.tmp" (
      for /f "usebackq delims=" %%L in ("!PREFS!") do (
        echo %%L | findstr /I /R "network\.proxy\." >nul || echo %%L
      )
    )
    move /y "!PREFS!.tmp" "!PREFS!" >nul 2>&1
  )
)
echo [ok] Proxy set for existing profiles.
exit /b 0

:ff_unset_proxy
echo [i] Removing Firefox proxy prefs...
set "FFDIR=%APPDATA%\Mozilla\Firefox\Profiles"
if not exist "%FFDIR%" (
  echo [warn] No Firefox profile directory.
  exit /b 0
)
for /f "tokens=*" %%D in ('dir /b /ad "%FFDIR%"') do (
  set "P=%FFDIR%\%%D"
  set "USERJS=!P!\user.js"
  set "PREFS=!P!\prefs.js"
  if exist "!USERJS!" (
    >"!USERJS!.tmp" (
      for /f "usebackq delims=" %%L in ("!USERJS!") do (
        echo %%L | findstr /I /R "network\.proxy\." >nul || echo %%L
      )
    )
    move /y "!USERJS!.tmp" "!USERJS!" >nul 2>&1
  )
  if exist "!PREFS!" (
    >"!PREFS!.tmp" (
      for /f "usebackq delims=" %%L in ("!PREFS!") do (
        echo %%L | findstr /I /R "network\.proxy\." >nul || echo %%L
      )
    )
    move /y "!PREFS!.tmp" "!PREFS!" >nul 2>&1
  )
)
echo [ok] Proxy removed.
exit /b 0

:open_check_site
start "" "https://check.torproject.org/"
echo [ok] Opened Tor check site.
exit /b 0

rem -----------------------------
rem Route test using PowerShell 7
rem -----------------------------
:route_test
echo [i] Route test: attempting PowerShell 7 Invoke-WebRequest through SOCKS proxy...
where %POWERSHELL7% >nul 2>&1
if errorlevel 1 (
  echo [warn] PowerShell 7 not found. Install PowerShell 7 to test SOCKS in CLI, or just use Firefox.
  exit /b 0
)
%POWERSHELL7% -NoLogo -NoProfile -Command ^
  "try { $r = Invoke-WebRequest -Proxy ('socks5://%SOCKS_HOST%:%SOCKS_PORT%') 'https://check.torproject.org/' ; if ($r.Content -match 'Congratulations') { Write-Host '[ok] Tor routing OK via %SOCKS_PORT%'; exit 0 } else { Write-Host '[warn] Page fetched but not confirmed via Tor.'; exit 1 } } catch { Write-Host ('[err] ' + $_); exit 2 }"
exit /b 0

rem -----------------------------
rem Self-update
rem -----------------------------
:update
setlocal
if "%BTOR_RAW_URL%"=="" (
  echo [err] BTOR_RAW_URL is not set. Configure the source URL and re-run.
  endlocal & exit /b 1
)
set "TMP=%TEMP%\BTor_new_%RANDOM%.cmd"
echo [i] Downloading latest BTor script from:
echo     %BTOR_RAW_URL%

powershell -NoLogo -NoProfile -Command ^
  "try { Invoke-WebRequest -UseBasicParsing -Uri '%BTOR_RAW_URL%' -OutFile '%TMP%'; if ((Get-Item '%TMP%').Length -gt 2048) { exit 0 } else { exit 2 } } catch { exit 1 }"

if errorlevel 2 (
  echo [err] Downloaded file looks invalid (too small). Aborting update.
  del /q "%TMP%" >nul 2>&1
  endlocal & exit /b 1
) else if errorlevel 1 (
  echo [err] Failed to download update. Check network/URL.
  endlocal & exit /b 1
)

echo [i] Installing update...
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%" >nul 2>&1
copy /y "%TMP%" "%TARGET%" >nul
del /q "%TMP%" >nul 2>&1
echo [ok] BTor updated at %TARGET%.
echo [ok] Re-open terminal and run: btor
endlocal & exit /b 0

rem -----------------------------
rem Menu
rem -----------------------------
:menu
call :header
call :status
echo.
echo 1) Start service
echo 2) Stop service
echo 3) Restart service
echo 4) Enable at boot
echo 5) Disable at boot
echo 6) Proxy helpers
echo 7) Route test
echo 8) Ensure 'btor' on PATH
echo 9) Update (self-update)
echo 0) Exit
set /p CH=Select [0-9]: 
if "%CH%"=="1" goto :start
if "%CH%"=="2" goto :stop
if "%CH%"=="3" goto :restart
if "%CH%"=="4" goto :enable
if "%CH%"=="5" goto :disable
if "%CH%"=="6" goto :proxy_menu
if "%CH%"=="7" goto :route_test
if "%CH%"=="8" goto :ensure_on_path
if "%CH%"=="9" goto :update
exit /b 0

rem -----------------------------
rem CLI dispatcher
rem -----------------------------
if "%~1"=="" goto :menu

if /I "%~1"=="install"   goto :install
if /I "%~1"=="uninstall" goto :uninstall
if /I "%~1"=="update"    goto :update
if /I "%~1"=="start"     goto :start
if /I "%~1"=="stop"      goto :stop
if /I "%~1"=="restart"   goto :restart
if /I "%~1"=="enable"    goto :enable
if /I "%~1"=="disable"   goto :disable
if /I "%~1"=="status"    goto :status
if /I "%~1"=="proxy"     goto :proxy_menu
if /I "%~1"=="route"     goto :route_test
if /I "%~1"=="path"      goto :ensure_on_path

echo Unknown command. Use:
echo   btor install|uninstall|update|start|stop|restart|enable|disable|status|proxy|route|path
exit /b 1
