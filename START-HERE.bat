@echo off
REM ===============================================================
REM   Ultimate Windows Repair Tool - Full Mode Launcher v4.0
REM ===============================================================

title Ultimate Windows Repair Tool v4.0 - Full Mode

cls
echo.
echo  ===============================================================
echo       Ultimate Windows Repair & Optimization Tool v4.0
echo  ===============================================================
echo.
echo  FULL MODE - Complete System Repair (45-60 minutes)
echo.
echo  What this comprehensive tool does:
echo.
echo  [1] RE-ENABLE DISABLED FEATURES
echo      * Windows Update (if disabled by policy/malware)
echo      * Microsoft Defender (if disabled)
echo.
echo  [2] OPTIMIZE & FIX
echo      * Startup programs analysis
echo      * Windows Store reset
echo      * Search index rebuild  
echo      * Print spooler reset
echo      * .NET Framework repair
echo      * Disk health check
echo      * Network adapter deep reset
echo.
echo  [3] DEEP CLEANUP (Frees 2-30+ GB!)
echo      * Windows.old removal
echo      * Temp files everywhere
echo      * Browser cache (passwords kept!)
echo      * Component store cleanup
echo      * Error reports and dumps
echo.
echo  [4] SYSTEM REPAIRS
echo      * DISM image repair
echo      * SFC system file scan
echo.
echo  [5] WINDOWS UPDATE RESET
echo      * Service reset
echo      * Cache clearing
echo      * 36 DLL re-registration
echo      * Network reset
echo.
echo  [6] PERFORMANCE METRICS
echo      * Before/after comparison
echo      * Shows improvements
echo.
echo  ===============================================================
echo.
echo  Press any key to start the complete repair, or close to cancel
echo.
pause >nul

REM Launch the full repair
start "Ultimate Windows Repair v4.0" powershell.exe -NoExit -ExecutionPolicy Bypass -Command "& '%~dp0Reset-WindowsUpdate-Clean.ps1'"

echo.
echo  Tool is running in a separate window.
echo  You can close this launcher.
echo.
timeout /t 2 >nul
exit
