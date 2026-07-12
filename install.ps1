param(
    [switch]$install,
    [switch]$repair,
    [switch]$uninstall,
    [switch]$openasar,
    [switch]$install_openasar,
    [switch]$uninstall_openasar,
    [switch]$setup_autorun,
    [switch]$disable_autorun,
    [switch]$interactive,
    
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$custom_args
)

$ErrorActionPreference = "Stop"

$ScriptVersion = "0.0.1"
$MyRepo = "Tahgolov/Vencordify"
$OnlineScriptUrl = "https://raw.githubusercontent.com/$MyRepo/main/install.ps1"

$TaskName = "VencordifyAutoUpdate"

function Show-Help {
    Write-Host ""
    $Logo = @'
                                    _ _  __       
 /\   /\___ _ __   ___ ___  _ __ __| (_)/ _|_   _ 
 \ \ / / _ \ '_ \ / __/ _ \| '__/ _` | | |_| | | |
  \ V /  __/ | | | (_| (_) | | | (_| | |  _| |_| |
   \_/ \___|_| |_|\___\___/|_|  \__,_|_|_|  \__, |
                                            |___/ 
'@
    Write-Host $Logo -ForegroundColor Cyan
    Write-Host ""

    Write-Host " [ Version ]           v$ScriptVersion" -ForegroundColor Green
    Write-Host " [ Homepage ]          https://github.com/$MyRepo" -ForegroundColor DarkCyan
    Write-Host " [ Vencord homepage ]  https://vencord.dev" -ForegroundColor DarkCyan
    Write-Host " [ OpenAsar homepage ] https://openasar.dev" -ForegroundColor DarkCyan
    Write-Host " ----------------------------------------------------------------------" -ForegroundColor Gray

    Write-Host ""
    Write-Host "Description:"
    Write-Host "  Utility for Vencord/OpenAsar to customize, automize installation with autorun support."
    Write-Host "  Vencord: By default, it passes '-branch auto' in the install/uninstall scenarios."
    Write-Host "  OpenAsar: WIP"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  powershell -ExecutionPolicy Bypass -File .\install.ps1 [flags]"
    Write-Host ""
    Write-Host "Wrapper Flags:"
    Write-Host "  ?                    Show this message"
    Write-Host "  -install             Patch Discord with Vencord"
    Write-Host "  -repair              Recoper vencord"
    Write-Host "  -uninstall           Remove Vencord modifications from Discord"
    Write-Host "  -openasar            Dynamically install/uninstall OpenAsar based on context"
    Write-Host "  -install_openasar    Explicitly install OpenAsar independently"
    Write-Host "  -uninstall_openasar  Explicitly uninstall OpenAsar independently"
    Write-Host "  -setup_autorun       Register a silent background update task on Windows logon"
    Write-Host "  -disable_autorun     Remove the background update task from Task Scheduler"
    Write-Host "  -interactive         Bypass automation and run official Vencord GUI menu"
    Write-Host ""
    Write-Host "Passthrough Custom Flags:"
    Write-Host "  Any other flags (ex. -debug, -help) will be passed to Vencord CLI."
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\install.ps1 -install -openasar"
    Write-Host "  .\install.ps1 -uninstall -openasar"
    Write-Host "  .\install.ps1 -setup_autorun"
    Write-Host ""
}

$isHelpTriggered = $args -contains "-?" -or $args -contains "?" -or $args -contains "-h" -or $args -contains "-help" -or $args -contains "--help" -or $custom_args -contains "?"
$hasWorkerAction = $install -or $repair -or $uninstall -or $openasar -or $install_openasar -or $uninstall_openasar -or $interactive

if ($isHelpTriggered -and -not $hasWorkerAction) {
    Show-Help
    return
}

function Manage-ScheduledTask {
    $taskExists = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    $isAutomationOnly = -not ($install -or $uninstall -or $repair -or $openasar -or $install_openasar -or $uninstall_openasar)

    if ($disable_autorun) {
        if ($taskExists) {
            Write-Host "[-] Removing autorun task from Task Scheduler..." -ForegroundColor Yellow
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
            Write-Host "[+] Autorun successfully disabled." -ForegroundColor Green
        } else {
            Write-Host "[!] Autorun task not found." -ForegroundColor Gray
        }
        if ($isAutomationOnly) { exit 0 }
    }

    if ($setup_autorun) {
        if ($taskExists) {
            $StatusMessage = "[!] Autorun task already exists. Overwriting settings..."
        } else {
            $StatusMessage = "[*] Creating new autorun task in Task Scheduler..."
        }
        Write-Host $StatusMessage -ForegroundColor Cyan
        
        $PassthroughList = @()
        if ($install) { $PassthroughList += "--install" }
        if ($repair) { $PassthroughList += "--repair" }
        if ($openasar) { $PassthroughList += "--openasar" }
        if ($install_openasar) { $PassthroughList += "--install-openasar" }
        $PassthroughArgs = $PassthroughList -join ' '
        
        $ActionCmd = "PowerShell.exe"
        $CleanedArgs = $PassthroughArgs.Trim()
        if ([string]::IsNullOrEmpty($CleanedArgs)) {
            $FormattedArgs = ""
        } else {
            $FormattedArgs = " $CleanedArgs"
        }
        $ActionArgs = "-NoProfile -WindowStyle Hidden -Command `"[ScriptBlock]::Create((irm '$OnlineScriptUrl')) --install$FormattedArgs`""
        
        $Action = New-ScheduledTaskAction -Execute $ActionCmd -Argument $ActionArgs
        $Trigger = New-ScheduledTaskTrigger -AtLogOn
        $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        
        Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Description "Silent network updates for Vencord on logon via Vencordify" -Force
        Write-Host "[+] Autorun task configured successfully!" -ForegroundColor Green
        if ($isAutomationOnly) { exit 0 }
    }
}

function Get-GitHubRelease {
    $repo = "Vencord/installer"
    $apiReleaseUrl = "https://api.github.com/repos/$repo/releases/latest"
    $headers = @{ 'User-Agent'="vencord-install/1.0" }
    
    try {
        return Invoke-RestMethod -Uri $apiReleaseUrl -Headers $headers
    } catch {
        Write-Error "Failed to fetch release info from GitHub API: $_"
        exit 2    
    }
}

function Stop-Discord {
    $discordProcesses = Get-Process -Name Discord -ErrorAction SilentlyContinue
    if ($discordProcesses) {
        Write-Host "[*] Terminating Discord processes..." -ForegroundColor Yellow
        Stop-Process -Name Discord -Force -ErrorAction SilentlyContinue
        $discordProcesses | Wait-Process -Timeout 5 -ErrorAction SilentlyContinue
    }
}

function Resolve-Arguments {
    $finalArgs = @()
    
    $passthroughFlags = @()
    $isInteractiveTriggered = $interactive

    if ($custom_args) {
        foreach ($arg in $custom_args) {
            if ($arg -eq "-interactive" -or $arg -eq "--interactive") {
                $isInteractiveTriggered = $true
                continue
            }

            if (-not $arg.StartsWith("-")) {
                $passthroughFlags += "-$arg"
            } else {
                $passthroughFlags += $arg
            }
        }
    }

    if ($isInteractiveTriggered) {
        Write-Host "[*] Running in interactive mode with stripped flags..." -ForegroundColor Gray
        if ($passthroughFlags) { $finalArgs += $passthroughFlags }
        return $finalArgs
    }
    
    if ($PSBoundParameters.Count -eq 0 -and $passthroughFlags.Count -gt 0) {
        return $passthroughFlags
    }

    if ($PSBoundParameters.Count -eq 0) {
        Write-Host "[*] Running in interactive mode..." -ForegroundColor Gray
        return $finalArgs
    }
    if ($interactive) {
        Write-Host "[*] Running in interactive mode with stripped flags..." -ForegroundColor Gray
        if ($passthroughFlags) { $finalArgs += $passthroughFlags }
        return $finalArgs
    }
    
    $hasWorkerFlag = $false
    $isUninstallContext = $uninstall -or $uninstall_openasar

    if ($install) { $finalArgs += "-install"; $hasWorkerFlag = $true }
    if ($repair) { $finalArgs += "-repair"; $hasWorkerFlag = $true }
    if ($uninstall) { $finalArgs += "-uninstall"; $hasWorkerFlag = $true }
    if ($install_openasar) { $finalArgs += "-install-openasar"; $hasWorkerFlag = $true }
    if ($uninstall_openasar) { $finalArgs += "-uninstall-openasar"; $hasWorkerFlag = $true }
    
    if ($openasar -and -not ($install_openasar -or $uninstall_openasar)) {
        if ($isUninstallContext) {
            $finalArgs += "-uninstall-openasar"
        } else {
            $finalArgs += "-install-openasar"
        }
        $hasWorkerFlag = $true
    }

    if ($passthroughFlags) {
        $finalArgs += $passthroughFlags
        $hasWorkerFlag = $true
    }

    if ($hasWorkerFlag -and -not ($finalArgs -contains "-help" -or $finalArgs -contains "-h")) {
        $finalArgs += @("-branch", "auto")
    }

    if ($finalArgs.Count -gt 0) {
        Write-Host "[*] Executing Vencord CLI flags: $finalArgs" -ForegroundColor Magenta
    }
    
    return $finalArgs
}

function Start-DiscordInstance {
    $isEligibleAction = $install -or $repair -or $install_openasar -or ($openasar -and -not $uninstall)

    if ($isEligibleAction -and -not $setup_autorun) {
        $DiscordUpdateExe = Join-Path $env:LOCALAPPDATA "Discord\Update.exe"
        if (Test-Path $DiscordUpdateExe) {
            Write-Host "[*] Restarting Discord..." -ForegroundColor Green
            Start-Process -FilePath $DiscordUpdateExe -ArgumentList "--processStart", "Discord.exe"
        }
    }
}

Manage-ScheduledTask

$release = Get-GitHubRelease

$cliAssetName = "VencordInstallerCli.exe"
$cliAsset = $release.assets | Where-Object { $_.name -ieq $cliAssetName }
if (-not $cliAsset) {
    Write-Error "Release asset $cliAssetName not found."
    exit 3
}

$InstallPath = Join-Path $env:TEMP $cliAssetName
if (Test-Path $InstallPath) { Remove-Item -Force -ErrorAction SilentlyContinue $InstallPath }

Write-Host "[*] Downloading $($cliAsset.name)..." -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri $cliAsset.browser_download_url -OutFile $InstallPath
} catch {
    Write-Error "Download failed: $_"
    exit 4
}

Stop-Discord

$finalArgs = Resolve-Arguments

try {
    if ($finalArgs.Count -gt 0) {
        Start-Process -Wait -NoNewWindow -FilePath $InstallPath -ArgumentList $finalArgs
    } else {
        Start-Process -Wait -NoNewWindow -FilePath $InstallPath
    }
    
    Write-Host "[+] Execution completed successfully!" -ForegroundColor Green
} catch {
    Write-Error "Installer execution failed: $_"
    exit 5
} finally {
    if (Test-Path $InstallPath) { Remove-Item -Force -ErrorAction SilentlyContinue $InstallPath }
}

Start-DiscordInstance