# ============================================================
# PERSISTENT VAULT - COMPLETE WINDOWS SCRIPT
# Run as Administrator
# ============================================================

$ErrorActionPreference = "Stop"

# ============================================================
# CONFIGURATION
# ============================================================

$Label = "PERSISTENT_VAULT"
$DriveLetter = "B"
$SizeMB = 256

# Direct GitHub raw / release download URL for bonjour.exe:
$DownloadUrl = "https://github.com/19092023700/black-screen/releases/latest/download/bonjour.exe"
$ExeName = "bonjour.exe"

# ============================================================
# ADMINISTRATOR CHECK
# ============================================================

$principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)

if (!$principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    Write-Host "Run PowerShell as Administrator." -ForegroundColor Red
    return
}

# ============================================================
# GET VAULT PARTITION & DRIVE LETTER HELPERS
# ============================================================

function Get-VaultPartitionInternal {

    $volume = Get-Volume -FileSystemLabel $Label -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if (!$volume) {
        return $null
    }

    return Get-Partition -Volume $volume
}

function Get-ActiveDriveLetter($partition) {
    if ($partition -and $partition.DriveLetter -and ([int][char]$partition.DriveLetter -ne 0)) {
        $ch = "$($partition.DriveLetter)".Trim()
        if ($ch -match '^[A-Za-z]$') {
            return $ch
        }
    }
    return $null
}

# Remove any Get-Vault function in current session so PowerShell's Get-* auto-prefixing
# never intercepts the 'vault' command.
if (Test-Path Function:\Get-Vault) {
    Remove-Item Function:\Get-Vault -Force -ErrorAction SilentlyContinue
}

# ============================================================
# MOUNT VAULT
# ============================================================

function Mount-Vault {

    $partition = Get-VaultPartitionInternal

    if (!$partition) {
        Write-Host "Vault not found." -ForegroundColor Red
        return
    }

    $currentLetter = Get-ActiveDriveLetter $partition

    if ($currentLetter -eq $DriveLetter) {
        Write-Host "Vault already mounted at $DriveLetter`:\" -ForegroundColor Green
        return
    }

    if ($currentLetter) {
        Write-Host "Vault is already mounted as $currentLetter`:"
        return
    }

    if (Get-Volume -DriveLetter $DriveLetter -ErrorAction SilentlyContinue) {
        Write-Host "Drive $DriveLetter`: is already occupied." -ForegroundColor Red
        return
    }

    Add-PartitionAccessPath `
        -DiskNumber $partition.DiskNumber `
        -PartitionNumber $partition.PartitionNumber `
        -AccessPath "$DriveLetter`:\"

    Write-Host "Vault mounted successfully at $DriveLetter`:\" -ForegroundColor Green
}

# ============================================================
# HIDE VAULT
# ============================================================

function Hide-Vault {

    $partition = Get-VaultPartitionInternal

    if (!$partition) {
        Write-Host "Vault not found." -ForegroundColor Red
        return
    }

    $currentLetter = Get-ActiveDriveLetter $partition

    if (!$currentLetter) {
        Write-Host "Vault is already hidden." -ForegroundColor Yellow
        return
    }

    Remove-PartitionAccessPath `
        -DiskNumber $partition.DiskNumber `
        -PartitionNumber $partition.PartitionNumber `
        -AccessPath "$currentLetter`:\"

    Write-Host "Vault hidden successfully." -ForegroundColor Green
}

# ============================================================
# VAULT STATUS
# ============================================================

function Show-VaultStatus {

    $partition = Get-VaultPartitionInternal

    if (!$partition) {
        Write-Host "Vault does not exist." -ForegroundColor Red
        return
    }

    $currentLetter = Get-ActiveDriveLetter $partition

    if ($currentLetter) {
        Write-Host "Vault mounted: $currentLetter`:" -ForegroundColor Green
    }
    else {
        Write-Host "Vault exists and is hidden." -ForegroundColor Yellow
    }
}

# ============================================================
# CREATE PARTITION
# ============================================================

function Create-VaultPartition {

    Write-Host ""
    Write-Host "Checking existing vault..."

    $existing = Get-VaultPartitionInternal

    if ($existing) {
        Write-Host "Existing vault partition detected!" -ForegroundColor Green
        Write-Host "Reusing existing partition."
        return
    }

    $c = Get-Partition -DriveLetter C
    $d = Get-Partition -DriveLetter D

    $disk = Get-Disk -Number $d.DiskNumber

    $size = [UInt64]($SizeMB * 1MB)

    if ($disk.PartitionStyle -ne "GPT") {
        throw "D: physical disk must use GPT."
    }

    if ($disk.IsOffline -or $disk.IsReadOnly) {
        throw "Target disk is offline or read-only."
    }

    Write-Host ""
    Write-Host "===================================="
    Write-Host "DISK CONFIGURATION"
    Write-Host "===================================="

    Write-Host "C: Physical disk: $($c.DiskNumber)"
    Write-Host "D: Physical disk: $($d.DiskNumber)"

    if ($c.DiskNumber -eq $d.DiskNumber) {

        Write-Host ""
        Write-Host "C: and D: are on the SAME physical disk." -ForegroundColor Cyan
        Write-Host "Using D: shrinking approach."

        $supported = Get-PartitionSupportedSize -DriveLetter D

        if (($d.Size - $size) -lt $supported.SizeMin) {
            throw "D: cannot be shrunk by $SizeMB MB."
        }

        $confirmation = Read-Host "Shrink D: by $SizeMB MB and create vault? Type CREATE"

        if ($confirmation -ne "CREATE") {
            throw "Operation cancelled."
        }

        Resize-Partition `
            -DriveLetter D `
            -Size ($d.Size - $size)

        Write-Host "D: successfully shrunk."

        $partition = New-Partition `
            -DiskNumber $disk.Number `
            -Size $size
    }
    else {

        Write-Host ""
        Write-Host "C: and D: are on DIFFERENT physical disks." -ForegroundColor Cyan
        Write-Host "Using D:'s physical disk."

        $disk = Get-Disk -Number $d.DiskNumber

        if ($disk.LargestFreeExtent -ge $size) {

            Write-Host "Sufficient unallocated space found."

            $partition = New-Partition `
                -DiskNumber $disk.Number `
                -Size $size
        }
        else {

            Write-Host "Not enough unallocated space."
            Write-Host "Attempting to shrink D: instead."

            $supported = Get-PartitionSupportedSize -DriveLetter D

            if (($d.Size - $size) -lt $supported.SizeMin) {
                throw "D: cannot be shrunk by $SizeMB MB."
            }

            $confirmation = Read-Host "Shrink D: by $SizeMB MB and create vault? Type CREATE"

            if ($confirmation -ne "CREATE") {
                throw "Operation cancelled."
            }

            Resize-Partition `
                -DriveLetter D `
                -Size ($d.Size - $size)

            Write-Host "D: successfully shrunk."

            $partition = New-Partition `
                -DiskNumber $disk.Number `
                -Size $size
        }
    }

    Write-Host ""
    Write-Host "Formatting partition as NTFS..."

    Format-Volume `
        -Partition $partition `
        -FileSystem NTFS `
        -NewFileSystemLabel $Label `
        -Confirm:$false |
        Out-Null

    Write-Host "Partition formatted successfully." -ForegroundColor Green
}

# ============================================================
# DOWNLOAD & HIDE BONJOUR.EXE IN VAULT
# ============================================================

function Install-BonjourExecutable {

    Write-Host ""
    Write-Host "Preparing $ExeName inside vault..."

    $partition = Get-VaultPartitionInternal

    if (!$partition) {
        throw "Vault partition not found."
    }

    $currentLetter = Get-ActiveDriveLetter $partition

    if (!$currentLetter) {

        if (Get-Volume -DriveLetter $DriveLetter -ErrorAction SilentlyContinue) {
            throw "Drive $DriveLetter`: is occupied. Free $DriveLetter`: before continuing."
        }

        Add-PartitionAccessPath `
            -DiskNumber $partition.DiskNumber `
            -PartitionNumber $partition.PartitionNumber `
            -AccessPath "$DriveLetter`:\"
    }

    $partition = Get-VaultPartitionInternal
    $currentLetter = Get-ActiveDriveLetter $partition

    if ($currentLetter -ne $DriveLetter) {
        throw "Vault is mounted under another drive letter ($currentLetter`:)."
    }

    $targetPath = "$DriveLetter`:\$ExeName"

    # If a hidden file already exists at B:\bonjour.exe, clear attributes before overwriting
    if (Test-Path -LiteralPath $targetPath) {
        $existingItem = Get-Item -LiteralPath $targetPath -Force
        $existingItem.Attributes = [System.IO.FileAttributes]::Normal
        Remove-Item -LiteralPath $targetPath -Force
    }

    $baseDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $localFallback = Join-Path $baseDir $ExeName

    if ($DownloadUrl -notmatch "YOUR_USERNAME" -and $DownloadUrl -match "^https?://") {
        Write-Host "Downloading $ExeName from GitHub..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest `
            -Uri $DownloadUrl `
            -OutFile $targetPath `
            -UseBasicParsing
        Write-Host "Downloaded to $targetPath" -ForegroundColor Green
    }
    elseif (Test-Path -LiteralPath $localFallback) {
        Write-Host "Copying local $ExeName to $targetPath..." -ForegroundColor Yellow
        Copy-Item -LiteralPath $localFallback -Destination $targetPath -Force
        Write-Host "Copied to $targetPath" -ForegroundColor Green
    }
    else {
        throw "Set `$DownloadUrl in script.ps1 to your GitHub raw/release link (or place $ExeName next to script.ps1)."
    }

    $fileItem = Get-Item -LiteralPath $targetPath -Force
    $fileItem.Attributes = [System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::System

    Write-Host "$ExeName is hidden at $targetPath (launch via CMD/PowerShell: $DriveLetter`:/$ExeName)" -ForegroundColor Green
}

# ============================================================
# INSTALL CMD COMMANDS
# ============================================================

function Install-VaultCommand {

    $commandPath = "$env:ProgramData\vault.ps1"
    $launcherPath = "$env:SystemRoot\vault.cmd"

    $vaultScript = @'
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("mount","hide","status","run")]
    [string]$Action
)

$label = "PERSISTENT_VAULT"
$letter = "B"

function Get-ActiveLetter($p) {
    if ($p -and $p.DriveLetter -and ([int][char]$p.DriveLetter -ne 0)) {
        $ch = "$($p.DriveLetter)".Trim()
        if ($ch -match '^[A-Za-z]$') {
            return $ch
        }
    }
    return $null
}

$volume = Get-Volume -FileSystemLabel $label -ErrorAction SilentlyContinue |
    Select-Object -First 1

if (!$volume) {
    Write-Host "Vault not found."
    exit 1
}

$partition = Get-Partition -Volume $volume
$currentLetter = Get-ActiveLetter $partition

switch ($Action) {

    "mount" {

        if ($currentLetter -eq $letter) {
            Write-Host "Already mounted at $letter`:\"
        }

        elseif ($currentLetter) {
            Write-Host "Already mounted as $currentLetter`:"
        }

        elseif (Get-Volume -DriveLetter $letter -ErrorAction SilentlyContinue) {
            Write-Host "Drive $letter`: is occupied."
            exit 1
        }

        else {

            Add-PartitionAccessPath `
                -DiskNumber $partition.DiskNumber `
                -PartitionNumber $partition.PartitionNumber `
                -AccessPath "$letter`:\"

            Write-Host "Vault mounted at $letter`:\"
        }
    }

    "run" {

        if (!$currentLetter) {
            Add-PartitionAccessPath `
                -DiskNumber $partition.DiskNumber `
                -PartitionNumber $partition.PartitionNumber `
                -AccessPath "$letter`:\"
            $currentLetter = $letter
        }
        Start-Process "$currentLetter`:\bonjour.exe"
        Write-Host "Launched $currentLetter`:\bonjour.exe (type 789 to open black screen, 101 to unhide)"
    }

    "hide" {

        if ($currentLetter) {

            Remove-PartitionAccessPath `
                -DiskNumber $partition.DiskNumber `
                -PartitionNumber $partition.PartitionNumber `
                -AccessPath "$currentLetter`:\"

            Write-Host "Vault hidden."
        }

        else {
            Write-Host "Vault is already hidden."
        }
    }

    "status" {

        if ($currentLetter) {
            Write-Host "Mounted: $currentLetter`:"
        }

        else {
            Write-Host "Vault exists and is hidden."
        }
    }
}
'@

    Set-Content `
        -Path $commandPath `
        -Value $vaultScript `
        -Encoding UTF8

    $launcher = @"
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$commandPath" %1
"@

    # Place vault.cmd directly in C:\Windows (already in PATH for all sessions!)
    Set-Content `
        -Path $launcherPath `
        -Value $launcher `
        -Encoding ASCII

    # Also write to C:\ProgramData\vault.cmd for backwards compatibility
    Set-Content `
        -Path "$env:ProgramData\vault.cmd" `
        -Value $launcher `
        -Encoding ASCII

    # Also save vault.ps1 and vault.cmd inside the B:\ vault partition itself
    # so they survive when Shadow Defender resets C: and D: on reboot!
    if (Test-Path "$DriveLetter`:\") {
        $vaultPs1Backup = "$DriveLetter`:\vault.ps1"
        $vaultCmdBackup = "$DriveLetter`:\vault.cmd"
        foreach ($bp in @($vaultPs1Backup, $vaultCmdBackup)) {
            if (Test-Path -LiteralPath $bp) {
                (Get-Item -LiteralPath $bp -Force).Attributes = [System.IO.FileAttributes]::Normal
            }
        }
        Set-Content -Path $vaultPs1Backup -Value $vaultScript -Encoding UTF8
        $bLauncher = @"
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0vault.ps1" %1
"@
        Set-Content -Path $vaultCmdBackup -Value $bLauncher -Encoding ASCII
        foreach ($bp in @($vaultPs1Backup, $vaultCmdBackup)) {
            (Get-Item -LiteralPath $bp -Force).Attributes = [System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::System
        }
    }

    Write-Host "CMD commands installed." -ForegroundColor Green
}

# ============================================================
# MAIN EXECUTION
# ============================================================

try {

    Write-Host ""
    Write-Host "============================================"
    Write-Host "       PERSISTENT VAULT INSTALLER"
    Write-Host "============================================"

    Create-VaultPartition

    Install-BonjourExecutable

    Install-VaultCommand

    Hide-Vault

    Write-Host ""
    Write-Host "============================================"
    Write-Host "       VAULT SETUP COMPLETED"
    Write-Host "============================================"

    Write-Host "Partition: $Label"
    Write-Host "Size: $SizeMB MB"
    Write-Host "Filesystem: NTFS"
    Write-Host "Executable: $DriveLetter`:\$ExeName (Hidden)"
    Write-Host "Drive letter: Removed"
    Write-Host ""
    Write-Host "Available commands:"
    Write-Host ""
    Write-Host "vault mount"
    Write-Host "$DriveLetter`:/$ExeName"
    Write-Host "vault run"
    Write-Host "vault hide"
    Write-Host "vault status"

    Write-Host "============================================"

}

catch {

    Write-Host ""
    Write-Host "SETUP ERROR:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red

    Write-Host ""
    Write-Host "Your existing partition has NOT been intentionally deleted."
}
