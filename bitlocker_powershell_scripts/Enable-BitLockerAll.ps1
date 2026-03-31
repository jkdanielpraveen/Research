# Enable-BitLockerAll.ps1
# Encrypts OS drive + all fixed data drives, backs up recovery keys to AD
# Deploy via GPO Scheduled Task running as SYSTEM

$ErrorActionPreference = "SilentlyContinue"
$LogFile = "C:\Windows\Logs\BitLockerDeploy.log"

function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $LogFile -Append
}

function Backup-KeyToAD {
    param($MountPoint)
    $vol = Get-BitLockerVolume -MountPoint $MountPoint -ErrorAction SilentlyContinue
    if ($null -eq $vol) { return }
    foreach ($kp in $vol.KeyProtector) {
        if ($kp.KeyProtectorType -eq 'RecoveryPassword') {
            Backup-BitLockerKeyProtector -MountPoint $MountPoint -KeyProtectorId $kp.KeyProtectorId -ErrorAction SilentlyContinue
            Write-Log "Recovery key backed up to AD for $MountPoint (KeyID: $($kp.KeyProtectorId))"
        }
    }
}

function Enable-DriveEncryption {
    param($MountPoint)

    $vol = Get-BitLockerVolume -MountPoint $MountPoint -ErrorAction SilentlyContinue
    if ($null -eq $vol) {
        Write-Log "Skipping $MountPoint - not a BitLocker-capable volume."
        return
    }

    if ($vol.ProtectionStatus -eq 'On') {
        Write-Log "$MountPoint is already encrypted. Ensuring key is backed up to AD."
        Backup-KeyToAD -MountPoint $MountPoint
        return
    }

    # Add recovery password protector if not already present
    $hasRecovery = $vol.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }
    if (-not $hasRecovery) {
        Add-BitLockerKeyProtector -MountPoint $MountPoint -RecoveryPasswordProtector | Out-Null
        Write-Log "Recovery password protector added to $MountPoint"
    }

    Enable-BitLocker -MountPoint $MountPoint -EncryptionMethod XtsAes256 -SkipHardwareTest -RecoveryPasswordProtector | Out-Null
    Write-Log "$MountPoint encryption started (XTS-AES 256)."
    Backup-KeyToAD -MountPoint $MountPoint
}

# -------------------------------------------------------
# OS Drive
# -------------------------------------------------------
$osDrive = $env:SystemDrive
Write-Log "=== BitLocker Deployment Started ==="
Write-Log "OS Drive: $osDrive"

$osVol = Get-BitLockerVolume -MountPoint $osDrive -ErrorAction SilentlyContinue

if ($osVol -and $osVol.ProtectionStatus -ne 'On') {
    # TPM protector for OS drive (no PIN = silent unlock at boot)
    Enable-BitLocker -MountPoint $osDrive -TpmProtector -EncryptionMethod XtsAes256 -SkipHardwareTest | Out-Null
    Add-BitLockerKeyProtector -MountPoint $osDrive -RecoveryPasswordProtector | Out-Null
    Write-Log "OS drive $osDrive encryption started with TPM + RecoveryPassword."
    Backup-KeyToAD -MountPoint $osDrive
} else {
    Write-Log "OS drive $osDrive already encrypted. Verifying AD key backup."
    Backup-KeyToAD -MountPoint $osDrive
}

# -------------------------------------------------------
# All Fixed Data Drives (all partitions with drive letters)
# -------------------------------------------------------
$fixedDrives = Get-BitLockerVolume | Where-Object {
    $_.VolumeType -eq 'Data' -and $_.MountPoint -ne ''
}

if ($fixedDrives) {
    foreach ($drive in $fixedDrives) {
        Write-Log "Processing fixed data drive: $($drive.MountPoint)"
        Enable-DriveEncryption -MountPoint $drive.MountPoint

        # Auto-unlock: data drives unlock automatically when OS drive is unlocked
        Enable-BitLockerAutoUnlock -MountPoint $drive.MountPoint -ErrorAction SilentlyContinue
        Write-Log "Auto-unlock enabled for $($drive.MountPoint)"
    }
} else {
    Write-Log "No additional fixed data drives found."
}

Write-Log "=== BitLocker Deployment Complete ==="
