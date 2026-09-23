@echo off
REM ===============================================================
REM   Ultimate Windows Repair Tool - Quick Mode Launcher v4.0
REM ===============================================================

title Ultimate Windows Repair Tool v4.0 - Quick Mode

cls
echo.
echo  ===============================================================
echo       Ultimate Windows Repair Tool - QUICK MODE
echo  ===============================================================
echo.
echo  QUICK MODE - Essential Fixes Only (~8-12 minutes)
echo.
echo  What Quick Mode does:
echo.
echo    [YES] Re-enables Windows Update if disabled
echo    [YES] Re-enables Microsoft Defender if disabled
echo    [YES] Windows Store reset
echo    [YES] Print Spooler reset
echo    [YES] Stops/restarts Windows Update services
echo    [YES] Clears update caches
echo    [YES] Re-registers 36 DLLs
echo    [YES] Network reset
echo    [YES] Checks for updates
echo.
echo  What Quick Mode skips:
echo.
echo    [NO]  Startup optimization
echo    [NO]  Search rebuild
echo    [NO]  .NET repair
echo    [NO]  Disk health check
echo    [NO]  Deep network reset
echo    [NO]  System Restore Point
echo    [NO]  Deep cleanup (Windows.old, temp files)
echo    [NO]  DISM/SFC repairs
echo    [NO]  Performance metrics
echo.
echo  Use Quick Mode when:
echo    - You're in a hurry
echo    - You just need updates working
echo    - You don't need cleanup or deep repairs
echo.
echo  For complete repair, use START-HERE.bat instead
echo.
echo  ===============================================================
echo.
echo  Press any key to start Quick Mode, or close to cancel
echo.
pause >nul

REM Launch Quick Mode
start "Ultimate Windows Repair - Quick" powershell.exe -NoExit -ExecutionPolicy Bypass -Command "& '%~dp0Reset-WindowsUpdate-Clean.ps1' -Quick"

echo.
echo  Quick Mode is running in a separate window.
echo.
timeout /t 2 >nul
exit
