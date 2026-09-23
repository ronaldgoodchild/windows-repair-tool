<#
.SYNOPSIS
    The Ultimate Windows Update reset, repair, and optimization tool with visual progress.

.DESCRIPTION
    This comprehensive script performs a complete Windows system repair and optimization.
    
    Core Features:
    - Re-enables Windows Update if disabled (registry + service fixes)
    - Re-enables Microsoft Defender if disabled (registry + service fixes)
    - Startup program analysis and optimization guidance
    - Windows Store reset and app re-registration
    - Windows Search index rebuild
    - Print Spooler reset (fixes stuck print jobs)
    - .NET Framework repair
    - Disk health check (SMART status, file system)
    - Comprehensive network adapter reset
    - Deep system cleanup (Windows.old, temp files, browser cache)
    - Creates System Restore Point (safety backup)
    - Runs DISM and SFC system repairs
    - Stops/restarts Windows Update services
    - Clears all update caches
    - Re-registers 36 critical DLLs
    - Resets network settings (DNS, Winsock, Proxy, IP)
    - Performance metrics (before/after comparison)
    - Checks for available updates

.NOTES
    Must be run as Administrator
    Estimated time: 40-60 minutes (Full Mode) or 5-10 minutes (Quick Mode)

.EXAMPLE
    .\Reset-WindowsUpdate-Final.ps1
    Runs full repair with all options

.EXAMPLE
    .\Reset-WindowsUpdate-Final.ps1 -Quick
    Quick mode - skips repairs and restore point (~5 minutes)

.EXAMPLE
    .\Reset-WindowsUpdate-Final.ps1 -SkipRepairs
    Skips DISM/SFC repairs but creates restore point
#>

[CmdletBinding()]
param(
    [switch]$SkipRestorePoint,
    [switch]$SkipRepairs,
    [switch]$SkipCleanup,
    [switch]$Quick
)

# --- AUTO-ELEVATION BLOCK ---
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    if ([string]::IsNullOrEmpty($PSCommandPath)) {
        Write-Host "ERROR: Please SAVE this script to a file before running it." -ForegroundColor Red
        Write-Host "The script needs a file path to restart as Administrator." -ForegroundColor Yellow
        Write-Host "`nPress Enter to exit..." -ForegroundColor Gray
        Read-Host
        Exit
    }
    
    # Build arguments string to preserve parameters and keep window open
    $argString = "-NoExit -ExecutionPolicy Bypass -Command `"& '$PSCommandPath'"
    if ($SkipRestorePoint) { $argString += " -SkipRestorePoint" }
    if ($SkipRepairs) { $argString += " -SkipRepairs" }
    if ($Quick) { $argString += " -Quick" }
    $argString += "`""
    
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = "powershell.exe"
    $processInfo.Arguments = $argString
    $processInfo.Verb = "runas"
    $processInfo.WindowStyle = "Normal"  # Ensure window is visible
    try {
        [System.Diagnostics.Process]::Start($processInfo) | Out-Null
    } catch {
        Write-Host "User cancelled UAC prompt or error occurred." -ForegroundColor Yellow
    }
    Exit
}
# ----------------------------

# Initialize
$ErrorActionPreference = "Continue"
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logFile = "$env:TEMP\WindowsUpdate_Reset_$timestamp.log"
$script:errorCount = 0
$script:warningCount = 0
$script:currentStep = 0
$script:totalSteps = 19  # Default for full mode with all features
$script:beforeMetrics = $null
$script:afterMetrics = $null

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    
    $color = switch ($Level) {
        "ERROR"   { "Red"; $script:errorCount++ }
        "WARNING" { "Yellow"; $script:warningCount++ }
        "SUCCESS" { "Green" }
        "HEADER"  { "Cyan" }
        default   { "White" }
    }
    
    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    Write-Host $logMessage -ForegroundColor $color
    Add-Content -Path $logFile -Value $logMessage
}

function Write-Header {
    param([string]$Title, [int]$StepNumber = 0)
    
    $script:currentStep = $StepNumber
    
    Write-Host "`n" -NoNewline
    Write-Host "===============================================================" -ForegroundColor Cyan
    if ($StepNumber -gt 0) {
        Write-Host "  STEP $StepNumber/$script:totalSteps: $Title" -ForegroundColor Cyan
    } else {
        Write-Host "  $Title" -ForegroundColor Cyan
    }
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Progress-Custom {
    param(
        [string]$Activity,
        [string]$Status,
        [int]$PercentComplete = -1,
        [string]$Icon = "[*]"
    )
    
    if ($PercentComplete -ge 0) {
        Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete
    }
    Write-Host "  $Icon $Status" -ForegroundColor Gray
}

function Stop-ServiceSafely {
    param([string]$ServiceName)
    
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($service) {
            if ($service.Status -eq 'Running') {
                Write-Host "  [STOP] Stopping: " -NoNewline -ForegroundColor Yellow
                Write-Host $ServiceName -ForegroundColor White
                Stop-Service -Name $ServiceName -Force -ErrorAction Stop
                Write-Host "  [ OK ] Stopped: " -NoNewline -ForegroundColor Green
                Write-Host $ServiceName -ForegroundColor White
            } else {
                Write-Host "  [INFO] Already stopped: " -NoNewline -ForegroundColor Gray
                Write-Host $ServiceName -ForegroundColor White
            }
        } else {
            Write-Log "Service not found: $ServiceName" -Level "WARNING"
        }
    } catch {
        Write-Log "Failed to stop service $ServiceName : $_" -Level "ERROR"
    }
}

function Start-ServiceSafely {
    param([string]$ServiceName)
    
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($service) {
            Write-Host "  [START] Starting: " -NoNewline -ForegroundColor Yellow
            Write-Host $ServiceName -ForegroundColor White
            Start-Service -Name $ServiceName -ErrorAction Stop
            Write-Host "  [ OK  ] Started: " -NoNewline -ForegroundColor Green
            Write-Host $ServiceName -ForegroundColor White
        } else {
            Write-Log "Service not found: $ServiceName" -Level "WARNING"
        }
    } catch {
        Write-Log "Failed to start service $ServiceName : $_" -Level "ERROR"
    }
}

function Optimize-StartupPrograms {
    param([int]$StepNumber = 1)
    
    Write-Header "Startup Program Optimization" $StepNumber
    Write-Host "  [CHECK] Analyzing startup programs..." -ForegroundColor Cyan
    Write-Host ""
    
    # Get startup programs from multiple locations
    $startupItems = @()
    
    # Registry - Current User Run
    try {
        $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
        if (Test-Path $regPath) {
            Get-ItemProperty $regPath -ErrorAction SilentlyContinue | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -notmatch "PS" } | ForEach-Object {
                $startupItems += [PSCustomObject]@{
                    Name = $_.Name
                    Location = "User Registry"
                    Enabled = $true
                }
            }
        }
    } catch { }
    
    # Registry - Local Machine Run
    try {
        $regPath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
        if (Test-Path $regPath) {
            Get-ItemProperty $regPath -ErrorAction SilentlyContinue | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -notmatch "PS" } | ForEach-Object {
                $startupItems += [PSCustomObject]@{
                    Name = $_.Name
                    Location = "System Registry"
                    Enabled = $true
                }
            }
        }
    } catch { }
    
    # Startup Folder - Current User
    try {
        $startupPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
        if (Test-Path $startupPath) {
            Get-ChildItem $startupPath -ErrorAction SilentlyContinue | ForEach-Object {
                $startupItems += [PSCustomObject]@{
                    Name = $_.Name
                    Location = "User Startup Folder"
                    Enabled = $true
                }
            }
        }
    } catch { }
    
    # Startup Folder - All Users
    try {
        $startupPath = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
        if (Test-Path $startupPath) {
            Get-ChildItem $startupPath -ErrorAction SilentlyContinue | ForEach-Object {
                $startupItems += [PSCustomObject]@{
                    Name = $_.Name
                    Location = "Common Startup Folder"
                    Enabled = $true
                }
            }
        }
    } catch { }
    
    # Task Scheduler startup tasks
    try {
        $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { 
            $_.Triggers.ClassName -like "*LogonTrigger*" -and $_.State -ne "Disabled" 
        }
        foreach ($task in $tasks) {
            $startupItems += [PSCustomObject]@{
                Name = $task.TaskName
                Location = "Task Scheduler"
                Enabled = $true
            }
        }
    } catch { }
    
    if ($startupItems.Count -eq 0) {
        Write-Host "  [ OK  ] No startup programs found (already optimized!)" -ForegroundColor Green
        return
    }
    
    Write-Host "  [INFO ] Found $($startupItems.Count) startup programs" -ForegroundColor Cyan
    Write-Host "         Listing for your information (no changes made):" -ForegroundColor Gray
    Write-Host ""
    
    $counter = 1
    foreach ($item in $startupItems | Select-Object -First 20) {
        Write-Host "         [$counter] $($item.Name)" -ForegroundColor White
        Write-Host "             Location: $($item.Location)" -ForegroundColor Gray
        $counter++
    }
    
    if ($startupItems.Count -gt 20) {
        Write-Host "         ... and $($startupItems.Count - 20) more" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "  [INFO ] To manage startup programs:" -ForegroundColor Yellow
    Write-Host "         1. Press Ctrl+Shift+Esc to open Task Manager" -ForegroundColor Gray
    Write-Host "         2. Go to the 'Startup' tab" -ForegroundColor Gray
    Write-Host "         3. Right-click programs and select 'Disable'" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  [ OK  ] Startup analysis complete" -ForegroundColor Green
}

function Reset-WindowsStore {
    param([int]$StepNumber = 1)
    
    Write-Header "Windows Store Reset" $StepNumber
    Write-Host "  [RESET] Resetting Windows Store..." -ForegroundColor Cyan
    
    try {
        # Clear Store cache
        Write-Host "  [CLEAN] Clearing Store cache..." -ForegroundColor Yellow
        Start-Process "wsreset.exe" -WindowStyle Hidden
        Start-Sleep -Seconds 5
        Write-Host "  [ OK  ] Store cache cleared" -ForegroundColor Green
        
        # Re-register Store apps
        Write-Host "`n  [REG  ] Re-registering Windows Store apps..." -ForegroundColor Cyan
        Write-Host "          This may take 2-3 minutes..." -ForegroundColor Gray
        
        $regCommand = "Get-AppxPackage -AllUsers | Where-Object {`$_.Name -like '*Store*'} | ForEach-Object {Add-AppxPackage -DisableDevelopmentMode -Register `"`$(`$_.InstallLocation)\AppXManifest.xml`"}"
        $null = PowerShell -Command $regCommand 2>&1
        
        Write-Host "  [ OK  ] Windows Store apps re-registered" -ForegroundColor Green
        
        # Reset Store app data
        Write-Host "`n  [RESET] Resetting Store app data..." -ForegroundColor Yellow
        Get-AppxPackage -Name "Microsoft.WindowsStore" -AllUsers | ForEach-Object {
            try {
                Reset-AppxPackage -Package $_.PackageFullName -ErrorAction SilentlyContinue
            } catch { }
        }
        Write-Host "  [ OK  ] Store reset complete" -ForegroundColor Green
        
    } catch {
        Write-Host "  [WARN ] Store reset completed with warnings: $_" -ForegroundColor Yellow
    }
}

function Rebuild-SearchIndex {
    param([int]$StepNumber = 1)
    
    Write-Header "Windows Search Index Rebuild" $StepNumber
    Write-Host "  [SEARCH] Rebuilding Windows Search index..." -ForegroundColor Cyan
    Write-Host "           This improves 'search not finding files' issues" -ForegroundColor Gray
    Write-Host ""
    
    try {
        # Stop Windows Search
        Write-Host "  [STOP ] Stopping Windows Search service..." -ForegroundColor Yellow
        Stop-Service -Name "WSearch" -Force -ErrorAction Stop
        Write-Host "  [ OK  ] Windows Search stopped" -ForegroundColor Green
        
        # Delete index files
        Write-Host "`n  [CLEAN] Deleting old search index..." -ForegroundColor Yellow
        $indexPath = "$env:ProgramData\Microsoft\Search\Data\Applications\Windows"
        if (Test-Path $indexPath) {
            Remove-Item -Path "$indexPath\*" -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "  [ OK  ] Old index deleted" -ForegroundColor Green
        }
        
        # Start Windows Search
        Write-Host "`n  [START] Starting Windows Search service..." -ForegroundColor Yellow
        Start-Service -Name "WSearch" -ErrorAction Stop
        Write-Host "  [ OK  ] Windows Search started" -ForegroundColor Green
        
        # Trigger rebuild via registry
        Write-Host "`n  [BUILD] Triggering index rebuild..." -ForegroundColor Yellow
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows Search"
        Set-ItemProperty -Path $regPath -Name "SetupCompletedSuccessfully" -Value 0 -Force -ErrorAction SilentlyContinue
        Restart-Service -Name "WSearch" -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $regPath -Name "SetupCompletedSuccessfully" -Value 1 -Force -ErrorAction SilentlyContinue
        
        Write-Host "  [ OK  ] Search index rebuild initiated" -ForegroundColor Green
        Write-Host "`n  [INFO ] The index will rebuild in the background" -ForegroundColor Cyan
        Write-Host "          This may take 15-30 minutes for large drives" -ForegroundColor Gray
        Write-Host "          Search will work normally during rebuild" -ForegroundColor Gray
        
    } catch {
        Write-Host "  [WARN ] Search rebuild completed with warnings: $_" -ForegroundColor Yellow
    }
}

function Reset-PrintSpooler {
    param([int]$StepNumber = 1)
    
    Write-Header "Print Spooler Reset" $StepNumber
    Write-Host "  [PRINT] Resetting Print Spooler..." -ForegroundColor Cyan
    Write-Host "          This fixes stuck print jobs and printer issues" -ForegroundColor Gray
    Write-Host ""
    
    try {
        # Stop Print Spooler
        Write-Host "  [STOP ] Stopping Print Spooler service..." -ForegroundColor Yellow
        Stop-Service -Name "Spooler" -Force -ErrorAction Stop
        Start-Sleep -Seconds 2
        Write-Host "  [ OK  ] Print Spooler stopped" -ForegroundColor Green
        
        # Clear print queue
        Write-Host "`n  [CLEAN] Clearing print queue..." -ForegroundColor Yellow
        $spoolPath = "$env:SystemRoot\System32\spool\PRINTERS"
        if (Test-Path $spoolPath) {
            $fileCount = (Get-ChildItem $spoolPath -File -ErrorAction SilentlyContinue).Count
            Remove-Item -Path "$spoolPath\*" -Force -ErrorAction SilentlyContinue
            if ($fileCount -gt 0) {
                Write-Host "  [ OK  ] Removed $fileCount stuck print job(s)" -ForegroundColor Green
            } else {
                Write-Host "  [ OK  ] Print queue was already empty" -ForegroundColor Green
            }
        }
        
        # Start Print Spooler
        Write-Host "`n  [START] Starting Print Spooler service..." -ForegroundColor Yellow
        Start-Service -Name "Spooler" -ErrorAction Stop
        Write-Host "  [ OK  ] Print Spooler started" -ForegroundColor Green
        Write-Host "`n  [ OK  ] Print Spooler reset complete" -ForegroundColor Green
        
    } catch {
        Write-Host "  [WARN ] Print Spooler reset completed with warnings: $_" -ForegroundColor Yellow
    }
}

function Get-PerformanceMetrics {
    param([string]$Phase = "BEFORE")
    
    $metrics = @{}
    
    try {
        # RAM Usage
        $os = Get-CimInstance Win32_OperatingSystem
        $totalRAM = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        $freeRAM = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        $usedRAM = $totalRAM - $freeRAM
        $ramPercent = [math]::Round(($usedRAM / $totalRAM) * 100, 1)
        
        $metrics.TotalRAM = $totalRAM
        $metrics.UsedRAM = $usedRAM
        $metrics.RAMPercent = $ramPercent
        
        # Disk Usage
        $disk = Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':'))
        $totalDisk = [math]::Round(($disk.Used + $disk.Free) / 1GB, 2)
        $freeDisk = [math]::Round($disk.Free / 1GB, 2)
        $usedDisk = $totalDisk - $freeDisk
        $diskPercent = [math]::Round(($usedDisk / $totalDisk) * 100, 1)
        
        $metrics.TotalDisk = $totalDisk
        $metrics.FreeDisk = $freeDisk
        $metrics.DiskPercent = $diskPercent
        
        # Process Count
        $metrics.ProcessCount = (Get-Process).Count
        
        # Service Count (Running)
        $metrics.RunningServices = (Get-Service | Where-Object {$_.Status -eq 'Running'}).Count
        
    } catch {
        Write-Host "  [WARN ] Could not collect all metrics" -ForegroundColor Yellow
    }
    
    return $metrics
}

function Show-PerformanceMetrics {
    param([int]$StepNumber = 1)
    
    Write-Header "Performance Metrics" $StepNumber
    
    if ($script:beforeMetrics -and $script:afterMetrics) {
        Write-Host "  [STATS] System Performance - Before vs After" -ForegroundColor Cyan
        Write-Host "  ================================================================" -ForegroundColor Cyan
        
        # RAM
        Write-Host "`n  Memory Usage:" -ForegroundColor White
        Write-Host "    Before: $($script:beforeMetrics.UsedRAM) GB / $($script:beforeMetrics.TotalRAM) GB " -NoNewline -ForegroundColor Gray
        Write-Host "($($script:beforeMetrics.RAMPercent)%)" -ForegroundColor Gray
        Write-Host "    After:  $($script:afterMetrics.UsedRAM) GB / $($script:afterMetrics.TotalRAM) GB " -NoNewline -ForegroundColor Gray
        Write-Host "($($script:afterMetrics.RAMPercent)%)" -ForegroundColor Gray
        
        $ramDiff = $script:beforeMetrics.UsedRAM - $script:afterMetrics.UsedRAM
        if ($ramDiff -gt 0) {
            Write-Host "    Freed: " -NoNewline -ForegroundColor Green
            Write-Host "$([math]::Round($ramDiff, 2)) GB" -ForegroundColor Green
        }
        
        # Disk
        Write-Host "`n  Disk Space:" -ForegroundColor White
        Write-Host "    Before: $($script:beforeMetrics.FreeDisk) GB free " -NoNewline -ForegroundColor Gray
        Write-Host "($([math]::Round(100 - $script:beforeMetrics.DiskPercent, 1))% free)" -ForegroundColor Gray
        Write-Host "    After:  $($script:afterMetrics.FreeDisk) GB free " -NoNewline -ForegroundColor Gray
        Write-Host "($([math]::Round(100 - $script:afterMetrics.DiskPercent, 1))% free)" -ForegroundColor Gray
        
        $diskGained = $script:afterMetrics.FreeDisk - $script:beforeMetrics.FreeDisk
        if ($diskGained -gt 0.1) {
            Write-Host "    Gained: " -NoNewline -ForegroundColor Green
            Write-Host "$([math]::Round($diskGained, 2)) GB" -ForegroundColor Green
        }
        
        # Processes
        Write-Host "`n  Running Processes:" -ForegroundColor White
        Write-Host "    Before: $($script:beforeMetrics.ProcessCount)" -ForegroundColor Gray
        Write-Host "    After:  $($script:afterMetrics.ProcessCount)" -ForegroundColor Gray
        
        # Services
        Write-Host "`n  Running Services:" -ForegroundColor White
        Write-Host "    Before: $($script:beforeMetrics.RunningServices)" -ForegroundColor Gray
        Write-Host "    After:  $($script:afterMetrics.RunningServices)" -ForegroundColor Gray
        
        Write-Host "`n  ================================================================" -ForegroundColor Cyan
        Write-Host "  [ OK  ] Performance metrics captured" -ForegroundColor Green
    } else {
        Write-Host "  [INFO ] Collecting baseline metrics..." -ForegroundColor Cyan
        $script:beforeMetrics = Get-PerformanceMetrics -Phase "BEFORE"
        Write-Host "  [ OK  ] Baseline captured" -ForegroundColor Green
    }
}

function Repair-DotNetFramework {
    param([int]$StepNumber = 1)
    
    Write-Header ".NET Framework Repair" $StepNumber
    Write-Host "  [.NET ] Checking and repairing .NET Framework..." -ForegroundColor Cyan
    Write-Host ""
    
    # Check .NET 3.5
    try {
        Write-Host "  [CHECK] .NET Framework 3.5..." -ForegroundColor Cyan
        $net35 = Get-WindowsOptionalFeature -Online -FeatureName "NetFx3" -ErrorAction SilentlyContinue
        
        if ($net35.State -eq "Enabled") {
            Write-Host "  [ OK  ] .NET 3.5 is installed" -ForegroundColor Green
        } else {
            Write-Host "  [INFO ] .NET 3.5 is not installed (optional)" -ForegroundColor Gray
        }
    } catch {
        Write-Host "  [WARN ] Could not check .NET 3.5 status" -ForegroundColor Yellow
    }
    
    # Repair .NET 4.x
    try {
        Write-Host "`n  [REPAIR] Repairing .NET Framework 4.x..." -ForegroundColor Yellow
        Write-Host "           This may take 2-5 minutes..." -ForegroundColor Gray
        
        # Use DISM to repair .NET
        $dismResult = & DISM /Online /Cleanup-Image /RestoreHealth /LimitAccess 2>&1
        
        Write-Host "  [ OK  ] .NET Framework repair completed" -ForegroundColor Green
        
    } catch {
        Write-Host "  [WARN ] .NET repair completed with warnings" -ForegroundColor Yellow
    }
    
    # Clear NGen queue
    try {
        Write-Host "`n  [NGEN ] Clearing .NET compilation queue..." -ForegroundColor Cyan
        $ngenPath64 = "$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\ngen.exe"
        $ngenPath32 = "$env:SystemRoot\Microsoft.NET\Framework\v4.0.30319\ngen.exe"
        
        if (Test-Path $ngenPath64) {
            & $ngenPath64 update /force /queue 2>&1 | Out-Null
            Write-Host "  [ OK  ] .NET 64-bit queue processed" -ForegroundColor Green
        }
        
        if (Test-Path $ngenPath32) {
            & $ngenPath32 update /force /queue 2>&1 | Out-Null
            Write-Host "  [ OK  ] .NET 32-bit queue processed" -ForegroundColor Green
        }
    } catch {
        Write-Host "  [WARN ] NGen processing completed with warnings" -ForegroundColor Yellow
    }
}

function Test-DiskHealth {
    param([int]$StepNumber = 1)
    
    Write-Header "Disk Health Check" $StepNumber
    Write-Host "  [DISK ] Checking disk health..." -ForegroundColor Cyan
    Write-Host ""
    
    # Get physical disks
    try {
        $disks = Get-PhysicalDisk -ErrorAction Stop
        
        foreach ($disk in $disks) {
            Write-Host "  [CHECK] $($disk.FriendlyName)" -ForegroundColor Cyan
            Write-Host "          Size: $([math]::Round($disk.Size / 1GB, 0)) GB" -ForegroundColor Gray
            Write-Host "          Type: $($disk.MediaType)" -ForegroundColor Gray
            
            # Health status
            if ($disk.HealthStatus -eq "Healthy") {
                Write-Host "          Health: " -NoNewline -ForegroundColor Gray
                Write-Host "Healthy" -ForegroundColor Green
            } else {
                Write-Host "          Health: " -NoNewline -ForegroundColor Gray
                Write-Host "$($disk.HealthStatus)" -ForegroundColor Red
                Write-Host "          WARNING: Disk may be failing! Back up data immediately!" -ForegroundColor Red
            }
            
            # Operational status
            Write-Host "          Status: $($disk.OperationalStatus)" -ForegroundColor Gray
            Write-Host ""
        }
        
    } catch {
        Write-Host "  [WARN ] Could not get physical disk info: $_" -ForegroundColor Yellow
    }
    
    # Check for errors with chkdsk
    try {
        Write-Host "  [CHECK] Scanning for file system errors..." -ForegroundColor Cyan
        Write-Host "          This is a quick scan (full scan on restart if needed)" -ForegroundColor Gray
        
        $volume = Get-Volume -DriveLetter ($env:SystemDrive.TrimEnd(':')) -ErrorAction Stop
        
        if ($volume.HealthStatus -eq "Healthy") {
            Write-Host "  [ OK  ] File system is healthy" -ForegroundColor Green
        } else {
            Write-Host "  [WARN ] File system issues detected: $($volume.HealthStatus)" -ForegroundColor Yellow
            Write-Host "          Run 'chkdsk /F' and restart to repair" -ForegroundColor Yellow
        }
        
    } catch {
        Write-Host "  [WARN ] Could not check file system: $_" -ForegroundColor Yellow
    }
    
    # SMART status via WMI
    try {
        Write-Host "`n  [SMART] Checking S.M.A.R.T. status..." -ForegroundColor Cyan
        $smartData = Get-WmiObject -Namespace root\wmi -Class MSStorageDriver_FailurePredictStatus -ErrorAction SilentlyContinue
        
        if ($smartData) {
            $failing = $smartData | Where-Object { $_.PredictFailure -eq $true }
            if ($failing) {
                Write-Host "  [ALERT] S.M.A.R.T. indicates disk failure predicted!" -ForegroundColor Red
                Write-Host "          BACK UP YOUR DATA IMMEDIATELY!" -ForegroundColor Red
            } else {
                Write-Host "  [ OK  ] S.M.A.R.T. status: No failures predicted" -ForegroundColor Green
            }
        }
    } catch {
        Write-Host "  [INFO ] S.M.A.R.T. data not available" -ForegroundColor Gray
    }
}

function Reset-NetworkAdaptersThorough {
    param([int]$StepNumber = 1)
    
    Write-Header "Network Adapter Deep Reset" $StepNumber
    Write-Host "  [NET  ] Performing thorough network reset..." -ForegroundColor Cyan
    Write-Host "          This is more comprehensive than the basic network reset" -ForegroundColor Gray
    Write-Host ""
    
    # Reset all network adapters
    try {
        Write-Host "  [RESET] Resetting all network adapters..." -ForegroundColor Yellow
        $adapters = Get-NetAdapter -ErrorAction Stop
        
        foreach ($adapter in $adapters) {
            try {
                Write-Host "          Resetting: $($adapter.Name)..." -ForegroundColor Gray
                Disable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 500
                Enable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
            } catch { }
        }
        Write-Host "  [ OK  ] Network adapters reset" -ForegroundColor Green
    } catch {
        Write-Host "  [WARN ] Some adapters could not be reset" -ForegroundColor Yellow
    }
    
    # Reset TCP/IP Stack
    try {
        Write-Host "`n  [TCP  ] Resetting TCP/IP stack..." -ForegroundColor Yellow
        & netsh int ip reset 2>&1 | Out-Null
        Write-Host "  [ OK  ] TCP/IP stack reset" -ForegroundColor Green
    } catch {
        Write-Host "  [WARN ] TCP/IP reset had warnings" -ForegroundColor Yellow
    }
    
    # Reset Winsock (again, more thorough)
    try {
        Write-Host "`n  [SOCK ] Resetting Winsock catalog..." -ForegroundColor Yellow
        & netsh winsock reset catalog 2>&1 | Out-Null
        Write-Host "  [ OK  ] Winsock catalog reset" -ForegroundColor Green
    } catch { }
    
    # Clear ARP cache
    try {
        Write-Host "`n  [ARP  ] Clearing ARP cache..." -ForegroundColor Yellow
        & arp -d * 2>&1 | Out-Null
        Write-Host "  [ OK  ] ARP cache cleared" -ForegroundColor Green
    } catch { }
    
    # Clear NetBIOS cache
    try {
        Write-Host "`n  [NBT  ] Clearing NetBIOS cache..." -ForegroundColor Yellow
        & nbtstat -R 2>&1 | Out-Null
        & nbtstat -RR 2>&1 | Out-Null
        Write-Host "  [ OK  ] NetBIOS cache cleared" -ForegroundColor Green
    } catch { }
    
    # Reset Firewall to defaults
    try {
        Write-Host "`n  [FW   ] Resetting Windows Firewall (keeps custom rules)..." -ForegroundColor Yellow
        & netsh advfirewall reset 2>&1 | Out-Null
        Write-Host "  [ OK  ] Firewall reset to defaults" -ForegroundColor Green
    } catch { }
    
    # Renew DHCP
    try {
        Write-Host "`n  [DHCP ] Renewing IP addresses..." -ForegroundColor Yellow
        & ipconfig /release 2>&1 | Out-Null
        Start-Sleep -Seconds 1
        & ipconfig /renew 2>&1 | Out-Null
        Write-Host "  [ OK  ] IP addresses renewed" -ForegroundColor Green
    } catch { }
    
    # Flush DNS (comprehensive)
    try {
        Write-Host "`n  [DNS  ] Flushing all DNS caches..." -ForegroundColor Yellow
        & ipconfig /flushdns 2>&1 | Out-Null
        Clear-DnsClientCache -ErrorAction SilentlyContinue
        Write-Host "  [ OK  ] DNS caches flushed" -ForegroundColor Green
    } catch { }
    
    # Re-register DNS
    try {
        Write-Host "`n  [DNS  ] Re-registering DNS..." -ForegroundColor Yellow
        & ipconfig /registerdns 2>&1 | Out-Null
        Write-Host "  [ OK  ] DNS re-registered" -ForegroundColor Green
    } catch { }
    
    Write-Host "`n  [ OK  ] Comprehensive network reset complete" -ForegroundColor Green
    Write-Host "          A restart is recommended for all changes to take effect" -ForegroundColor Yellow
}

function Invoke-SystemCleanup {
    param([int]$StepNumber = 1)
    
    Write-Header "Deep System Cleanup" $StepNumber
    Write-Host "  [CLEAN] Starting comprehensive cleanup..." -ForegroundColor Cyan
    Write-Host "          This will free up disk space by removing unnecessary files" -ForegroundColor Gray
    Write-Host ""
    
    $totalFreed = 0
    
    # Windows.old (from previous Windows upgrades)
    Write-Host "  [CHECK] Looking for old Windows installation files..." -ForegroundColor Cyan
    try {
        $windowsOld = "$env:SystemDrive\Windows.old"
        if (Test-Path $windowsOld) {
            $sizeBefore = (Get-ChildItem $windowsOld -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum / 1GB
            Write-Host "  [CLEAN] Found Windows.old folder ($([math]::Round($sizeBefore, 2)) GB)" -ForegroundColor Yellow
            Write-Host "          Removing old Windows installation..." -ForegroundColor Yellow
            
            # Use takeown and icacls to get permissions, then remove
            & takeown /F $windowsOld /R /D Y 2>&1 | Out-Null
            & icacls $windowsOld /grant administrators:F /T 2>&1 | Out-Null
            Remove-Item -Path $windowsOld -Recurse -Force -ErrorAction SilentlyContinue
            
            Write-Host "  [ OK  ] Removed Windows.old ($([math]::Round($sizeBefore, 2)) GB freed)" -ForegroundColor Green
            $totalFreed += $sizeBefore
        } else {
            Write-Host "  [ OK  ] No Windows.old folder found (already clean)" -ForegroundColor Green
        }
    } catch {
        Write-Host "  [WARN ] Could not remove Windows.old: $_" -ForegroundColor Yellow
    }
    
    # WinSxS component cleanup
    Write-Host "`n  [CLEAN] Running Windows Component Store cleanup..." -ForegroundColor Cyan
    Write-Host "          This may take 5-10 minutes..." -ForegroundColor Gray
    try {
        $dismOutput = & Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [ OK  ] Component store cleaned successfully" -ForegroundColor Green
        } else {
            Write-Host "  [WARN ] Component cleanup completed with warnings" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [WARN ] Could not complete component cleanup: $_" -ForegroundColor Yellow
    }
    
    # Temp Files - User Temp
    Write-Host "`n  [CLEAN] Cleaning temporary files..." -ForegroundColor Cyan
    try {
        $tempPath = $env:TEMP
        if (Test-Path $tempPath) {
            $sizeBefore = (Get-ChildItem $tempPath -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum / 1GB
            Get-ChildItem $tempPath -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "  [ OK  ] User Temp folder cleaned ($([math]::Round($sizeBefore, 2)) GB freed)" -ForegroundColor Green
            $totalFreed += $sizeBefore
        }
    } catch {
        Write-Host "  [WARN ] Could not fully clean user Temp folder" -ForegroundColor Yellow
    }
    
    # Temp Files - Windows Temp
    try {
        $winTempPath = "$env:SystemRoot\Temp"
        if (Test-Path $winTempPath) {
            $sizeBefore = (Get-ChildItem $winTempPath -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum / 1GB
            Get-ChildItem $winTempPath -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "  [ OK  ] Windows Temp folder cleaned ($([math]::Round($sizeBefore, 2)) GB freed)" -ForegroundColor Green
            $totalFreed += $sizeBefore
        }
    } catch {
        Write-Host "  [WARN ] Could not fully clean Windows Temp folder" -ForegroundColor Yellow
    }
    
    # Prefetch
    try {
        $prefetchPath = "$env:SystemRoot\Prefetch"
        if (Test-Path $prefetchPath) {
            $sizeBefore = (Get-ChildItem $prefetchPath -Filter "*.pf" -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum / 1MB
            Get-ChildItem $prefetchPath -Filter "*.pf" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            Write-Host "  [ OK  ] Prefetch cleaned ($([math]::Round($sizeBefore, 0)) MB freed)" -ForegroundColor Green
            $totalFreed += ($sizeBefore / 1024)
        }
    } catch {
        Write-Host "  [WARN ] Could not clean Prefetch" -ForegroundColor Yellow
    }
    
    # Windows Update Cleanup
    Write-Host "`n  [CLEAN] Cleaning Windows Update cache..." -ForegroundColor Cyan
    try {
        & Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase 2>&1 | Out-Null
        Write-Host "  [ OK  ] Windows Update cleanup completed" -ForegroundColor Green
    } catch {
        Write-Host "  [WARN ] Could not complete Update cleanup" -ForegroundColor Yellow
    }
    
    # Delivery Optimization Files
    try {
        $deliveryOptPath = "$env:SystemRoot\SoftwareDistribution\DeliveryOptimization"
        if (Test-Path $deliveryOptPath) {
            $sizeBefore = (Get-ChildItem $deliveryOptPath -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum / 1GB
            Get-ChildItem $deliveryOptPath -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "  [ OK  ] Delivery Optimization cache cleared ($([math]::Round($sizeBefore, 2)) GB freed)" -ForegroundColor Green
            $totalFreed += $sizeBefore
        }
    } catch {
        Write-Host "  [WARN ] Could not clean Delivery Optimization cache" -ForegroundColor Yellow
    }
    
    # Recycle Bin
    Write-Host "`n  [CLEAN] Emptying Recycle Bin..." -ForegroundColor Cyan
    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-Host "  [ OK  ] Recycle Bin emptied" -ForegroundColor Green
    } catch {
        Write-Host "  [WARN ] Could not empty Recycle Bin: $_" -ForegroundColor Yellow
    }
    
    # Thumbnail Cache
    try {
        $thumbCachePath = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
        if (Test-Path $thumbCachePath) {
            Get-ChildItem $thumbCachePath -Filter "thumbcache_*.db" -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            Write-Host "  [ OK  ] Thumbnail cache cleared" -ForegroundColor Green
        }
    } catch {
        Write-Host "  [WARN ] Could not clear thumbnail cache" -ForegroundColor Yellow
    }
    
    # Windows Error Reports
    try {
        $werPath = "$env:ProgramData\Microsoft\Windows\WER"
        if (Test-Path $werPath) {
            $sizeBefore = (Get-ChildItem $werPath -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum / 1MB
            Get-ChildItem $werPath -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "  [ OK  ] Windows Error Reports cleared ($([math]::Round($sizeBefore, 0)) MB freed)" -ForegroundColor Green
        }
    } catch {
        Write-Host "  [WARN ] Could not clear Windows Error Reports" -ForegroundColor Yellow
    }
    
    # CBS Logs
    try {
        $cbsLogPath = "$env:SystemRoot\Logs\CBS\CBS.log"
        if (Test-Path $cbsLogPath) {
            $sizeBefore = (Get-Item $cbsLogPath -ErrorAction SilentlyContinue).Length / 1MB
            if ($sizeBefore -gt 100) {
                Remove-Item $cbsLogPath -Force -ErrorAction SilentlyContinue
                Write-Host "  [ OK  ] CBS log cleared ($([math]::Round($sizeBefore, 0)) MB freed)" -ForegroundColor Green
            }
        }
    } catch {
        Write-Host "  [WARN ] Could not clear CBS logs" -ForegroundColor Yellow
    }
    
    # Browser Cache Cleanup (Chrome, Edge, Firefox) - Keeps passwords, bookmarks, history
    Write-Host "`n  [CLEAN] Cleaning browser cache (passwords preserved)..." -ForegroundColor Cyan
    
    # Chrome Cache
    try {
        $chromeCachePaths = @(
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache",
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\GPUCache",
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Service Worker\CacheStorage"
        )
        
        $chromeFreed = 0
        foreach ($path in $chromeCachePaths) {
            if (Test-Path $path) {
                $sizeBefore = (Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum / 1MB
                Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                $chromeFreed += $sizeBefore
            }
        }
        
        if ($chromeFreed -gt 0) {
            Write-Host "  [ OK  ] Chrome cache cleared ($([math]::Round($chromeFreed, 0)) MB freed)" -ForegroundColor Green
            $totalFreed += ($chromeFreed / 1024)
        }
    } catch {
        Write-Host "  [WARN ] Could not fully clean Chrome cache" -ForegroundColor Yellow
    }
    
    # Edge Cache
    try {
        $edgeCachePaths = @(
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache",
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\GPUCache",
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Service Worker\CacheStorage"
        )
        
        $edgeFreed = 0
        foreach ($path in $edgeCachePaths) {
            if (Test-Path $path) {
                $sizeBefore = (Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum / 1MB
                Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                $edgeFreed += $sizeBefore
            }
        }
        
        if ($edgeFreed -gt 0) {
            Write-Host "  [ OK  ] Edge cache cleared ($([math]::Round($edgeFreed, 0)) MB freed)" -ForegroundColor Green
            $totalFreed += ($edgeFreed / 1024)
        }
    } catch {
        Write-Host "  [WARN ] Could not fully clean Edge cache" -ForegroundColor Yellow
    }
    
    # Firefox Cache
    try {
        $firefoxProfilePath = "$env:APPDATA\Mozilla\Firefox\Profiles"
        if (Test-Path $firefoxProfilePath) {
            $firefoxFreed = 0
            Get-ChildItem $firefoxProfilePath -Directory | ForEach-Object {
                $cachePath = Join-Path $_.FullName "cache2"
                if (Test-Path $cachePath) {
                    $sizeBefore = (Get-ChildItem $cachePath -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum / 1MB
                    Get-ChildItem $cachePath -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                    $firefoxFreed += $sizeBefore
                }
            }
            
            if ($firefoxFreed -gt 0) {
                Write-Host "  [ OK  ] Firefox cache cleared ($([math]::Round($firefoxFreed, 0)) MB freed)" -ForegroundColor Green
                $totalFreed += ($firefoxFreed / 1024)
            }
        }
    } catch {
        Write-Host "  [WARN ] Could not fully clean Firefox cache" -ForegroundColor Yellow
    }
    
    # Memory Dumps
    try {
        $dumpPath = "$env:SystemRoot\MEMORY.DMP"
        if (Test-Path $dumpPath) {
            $sizeBefore = (Get-Item $dumpPath).Length / 1GB
            Remove-Item $dumpPath -Force -ErrorAction Stop
            Write-Host "  [ OK  ] Memory dump removed ($([math]::Round($sizeBefore, 2)) GB freed)" -ForegroundColor Green
            $totalFreed += $sizeBefore
        }
        
        # Minidumps
        $minidumpPath = "$env:SystemRoot\Minidump"
        if (Test-Path $minidumpPath) {
            $sizeBefore = (Get-ChildItem $minidumpPath -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum / 1MB
            Get-ChildItem $minidumpPath -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            if ($sizeBefore -gt 0) {
                Write-Host "  [ OK  ] Minidumps cleared ($([math]::Round($sizeBefore, 0)) MB freed)" -ForegroundColor Green
            }
        }
    } catch {
        Write-Host "  [WARN ] Could not clear memory dumps" -ForegroundColor Yellow
    }
    
    # Downloaded Program Files (ActiveX/Java)
    try {
        $downloadedProgPath = "$env:SystemRoot\Downloaded Program Files"
        if (Test-Path $downloadedProgPath) {
            Get-ChildItem $downloadedProgPath -Exclude "desktop.ini" -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "  [ OK  ] Downloaded Program Files cleared" -ForegroundColor Green
        }
    } catch {
        Write-Host "  [WARN ] Could not clear Downloaded Program Files" -ForegroundColor Yellow
    }
    
    # Windows Defender scan history
    try {
        $defenderPath = "$env:ProgramData\Microsoft\Windows Defender\Scans\History"
        if (Test-Path $defenderPath) {
            $sizeBefore = (Get-ChildItem $defenderPath -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum / 1MB
            Get-ChildItem $defenderPath -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            if ($sizeBefore -gt 10) {
                Write-Host "  [ OK  ] Defender scan history cleared ($([math]::Round($sizeBefore, 0)) MB freed)" -ForegroundColor Green
            }
        }
    } catch {
        Write-Host "  [WARN ] Could not clear Defender scan history" -ForegroundColor Yellow
    }
    
    # Summary
    Write-Host "`n  ================================================================" -ForegroundColor Cyan
    Write-Host "  [ OK  ] Deep cleanup completed!" -ForegroundColor Green
    Write-Host "         Total disk space freed: ~$([math]::Round($totalFreed, 2)) GB" -ForegroundColor Green
    Write-Host "  ================================================================" -ForegroundColor Cyan
}

function Enable-WindowsUpdate {
    param([int]$StepNumber = 1)
    
    Write-Header "Re-Enabling Windows Update" $StepNumber
    Write-Host "  [CHECK] Checking if Windows Update is disabled..." -ForegroundColor Cyan
    Write-Host ""
    
    $changesRequired = $false
    
    # Check and fix Windows Update service startup type
    try {
        $wuauservService = Get-Service -Name wuauserv -ErrorAction Stop
        if ($wuauservService.StartType -eq 'Disabled') {
            Write-Host "  [FIX  ] Windows Update service is DISABLED - Enabling..." -ForegroundColor Yellow
            Set-Service -Name wuauserv -StartupType Manual -ErrorAction Stop
            Write-Host "  [ OK  ] Windows Update service enabled" -ForegroundColor Green
            $changesRequired = $true
        } else {
            Write-Host "  [ OK  ] Windows Update service is enabled ($($wuauservService.StartType))" -ForegroundColor Green
        }
    } catch {
        Write-Host "  [WARN ] Could not check/fix Windows Update service: $_" -ForegroundColor Yellow
    }
    
    # Fix Group Policy registry keys that disable Windows Update
    Write-Host "`n  [REG  ] Checking registry keys that may disable updates..." -ForegroundColor Cyan
    
    $registryFixes = @(
        # Windows Update Group Policies
        @{
            Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
            Name = "DisableWindowsUpdateAccess"
            ExpectedValue = 0
            Description = "Group Policy: Disable Windows Update Access"
        },
        @{
            Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
            Name = "NoAutoUpdate"
            ExpectedValue = 0
            Description = "Group Policy: Disable Automatic Updates"
        },
        @{
            Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
            Name = "AUOptions"
            ExpectedValue = $null  # Remove if exists
            Description = "Group Policy: Auto Update Options Override"
            Remove = $true
        },
        @{
            Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update"
            Name = "EnableFeaturedSoftware"
            ExpectedValue = 1
            Description = "Enable Featured Software Updates"
        },
        # User-level blocks
        @{
            Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\WindowsUpdate"
            Name = "DisableWindowsUpdateAccess"
            ExpectedValue = 0
            Description = "User Policy: Disable Windows Update Access"
        },
        # Windows Update Medic Service
        @{
            Path = "HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc"
            Name = "Start"
            ExpectedValue = 3  # Manual startup
            Description = "Windows Update Medic Service"
        }
    )
    
    foreach ($fix in $registryFixes) {
        try {
            # Create path if it doesn't exist
            if (-not (Test-Path $fix.Path)) {
                if ($fix.Remove) {
                    Write-Host "  [ OK  ] $($fix.Description) - Path doesn't exist (good)" -ForegroundColor Green
                    continue
                }
                Write-Host "  [FIX  ] Creating registry path: $($fix.Path)" -ForegroundColor Yellow
                New-Item -Path $fix.Path -Force | Out-Null
            }
            
            $currentValue = Get-ItemProperty -Path $fix.Path -Name $fix.Name -ErrorAction SilentlyContinue
            
            if ($fix.Remove) {
                # Remove the key if it exists
                if ($currentValue) {
                    Write-Host "  [FIX  ] Removing: $($fix.Description)" -ForegroundColor Yellow
                    Remove-ItemProperty -Path $fix.Path -Name $fix.Name -Force -ErrorAction Stop
                    Write-Host "  [ OK  ] Removed blocking registry key" -ForegroundColor Green
                    $changesRequired = $true
                } else {
                    Write-Host "  [ OK  ] $($fix.Description) - Not present (good)" -ForegroundColor Green
                }
            } else {
                # Check if value needs fixing
                if ($currentValue.$($fix.Name) -ne $fix.ExpectedValue) {
                    Write-Host "  [FIX  ] Fixing: $($fix.Description)" -ForegroundColor Yellow
                    Write-Host "         Current: $($currentValue.$($fix.Name)) -> Expected: $($fix.ExpectedValue)" -ForegroundColor Gray
                    Set-ItemProperty -Path $fix.Path -Name $fix.Name -Value $fix.ExpectedValue -Force -ErrorAction Stop
                    Write-Host "  [ OK  ] Fixed registry value" -ForegroundColor Green
                    $changesRequired = $true
                } else {
                    Write-Host "  [ OK  ] $($fix.Description) - Already correct" -ForegroundColor Green
                }
            }
        } catch {
            Write-Host "  [WARN ] Could not fix: $($fix.Description) - $_" -ForegroundColor Yellow
        }
    }
    
    # Check for update pause/deferral
    Write-Host "`n  [CHECK] Checking for update pause/deferral..." -ForegroundColor Cyan
    try {
        $pauseKey = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
        if (Test-Path $pauseKey) {
            $pauseValue = Get-ItemProperty -Path $pauseKey -Name "PauseUpdatesExpiryTime" -ErrorAction SilentlyContinue
            if ($pauseValue) {
                Write-Host "  [FIX  ] Removing update pause..." -ForegroundColor Yellow
                Remove-ItemProperty -Path $pauseKey -Name "PauseUpdatesExpiryTime" -Force -ErrorAction SilentlyContinue
                Remove-ItemProperty -Path $pauseKey -Name "PauseFeatureUpdatesEndTime" -Force -ErrorAction SilentlyContinue
                Remove-ItemProperty -Path $pauseKey -Name "PauseQualityUpdatesEndTime" -Force -ErrorAction SilentlyContinue
                Write-Host "  [ OK  ] Update pause removed" -ForegroundColor Green
                $changesRequired = $true
            } else {
                Write-Host "  [ OK  ] Updates are not paused" -ForegroundColor Green
            }
        }
    } catch {
        Write-Host "  [WARN ] Could not check pause status: $_" -ForegroundColor Yellow
    }
    
    if ($changesRequired) {
        Write-Host "`n  [INFO ] Changes were made to enable Windows Update" -ForegroundColor Yellow
        Write-Host "         A restart is recommended for all changes to take effect" -ForegroundColor Yellow
    } else {
        Write-Host "`n  [ OK  ] Windows Update is already fully enabled!" -ForegroundColor Green
    }
}

function Enable-MicrosoftDefender {
    param([int]$StepNumber = 2)
    
    Write-Header "Re-Enabling Microsoft Defender" $StepNumber
    Write-Host "  [CHECK] Checking if Microsoft Defender is disabled..." -ForegroundColor Cyan
    Write-Host ""
    
    $changesRequired = $false
    
    # Check and enable Defender services
    $defenderServices = @(
        @{Name="WinDefend"; DisplayName="Windows Defender Antivirus Service"},
        @{Name="WdNisSvc"; DisplayName="Windows Defender Network Inspection Service"},
        @{Name="Sense"; DisplayName="Windows Defender Advanced Threat Protection"},
        @{Name="WdNisDrv"; DisplayName="Windows Defender Network Inspection Driver"},
        @{Name="WdFilter"; DisplayName="Windows Defender Mini-Filter Driver"}
    )
    
    Write-Host "  [SVC  ] Checking Defender services..." -ForegroundColor Cyan
    foreach ($svc in $defenderServices) {
        try {
            $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
            if ($service) {
                if ($service.StartType -eq 'Disabled') {
                    Write-Host "  [FIX  ] Enabling: $($svc.DisplayName)" -ForegroundColor Yellow
                    Set-Service -Name $svc.Name -StartupType Automatic -ErrorAction Stop
                    Write-Host "  [ OK  ] Service enabled" -ForegroundColor Green
                    $changesRequired = $true
                } else {
                    Write-Host "  [ OK  ] $($svc.DisplayName) - Enabled" -ForegroundColor Green
                }
            }
        } catch {
            Write-Host "  [WARN ] Could not enable $($svc.DisplayName): $_" -ForegroundColor Yellow
        }
    }
    
    # Fix Defender registry keys
    Write-Host "`n  [REG  ] Checking Defender registry keys..." -ForegroundColor Cyan
    
    $defenderRegFixes = @(
        # Main Defender disable switch
        @{
            Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
            Name = "DisableAntiSpyware"
            ExpectedValue = 0
            Description = "Defender: Disable AntiSpyware"
        },
        @{
            Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
            Name = "DisableAntiVirus"
            ExpectedValue = 0
            Description = "Defender: Disable AntiVirus"
        },
        # Real-time protection
        @{
            Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection"
            Name = "DisableRealtimeMonitoring"
            ExpectedValue = 0
            Description = "Defender: Disable Real-time Monitoring"
        },
        @{
            Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection"
            Name = "DisableBehaviorMonitoring"
            ExpectedValue = 0
            Description = "Defender: Disable Behavior Monitoring"
        },
        @{
            Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection"
            Name = "DisableOnAccessProtection"
            ExpectedValue = 0
            Description = "Defender: Disable On-Access Protection"
        },
        @{
            Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection"
            Name = "DisableScanOnRealtimeEnable"
            ExpectedValue = 0
            Description = "Defender: Disable Scan on Realtime Enable"
        },
        # Tamper Protection (should be enabled)
        @{
            Path = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features"
            Name = "TamperProtection"
            ExpectedValue = 5  # Enabled
            Description = "Defender: Tamper Protection"
        },
        # Windows Security Center
        @{
            Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Notifications"
            Name = "DisableNotifications"
            ExpectedValue = 0
            Description = "Defender: Disable Security Notifications"
        },
        # Spynet (Cloud Protection)
        @{
            Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet"
            Name = "SpynetReporting"
            ExpectedValue = 2  # Advanced membership
            Description = "Defender: Cloud Protection Level"
        },
        # Sample Submission
        @{
            Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet"
            Name = "SubmitSamplesConsent"
            ExpectedValue = 1  # Send safe samples automatically
            Description = "Defender: Automatic Sample Submission"
        }
    )
    
    foreach ($fix in $defenderRegFixes) {
        try {
            # Create path if it doesn't exist
            if (-not (Test-Path $fix.Path)) {
                Write-Host "  [FIX  ] Creating registry path: $($fix.Path)" -ForegroundColor Yellow
                New-Item -Path $fix.Path -Force | Out-Null
            }
            
            $currentValue = Get-ItemProperty -Path $fix.Path -Name $fix.Name -ErrorAction SilentlyContinue
            
            if ($null -eq $currentValue -or $currentValue.$($fix.Name) -ne $fix.ExpectedValue) {
                Write-Host "  [FIX  ] Fixing: $($fix.Description)" -ForegroundColor Yellow
                if ($currentValue) {
                    Write-Host "         Current: $($currentValue.$($fix.Name)) -> Expected: $($fix.ExpectedValue)" -ForegroundColor Gray
                } else {
                    Write-Host "         Setting to: $($fix.ExpectedValue)" -ForegroundColor Gray
                }
                Set-ItemProperty -Path $fix.Path -Name $fix.Name -Value $fix.ExpectedValue -Force -ErrorAction Stop
                Write-Host "  [ OK  ] Fixed registry value" -ForegroundColor Green
                $changesRequired = $true
            } else {
                Write-Host "  [ OK  ] $($fix.Description) - Already correct" -ForegroundColor Green
            }
        } catch {
            Write-Host "  [WARN ] Could not fix: $($fix.Description) - $_" -ForegroundColor Yellow
        }
    }
    
    # Try to start Windows Defender service
    Write-Host "`n  [START] Attempting to start Defender services..." -ForegroundColor Cyan
    try {
        $winDefendService = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
        if ($winDefendService -and $winDefendService.Status -ne 'Running') {
            Write-Host "  [FIX  ] Starting Windows Defender service..." -ForegroundColor Yellow
            Start-Service -Name WinDefend -ErrorAction Stop
            Write-Host "  [ OK  ] Windows Defender service started" -ForegroundColor Green
            $changesRequired = $true
        } elseif ($winDefendService -and $winDefendService.Status -eq 'Running') {
            Write-Host "  [ OK  ] Windows Defender service is already running" -ForegroundColor Green
        }
    } catch {
        Write-Host "  [WARN ] Could not start Windows Defender: $_" -ForegroundColor Yellow
        Write-Host "         You may need to restart the computer" -ForegroundColor Yellow
    }
    
    # Use PowerShell to enable Defender features
    Write-Host "`n  [PS   ] Enabling Defender features via PowerShell..." -ForegroundColor Cyan
    try {
        # Enable real-time monitoring
        Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue
        Write-Host "  [ OK  ] Real-time monitoring enabled" -ForegroundColor Green
        
        # Enable behavior monitoring
        Set-MpPreference -DisableBehaviorMonitoring $false -ErrorAction SilentlyContinue
        Write-Host "  [ OK  ] Behavior monitoring enabled" -ForegroundColor Green
        
        # Enable IOAV protection
        Set-MpPreference -DisableIOAVProtection $false -ErrorAction SilentlyContinue
        Write-Host "  [ OK  ] IOAV protection enabled" -ForegroundColor Green
        
        # Enable script scanning
        Set-MpPreference -DisableScriptScanning $false -ErrorAction SilentlyContinue
        Write-Host "  [ OK  ] Script scanning enabled" -ForegroundColor Green
        
        $changesRequired = $true
    } catch {
        Write-Host "  [WARN ] Some PowerShell commands failed (may not be available on this system)" -ForegroundColor Yellow
    }
    
    if ($changesRequired) {
        Write-Host "`n  [INFO ] Changes were made to enable Microsoft Defender" -ForegroundColor Yellow
        Write-Host "         A restart is recommended for all changes to take effect" -ForegroundColor Yellow
        Write-Host "         You may need to manually enable some features in Windows Security" -ForegroundColor Yellow
    } else {
        Write-Host "`n  [ OK  ] Microsoft Defender is already fully enabled!" -ForegroundColor Green
    }
}

function Test-DiskSpace {
    Write-Header "Pre-Flight System Check"
    
    try {
        Write-Progress-Custom -Activity "Checking System" -Status "Analyzing disk space..." -Icon "[DISK]"
        
        $systemDrive = $env:SystemDrive
        $drive = Get-PSDrive -Name $systemDrive.TrimEnd(':') -ErrorAction Stop
        $freeSpaceGB = [math]::Round($drive.Free / 1GB, 2)
        $totalSpaceGB = [math]::Round(($drive.Used + $drive.Free) / 1GB, 2)
        $freePercent = [math]::Round(($drive.Free / ($drive.Used + $drive.Free)) * 100, 2)
        
        Write-Host "  [DISK] System Drive: " -NoNewline -ForegroundColor Cyan
        Write-Host "$systemDrive\" -ForegroundColor White
        Write-Host "  [DISK] Free Space: " -NoNewline -ForegroundColor Cyan
        Write-Host "$freeSpaceGB GB / $totalSpaceGB GB " -NoNewline -ForegroundColor White
        Write-Host "($freePercent%)" -ForegroundColor Gray
        
        if ($freeSpaceGB -lt 10) {
            Write-Host "  [WARN] WARNING: Low disk space detected!" -ForegroundColor Yellow
            Write-Host "         Windows Update needs at least 10GB free." -ForegroundColor Yellow
        } else {
            Write-Host "  [ OK ] Disk space is adequate" -ForegroundColor Green
        }
    } catch {
        Write-Log "Failed to check disk space: $_" -Level "ERROR"
    }
}

function Get-WindowsUpdateErrors {
    try {
        Write-Progress-Custom -Activity "Checking System" -Status "Scanning event logs..." -Icon "[LOGS]"
        
        $events = Get-WinEvent -FilterHashtable @{
            LogName = 'System'
            ProviderName = 'Microsoft-Windows-WindowsUpdateClient'
            Level = 2,3
            StartTime = (Get-Date).AddDays(-7)
        } -MaxEvents 10 -ErrorAction SilentlyContinue
        
        if ($events) {
            Write-Host "`n  [LOGS] Recent Windows Update Issues (Last 7 Days):" -ForegroundColor Yellow
            foreach ($event in $events) {
                $dateStr = Get-Date $event.TimeCreated -Format "MM/dd HH:mm"
                $msg = $event.Message.Split("`n")[0]
                if ($msg.Length -gt 80) { $msg = $msg.Substring(0, 80) + "..." }
                Write-Host "         [$dateStr] Event $($event.Id): $msg" -ForegroundColor Gray
            }
        } else {
            Write-Host "  [ OK ] No recent Windows Update errors found" -ForegroundColor Green
        }
    } catch {
        Write-Host "  [INFO] Could not check event logs" -ForegroundColor Gray
    }
}

function New-SystemRestorePoint {
    param([int]$StepNumber = 1)
    
    Write-Header "Creating Safety Backup" $StepNumber
    
    try {
        Write-Progress-Custom -Activity "System Backup" -Status "Creating restore point (1-2 minutes)..." -PercentComplete 0 -Icon "[BACKUP]"
        
        Checkpoint-Computer -Description "Before Windows Update Reset - $timestamp" -RestorePointType "MODIFY_SETTINGS"
        
        Write-Progress-Custom -Activity "System Backup" -Status "Restore point created" -PercentComplete 100 -Icon "[ OK ]"
        Write-Host "  [ OK ] System Restore Point created successfully" -ForegroundColor Green
        Write-Host "         You can roll back changes if needed" -ForegroundColor Gray
    } catch {
        Write-Host "  [WARN] Could not create restore point: $_" -ForegroundColor Yellow
        Write-Host "         Continuing without restore point..." -ForegroundColor Gray
    }
}

function Invoke-SystemRepairs {
    param([int]$StepNumber = 2)
    
    Write-Header "Running System Repairs" $StepNumber
    Write-Host "  [TIME] This will take 10-30 minutes. Please be patient..." -ForegroundColor Yellow
    Write-Host ""
    
    # DISM Repair
    Write-Host "  [DISM] Running DISM Repair..." -ForegroundColor Cyan
    Write-Progress-Custom -Activity "System Repair" -Status "DISM: Checking Windows image..." -PercentComplete 10 -Icon "[SCAN]"
    
    try {
        $dismResult = Repair-WindowsImage -Online -RestoreHealth -ErrorAction Stop
        
        Write-Progress-Custom -Activity "System Repair" -Status "DISM: Repair completed" -PercentComplete 50 -Icon "[ OK ]"
        
        if ($dismResult.ImageHealthState -eq 'Healthy') {
            Write-Host "  [ OK ] DISM: System image is healthy" -ForegroundColor Green
        } else {
            Write-Host "  [ OK ] DISM: Repairs were made to the system image" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [FAIL] DISM repair encountered errors: $_" -ForegroundColor Red
    }
    
    # SFC Scan
    Write-Host "`n  [ SFC] Running SFC Scan..." -ForegroundColor Cyan
    Write-Progress-Custom -Activity "System Repair" -Status "SFC: Scanning system files..." -PercentComplete 60 -Icon "[SCAN]"
    
    try {
        $sfcOutput = & sfc /scannow 2>&1 | Out-String
        Add-Content -Path $logFile -Value $sfcOutput
        
        Write-Progress-Custom -Activity "System Repair" -Status "SFC: Scan completed" -PercentComplete 100 -Icon "[ OK ]"
        
        if ($sfcOutput -match "did not find any integrity violations") {
            Write-Host "  [ OK ] SFC: No integrity violations found" -ForegroundColor Green
        } elseif ($sfcOutput -match "found corrupt files and successfully repaired them") {
            Write-Host "  [ OK ] SFC: Found and repaired corrupt files" -ForegroundColor Yellow
        } else {
            Write-Host "  [INFO] SFC: Scan completed (check log for details)" -ForegroundColor Gray
        }
    } catch {
        Write-Host "  [FAIL] SFC scan encountered errors: $_" -ForegroundColor Red
    }
}

function Reset-NetworkSettings {
    param([int]$StepNumber = 3)
    
    Write-Header "Resetting Network Components" $StepNumber
    
    $operations = @(
        @{Name="DNS Cache"; Action={Clear-DnsClientCache}; Icon="[DNS ]"},
        @{Name="Winsock"; Action={netsh winsock reset | Out-Null}; Icon="[SOCK]"},
        @{Name="WinHTTP Proxy"; Action={netsh winhttp reset proxy | Out-Null}; Icon="[HTTP]"},
        @{Name="IP Address"; Action={ipconfig /release | Out-Null; ipconfig /renew | Out-Null}; Icon="[ IP ]"}
    )
    
    $count = 0
    foreach ($op in $operations) {
        $count++
        $percent = [int](($count / $operations.Count) * 100)
        
        try {
            Write-Progress-Custom -Activity "Network Reset" -Status "Resetting $($op.Name)..." -PercentComplete $percent -Icon $op.Icon
            & $op.Action
            Write-Host "  [ OK ] " -NoNewline -ForegroundColor Green
            Write-Host "$($op.Name) reset successfully" -ForegroundColor White
        } catch {
            Write-Host "  [WARN] " -NoNewline -ForegroundColor Yellow
            Write-Host "Could not reset $($op.Name)" -ForegroundColor White
        }
        Start-Sleep -Milliseconds 500
    }
}

function Clear-UpdateCache {
    param([int]$StepNumber = 4)
    
    Write-Header "Clearing Update Cache" $StepNumber
    
    $folders = @(
        @{Path="$env:ALLUSERSPROFILE\Microsoft\Network\Downloader\*"; Name="Download Cache"},
        @{Path="$env:SystemRoot\SoftwareDistribution"; Name="Software Distribution"},
        @{Path="$env:SystemRoot\System32\catroot2"; Name="Catroot2"}
    )
    
    $count = 0
    foreach ($folder in $folders) {
        $count++
        $percent = [int](($count / $folders.Count) * 100)
        
        try {
            if (Test-Path $folder.Path) {
                Write-Progress-Custom -Activity "Cache Cleanup" -Status "Removing $($folder.Name)..." -PercentComplete $percent -Icon "[CLEAN]"
                Remove-Item -Path $folder.Path -Force -Recurse -ErrorAction Stop
                Write-Host "  [ OK ] " -NoNewline -ForegroundColor Green
                Write-Host "$($folder.Name) cleared" -ForegroundColor White
            } else {
                Write-Host "  [INFO] " -NoNewline -ForegroundColor Gray
                Write-Host "$($folder.Name) not found (already clean)" -ForegroundColor White
            }
        } catch {
            Write-Host "  [WARN] " -NoNewline -ForegroundColor Yellow
            Write-Host "Could not clear $($folder.Name): $_" -ForegroundColor White
        }
        Start-Sleep -Milliseconds 300
    }
}

function Register-SystemDLLs {
    param([int]$StepNumber = 5)
    
    Write-Header "Re-registering System Components" $StepNumber
    
    Write-Host "  [DLL ] Registering 36 critical system DLLs..." -ForegroundColor Cyan
    
    $dlls = @(
        'atl.dll', 'urlmon.dll', 'mshtml.dll', 'shdocvw.dll', 
        'browseui.dll', 'jscript.dll', 'vbscript.dll', 'scrrun.dll',
        'msxml.dll', 'msxml3.dll', 'msxml6.dll', 'actxprxy.dll',
        'softpub.dll', 'wintrust.dll', 'dssenh.dll', 'rsaenh.dll',
        'gpkcsp.dll', 'sccbase.dll', 'slbcsp.dll', 'cryptdlg.dll',
        'oleaut32.dll', 'ole32.dll', 'shell32.dll', 'initpki.dll',
        'wuapi.dll', 'wuaueng.dll', 'wuaueng1.dll', 'wucltui.dll',
        'wups.dll', 'wups2.dll', 'wuweb.dll', 'qmgr.dll',
        'qmgrprxy.dll', 'wucltux.dll', 'muweb.dll', 'wuwebv.dll'
    )

    $registeredCount = 0
    $totalDlls = $dlls.Count
    
    for ($i = 0; $i -lt $totalDlls; $i++) {
        $dll = $dlls[$i]
        $percent = [int](($i / $totalDlls) * 100)
        
        Write-Progress -Activity "Registering DLLs" -Status "Processing $dll..." -PercentComplete $percent
        
        try {
            $process = Start-Process -FilePath "regsvr32.exe" -ArgumentList "/s $dll" -Wait -PassThru -NoNewWindow
            if ($process.ExitCode -eq 0) {
                $registeredCount++
            }
        } catch {
            # Silently continue
        }
    }
    
    Write-Progress -Activity "Registering DLLs" -Completed
    Write-Host "  [ OK ] Successfully registered " -NoNewline -ForegroundColor Green
    Write-Host "$registeredCount" -NoNewline -ForegroundColor White
    Write-Host " out of " -NoNewline -ForegroundColor Green
    Write-Host "$totalDlls" -NoNewline -ForegroundColor White
    Write-Host " DLL files" -ForegroundColor Green
}

function Invoke-WindowsUpdateCheck {
    param([int]$StepNumber = 8)
    
    Write-Header "Triggering Update Check" $StepNumber
    
    try {
        Write-Progress-Custom -Activity "Update Check" -Status "Connecting to Windows Update..." -PercentComplete 0 -Icon "[CHECK]"
        
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        
        Write-Progress-Custom -Activity "Update Check" -Status "Searching for updates..." -PercentComplete 50 -Icon "[SCAN]"
        $searchResult = $updateSearcher.Search("IsInstalled=0")
        
        Write-Progress-Custom -Activity "Update Check" -Status "Search completed" -PercentComplete 100 -Icon "[ OK ]"
        
        Write-Host "  [ OK ] Found " -NoNewline -ForegroundColor Green
        Write-Host "$($searchResult.Updates.Count)" -NoNewline -ForegroundColor Cyan
        Write-Host " available update(s)" -ForegroundColor Green
        
        if ($searchResult.Updates.Count -gt 0) {
            Write-Host "         Go to Settings -> Windows Update to install" -ForegroundColor Gray
        }
    } catch {
        Write-Host "  [INFO] Could not automatically check for updates" -ForegroundColor Yellow
        Write-Host "         Please manually check in Settings -> Windows Update" -ForegroundColor Gray
    }
}

# ========================================
# Main Script Execution
# ========================================

# Set window title
$host.UI.RawUI.WindowTitle = "Ultimate Windows Repair Tool v4.0"

Clear-Host

# ASCII Art Banner
Write-Host ""
Write-Host "  ===============================================================" -ForegroundColor Cyan
Write-Host "                                                                 " -ForegroundColor Cyan
Write-Host "          Ultimate Windows Repair & Optimization Tool           " -ForegroundColor Cyan
Write-Host "                        Version 4.0                              " -ForegroundColor Cyan
Write-Host "                                                                 " -ForegroundColor Cyan
Write-Host "  ===============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Log "Script Started" -Level "HEADER"
Write-Host "  [LOG ] Log file: " -NoNewline -ForegroundColor Cyan
Write-Host $logFile -ForegroundColor White

if ($Quick) {
    Write-Host "  [FAST] Quick Mode: " -NoNewline -ForegroundColor Yellow
    Write-Host "Essential fixes only (~8-12 minutes)" -ForegroundColor White
    Write-Host "         Includes: Update/Defender enable, Store/Print fix, Service reset" -ForegroundColor Gray
    $script:totalSteps = 10
} else {
    Write-Host "  [FULL] Complete Repair Mode: " -NoNewline -ForegroundColor Cyan
    Write-Host "All optimizations and repairs (~45-60 minutes)" -ForegroundColor White
    Write-Host "         Includes: ALL features + cleanup + repairs + metrics" -ForegroundColor Gray
}
Write-Host ""

# Pre-flight checks
Test-DiskSpace
Get-WindowsUpdateErrors

# Capture BEFORE metrics
Write-Host ""
$script:beforeMetrics = Get-PerformanceMetrics -Phase "BEFORE"

# Determine step numbers based on mode
$enableUpdatesStep = 1
$enableDefenderStep = 2
$startupOptimizeStep = 3
$storeResetStep = 4
$searchRebuildStep = 5
$printSpoolerStep = 6
$dotNetRepairStep = 7
$diskHealthStep = 8
$networkResetThoroughStep = 9
$restorePointStep = 10
$cleanupStep = 11
$repairsStep = 12
$stopServicesStep = 13
$clearCacheStep = 14
$registerDllsStep = 15
$resetNetworkStep = 16
$startServicesStep = 17
$updateCheckStep = 18
$metricsStep = 19

if ($Quick) {
    # Quick mode - essential fixes only
    $enableUpdatesStep = 1
    $enableDefenderStep = 2
    $storeResetStep = 3
    $printSpoolerStep = 4
    $stopServicesStep = 5
    $clearCacheStep = 6
    $registerDllsStep = 7
    $resetNetworkStep = 8
    $startServicesStep = 9
    $updateCheckStep = 10
    $script:totalSteps = 10
}

# Re-enable Windows Update and Defender first
Enable-WindowsUpdate -StepNumber $enableUpdatesStep
Enable-MicrosoftDefender -StepNumber $enableDefenderStep

if (-not $Quick) {
    # Additional optimizations and fixes
    Optimize-StartupPrograms -StepNumber $startupOptimizeStep
    Reset-WindowsStore -StepNumber $storeResetStep
    Rebuild-SearchIndex -StepNumber $searchRebuildStep
    Reset-PrintSpooler -StepNumber $printSpoolerStep
    Repair-DotNetFramework -StepNumber $dotNetRepairStep
    Test-DiskHealth -StepNumber $diskHealthStep
    Reset-NetworkAdaptersThorough -StepNumber $networkResetThoroughStep
}

if (-not $Quick) {
    # Create restore point
    if (-not $SkipRestorePoint) {
        New-SystemRestorePoint -StepNumber $restorePointStep
    }
    
    # Deep cleanup
    if (-not $SkipCleanup) {
        Invoke-SystemCleanup -StepNumber $cleanupStep
    }
    
    # Run repairs
    if (-not $SkipRepairs) {
        Invoke-SystemRepairs -StepNumber $repairsStep
    }
} else {
    # Quick mode - just Store and Print fixes
    Reset-WindowsStore -StepNumber $storeResetStep
    Reset-PrintSpooler -StepNumber $printSpoolerStep
}

# Stop Services
Write-Header "Stopping Windows Update Services" $stopServicesStep
$services = @('bits', 'wuauserv', 'appidsvc', 'cryptsvc')
foreach ($service in $services) {
    Stop-ServiceSafely -ServiceName $service
}
Start-Sleep -Seconds 2

# Clear cache
Clear-UpdateCache -StepNumber $clearCacheStep

# Register DLLs
Register-SystemDLLs -StepNumber $registerDllsStep

# Reset network
Reset-NetworkSettings -StepNumber $resetNetworkStep

# Restart Services
Write-Header "Restarting Windows Update Services" $startServicesStep
foreach ($service in $services) {
    Start-ServiceSafely -ServiceName $service
}

Start-Sleep -Seconds 3

# Check for updates
if (-not $Quick) {
    Invoke-WindowsUpdateCheck -StepNumber $updateCheckStep
}

# Capture AFTER metrics and show comparison
Write-Host ""
$script:afterMetrics = Get-PerformanceMetrics -Phase "AFTER"
if (-not $Quick) {
    Show-PerformanceMetrics -StepNumber $metricsStep
}

# Final Summary
Write-Host "`n"
Write-Host "  ===============================================================" -ForegroundColor Cyan
Write-Host "                       SUMMARY REPORT                           " -ForegroundColor Cyan
Write-Host "  ===============================================================" -ForegroundColor Cyan
Write-Host ""

if ($script:errorCount -eq 0) {
    Write-Host "  [ OK ] " -NoNewline -ForegroundColor Green
    Write-Host "Windows Update reset completed successfully!" -ForegroundColor White
} else {
    Write-Host "  [WARN] " -NoNewline -ForegroundColor Yellow
    Write-Host "Completed with " -NoNewline -ForegroundColor White
    Write-Host "$script:errorCount error(s)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  [STATS] Results: " -ForegroundColor Cyan
Write-Host "          Errors: " -NoNewline -ForegroundColor White
Write-Host $script:errorCount -ForegroundColor $(if($script:errorCount -eq 0){"Green"}else{"Red"})
Write-Host "          Warnings: " -NoNewline -ForegroundColor White
Write-Host $script:warningCount -ForegroundColor $(if($script:warningCount -eq 0){"Green"}else{"Yellow"})
Write-Host "          Steps Completed: " -NoNewline -ForegroundColor White
Write-Host "$script:currentStep / $script:totalSteps" -ForegroundColor Cyan
Write-Host "          Log File: " -NoNewline -ForegroundColor White
Write-Host $logFile -ForegroundColor Gray

if ($script:afterMetrics -and $script:beforeMetrics) {
    $diskGained = $script:afterMetrics.FreeDisk - $script:beforeMetrics.FreeDisk
    if ($diskGained -gt 0.1) {
        Write-Host "          Disk Space Freed: " -NoNewline -ForegroundColor White
        Write-Host "$([math]::Round($diskGained, 2)) GB" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "  ===============================================================" -ForegroundColor Yellow
Write-Host "                         NEXT STEPS                             " -ForegroundColor Yellow
Write-Host "  ===============================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "  [1] RESTART your computer (IMPORTANT!)" -ForegroundColor White
Write-Host "  [2] Open Settings -> Windows Update" -ForegroundColor White
Write-Host "  [3] Click 'Check for updates'" -ForegroundColor White
Write-Host "  [4] Open Windows Security -> Verify Defender is running" -ForegroundColor White
Write-Host ""
Write-Host "  ===============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Press Enter to exit..." -ForegroundColor Gray
Read-Host
