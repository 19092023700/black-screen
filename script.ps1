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
# GET VAULT PARTITION
# ============================================================

function Get-Vault {

    $volume = Get-Volume -FileSystemLabel $Label -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if (!$volume) {
        return $null
    }

    return Get-Partition -Volume $volume
}

# ============================================================
# MOUNT VAULT
# ============================================================

function Mount-Vault {

    $partition = Get-Vault

    if (!$partition) {
        Write-Host "Vault not found." -ForegroundColor Red
        return
    }

    if ($partition.DriveLetter -eq $DriveLetter) {
        Write-Host "Vault already mounted at $DriveLetter`:\" -ForegroundColor Green
        return
    }

    if ($partition.DriveLetter) {
        Write-Host "Vault is already mounted as $($partition.DriveLetter):"
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

    $partition = Get-Vault

    if (!$partition) {
        Write-Host "Vault not found." -ForegroundColor Red
        return
    }

    if (!$partition.DriveLetter) {
        Write-Host "Vault is already hidden." -ForegroundColor Yellow
        return
    }

    $letter = $partition.DriveLetter

    Remove-PartitionAccessPath `
        -DiskNumber $partition.DiskNumber `
        -PartitionNumber $partition.PartitionNumber `
        -AccessPath "$letter`:\"

    Write-Host "Vault hidden successfully." -ForegroundColor Green
}

# ============================================================
# VAULT STATUS
# ============================================================

function Show-VaultStatus {

    $partition = Get-Vault

    if (!$partition) {
        Write-Host "Vault does not exist." -ForegroundColor Red
        return
    }

    if ($partition.DriveLetter) {
        Write-Host "Vault mounted: $($partition.DriveLetter):" -ForegroundColor Green
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

    # Reuse existing partition if setup was previously interrupted.

    $existing = Get-Vault

    if ($existing) {
        Write-Host "Existing vault partition detected!" -ForegroundColor Green
        Write-Host "Reusing existing partition."
        return
    }

    # Get C: and D:

    $c = Get-Partition -DriveLetter C
    $d = Get-Partition -DriveLetter D

    $disk = Get-Disk -Number $d.DiskNumber

    $size = [UInt64]($SizeMB * 1MB)

    # GPT validation

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

    # --------------------------------------------------------
    # CASE 1: SAME PHYSICAL DISK
    # --------------------------------------------------------

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

    # --------------------------------------------------------
    # CASE 2: DIFFERENT PHYSICAL DISKS
    # --------------------------------------------------------

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

    # --------------------------------------------------------
    # FORMAT PARTITION
    # --------------------------------------------------------

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

    $partition = Get-Vault

    if (!$partition) {
        throw "Vault partition not found."
    }

    # Ensure E: is mounted.

    if (!$partition.DriveLetter) {

        if (Get-Volume -DriveLetter $DriveLetter -ErrorAction SilentlyContinue) {
            throw "Drive $DriveLetter`: is occupied. Free $DriveLetter`: before continuing."
        }

        Add-PartitionAccessPath `
            -DiskNumber $partition.DiskNumber `
            -PartitionNumber $partition.PartitionNumber `
            -AccessPath "$DriveLetter`:\"
    }

    $partition = Get-Vault

    if ($partition.DriveLetter -ne $DriveLetter) {
        throw "Vault is mounted under another drive letter ($($partition.DriveLetter):)."
    }

    $targetPath = "$DriveLetter`:\$ExeName"

    # If a hidden file already exists at B:\bonjour.exe, clear attributes before overwriting
    if (Test-Path -LiteralPath $targetPath) {
        $existingItem = Get-Item -LiteralPath $targetPath -Force
        $existingItem.Attributes = [System.IO.FileAttributes]::Normal
        Remove-Item -LiteralPath $targetPath -Force
    }

    # Download from GitHub URL (or copy local bonjour.exe if URL is placeholder)
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
        Write-Host "DownloadUrl is still placeholder; copying local $ExeName to $targetPath..." -ForegroundColor Yellow
        Copy-Item -LiteralPath $localFallback -Destination $targetPath -Force
        Write-Host "Copied to $targetPath" -ForegroundColor Green
    }
    else {
        throw "Set `$DownloadUrl in script.ps1 to your GitHub raw/release link (or place $ExeName next to script.ps1)."
    }

    # Mark E:\bonjour.exe as Hidden (and System) so it is invisible in Explorer,
    # but still directly runnable via CMD / PowerShell as E:\bonjour.exe or E:/bonjour.exe
    $fileItem = Get-Item -LiteralPath $targetPath -Force
    $fileItem.Attributes = [System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::System

    Write-Host "$ExeName is hidden at $targetPath (launch via CMD/PowerShell: $DriveLetter`:/$ExeName)" -ForegroundColor Green
}

# ============================================================
# INSTALL CMD COMMANDS
# ============================================================

function Install-VaultCommand {

    $commandPath = "$env:ProgramData\vault.ps1"
    $launcherPath = "$env:ProgramData\vault.cmd"

    $vaultScript = @'
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("mount","hide","status","run")]
    [string]$Action
)

$label = "PERSISTENT_VAULT"
$letter = "B"

$volume = Get-Volume -FileSystemLabel $label -ErrorAction SilentlyContinue |
    Select-Object -First 1

if (!$volume) {
    Write-Host "Vault not found."
    exit 1
}

$partition = Get-Partition -Volume $volume

switch ($Action) {

    "mount" {

        if ($partition.DriveLetter -eq $letter) {
            Write-Host "Already mounted at $letter`:\"
        }

        elseif ($partition.DriveLetter) {
            Write-Host "Already mounted as $($partition.DriveLetter):"
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

        if (!$partition.DriveLetter) {
            Add-PartitionAccessPath `
                -DiskNumber $partition.DiskNumber `
                -PartitionNumber $partition.PartitionNumber `
                -AccessPath "$letter`:\"
        }
        $activeLetter = if ($partition.DriveLetter) { $partition.DriveLetter } else { $letter }
        Start-Process "$activeLetter`:\bonjour.exe"
    }

    "hide" {

        if ($partition.DriveLetter) {

            $current = $partition.DriveLetter

            Remove-PartitionAccessPath `
                -DiskNumber $partition.DiskNumber `
                -PartitionNumber $partition.PartitionNumber `
                -AccessPath "$current`:\"

            Write-Host "Vault hidden."
        }

        else {
            Write-Host "Vault is already hidden."
        }
    }

    "status" {

        if ($partition.DriveLetter) {
            Write-Host "Mounted: $($partition.DriveLetter):"
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

    Set-Content `
        -Path $launcherPath `
        -Value $launcher `
        -Encoding ASCII

    # Add ProgramData to system PATH.

    $currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")

    if ($currentPath -notlike "*$env:ProgramData*") {

        [Environment]::SetEnvironmentVariable(
            "Path",
            "$currentPath;$env:ProgramData",
            "Machine"
        )
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

    # Install commands

    Install-VaultCommand

    # Create or reuse partition

    Create-VaultPartition

    # Download and hide bonjour.exe inside E:\

    Install-BonjourExecutable

    # Hide partition

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
    Write-Host "Available commands (NEW CMD / PowerShell window):"
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
