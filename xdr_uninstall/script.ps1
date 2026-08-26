# Cortex XDR 9.1.0.20483 - Automated Uninstallation
# WARNING: This file contains the supervisor/uninstall password in plain text.

$CyTool = "C:\Program Files\Palo Alto Networks\Traps\cytool.exe"
$ProductCode = "{1845C05B-F952-4770-A995-FD8BA5C6EF0A}"
$SupervisorPassword = "Password1"
$UninstallPassword = "Password1"
$LogFile = "C:\CortexUninstall.log"

Write-Host "=== Cortex XDR Automated Uninstallation ==="

$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $IsAdmin) {
    Write-Host "ERROR: Run this script as Administrator."
    exit 1
}

if (-not (Test-Path $CyTool)) {
    Write-Host "ERROR: cytool.exe not found: $CyTool"
    exit 1
}

Write-Host "Disabling Anti-Tampering..."

# Supply the supervisor password through standard input so Cytool does not prompt.
$cmdLine = 'echo ' + $SupervisorPassword + '|' + '"' + $CyTool + '" protect disable'
$ProtectProcess = Start-Process -FilePath "cmd.exe" `
    -ArgumentList "/c `"$cmdLine`"" `
    -Wait -PassThru -NoNewWindow

if ($ProtectProcess.ExitCode -ne 0) {
    Write-Host "ERROR: Failed to disable Anti-Tampering. Exit code: $($ProtectProcess.ExitCode)"
    exit 1
}

Write-Host "Anti-Tampering command completed."
Write-Host "Starting Cortex XDR uninstall..."

$Arguments = "/x $ProductCode /qn /norestart UNINSTALL_PASSWORD=$UninstallPassword /L*v `"$LogFile`""
$UninstallProcess = Start-Process -FilePath "msiexec.exe" `
    -ArgumentList $Arguments `
    -Wait -PassThru

Write-Host "MSI Exit Code: $($UninstallProcess.ExitCode)"

if ($UninstallProcess.ExitCode -eq 0 -or $UninstallProcess.ExitCode -eq 3010) {
    Write-Host "SUCCESS: Cortex XDR uninstalled."
    if ($UninstallProcess.ExitCode -eq 3010) {
        Write-Host "A restart is required."
    }
    Write-Host "Log: $LogFile"
    exit 0
}
 