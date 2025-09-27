<# 
.SYNOPSIS
  Install legacy DirectX DLLs directly into System32/SysWOW64 with
  real-time progress, readable logging, and registration attempts.

.PARAMETER Source
  Folder containing the extracted DirectX redist CABs (e.g., C:\DXRedist)

.PARAMETER BackupDir
  Where to store backups and logs (default: C:\DXLegacy_Backup_YYYYMMDD_HHMMSS)

.PARAMETER OnlyJune2010
  If set, only process Jun2010_X86.cab and Jun2010_X64.cab

.PARAMETER WindowsDrive
  Explicitly confirm the active Windows drive letter (e.g., -WindowsDrive "C:" or -WindowsDrive "D").
  The script verifies that %WINDIR% is on the supplied drive and aborts if not.

.PARAMETER SkipRestorePoint
  Bypass creating a System Restore Point. Use only if you understand the risk.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Install-DXLegacy_v4.ps1 -Source "C:\DXRedist" -OnlyJune2010
#>
# BEGINNER NOTE:
# This top block is just documentation that PowerShell shows when someone runs:
#   Get-Help .\Install-DXLegacy_v4.ps1 -Full
# It does not execute anything; it explains what the script does and which options it accepts.

param(
  [string]$Source = ".",
  [string]$BackupDir,
  [switch]$OnlyJune2010,
  [string]$WindowsDrive,
  [switch]$SkipRestorePoint
)
# BEGINNER NOTE:
# These are inputs (called parameters) you can pass to the script.
# - $Source: Where your extracted DirectX .cab files live (default is the current folder).
# - $BackupDir: Where to save backups and logs (if not given, the script creates a folder automatically).
# - $OnlyJune2010: If included, restricts processing to the June 2010 CABs.
# - $WindowsDrive: Safety check—confirm which drive letter actually contains Windows (e.g., "C:").
# - $SkipRestorePoint: Lets you choose to skip creating a restore point (not recommended for most users).

# -------------------------------------------------------------------------------------------------
# GLOBAL ERROR BEHAVIOR & "RUN WITH POWERSHELL" QUALITY-OF-LIFE
# -------------------------------------------------------------------------------------------------
# - Force terminating errors so failures are caught early and don't continue silently.
# - A top-level 'trap' will catch any unhandled terminating error, print it clearly,
#   and PAUSE the window so users who launched via "Run with PowerShell" can read it.
#   (This avoids the common "window closes instantly" problem on errors.)
# -------------------------------------------------------------------------------------------------
$ErrorActionPreference = "Stop"
# BEGINNER NOTE:
# This tells PowerShell to treat most problems as "stop now" errors, so we don't continue in a broken state.

function Stop-WithPause {
  param(
    [int]$Code = 1,
    [string]$Message = ""
  )
  if ($Message) {
    Write-Host "  [X] $Message" -ForegroundColor Red
  }
  # If we are in a console window (including Run with PowerShell), give the user a chance to read.
  try {
    if ($Host.Name -like "*ConsoleHost*") {
      Write-Host ""
      Read-Host "Press Enter to close this window"
    }
  } catch { }
  exit $Code
}
# BEGINNER NOTE:
# Stop-WithPause is a helper function that prints a message, waits for you to press Enter,
# and then exits with a code. It's used for clean, readable exits—especially when errors happen.

trap {
  # Catch any unhandled terminating errors, surface details, then pause/exit.
  Write-Host ""
  Write-Host "  [X] Unhandled error: $($_.Exception.Message)" -ForegroundColor Red
  if ($_.InvocationInfo.PositionMessage) {
    Write-Host "      At: $($_.InvocationInfo.PositionMessage.Trim())" -ForegroundColor DarkGray
  }
  try {
    if ($Host.Name -like "*ConsoleHost*") {
      Write-Host ""
      Read-Host "Press Enter to close this window"
    }
  } catch { }
  exit 999
}
# BEGINNER NOTE:
# This trap is a global safety net. If something goes wrong that we didn't specifically handle,
# this will show the error and pause so you can read it instead of the window disappearing.

# -------------------------------------------------------------------------------------------------
# AUTO-ELEVATION (supports right-click "Run with PowerShell")
# -------------------------------------------------------------------------------------------------
# If not running as Administrator, relaunch elevated with the same parameters and
# with ExecutionPolicy Bypass so the relaunch can proceed without policy blocks.
# -------------------------------------------------------------------------------------------------
$ident = [Security.Principal.WindowsIdentity]::GetCurrent()
$princ = New-Object Security.Principal.WindowsPrincipal($ident)
if (-not $princ.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  $args = @('-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"","-Source", "`"$Source`"")
  if ($BackupDir)       { $args += @("-BackupDir","`"$BackupDir`"") }
  if ($OnlyJune2010)    { $args += "-OnlyJune2010" }
  if ($WindowsDrive)    { $args += @("-WindowsDrive","`"$WindowsDrive`"") }
  if ($SkipRestorePoint){ $args += "-SkipRestorePoint" }
  Start-Process -FilePath "powershell.exe" -ArgumentList $args -Verb RunAs
  exit
}
# BEGINNER NOTE:
# Installing system files requires Administrator rights. If you're not admin, this part restarts the script
# with admin privileges and the same options you provided. Then the current (non-admin) instance exits.

# ---------- Console markers (ASCII-safe) ----------
$OK    = "[OK]"
$FAIL  = "[X]"
$WARN  = "[!]"
$BUL   = "-"
# BEGINNER NOTE:
# These are just text labels used to prefix console messages (visual clarity: OK, X, !, and a bullet).

# -------------------------------------------------------------------------------------------------
# SAFETY INTERLOCK: VERIFY THE ACTIVE WINDOWS DRIVE
# -------------------------------------------------------------------------------------------------
# Determine where the currently running Windows lives (e.g., "C:").
# If the user supplied -WindowsDrive, ensure it matches; otherwise:
#   - If Windows is not on C:, abort with instructions to re-run with -WindowsDrive "<drive>".
# This prevents accidentally writing to the wrong Windows volume in multi-boot/atypical setups.
# -------------------------------------------------------------------------------------------------
$__osDrive = (Split-Path $env:WINDIR -Qualifier).TrimEnd('\')  # e.g., "C:"
if ($WindowsDrive) {
  $__want = ($WindowsDrive.Trim()).TrimEnd('\','/').ToUpper()
  if ($__want.Length -eq 1) { $__want += ":" }   # Accept "C" as "C:"  (FIX: avoid $"$__want:" parsing issue)
  if ($__want -ne $__osDrive.ToUpper()) {
    Stop-WithPause -Code 1002 -Message "Active Windows appears to be on '$__osDrive', not on '$__want'. Aborting."
  }
} else {
  if ($__osDrive.ToUpper() -ne "C:") {
    Write-Host "  $FAIL Active Windows is on '$__osDrive', not 'C:'." -ForegroundColor Red
    Write-Host "       Re-run with -WindowsDrive '$__osDrive' to confirm you intend to modify that volume." -ForegroundColor Yellow
    Write-Host "       Example:  powershell -ExecutionPolicy Bypass -File .\Install-DXLegacy_v4.ps1 -Source ""C:\DXRedist"" -WindowsDrive ""$__osDrive""" -ForegroundColor Yellow
    Stop-WithPause -Code 1001
  }
}
# BEGINNER NOTE:
# This is a safety check to make sure the script is targeting the correct Windows installation.
# If your Windows isn't on C:, you must explicitly confirm the real drive (e.g., -WindowsDrive "D:").

# -------------------------------------------------------------------------------------------------
# SYSTEM RESTORE POINT (BEFORE ANY CHANGES) — CAN BE OVERRIDDEN VIA -SkipRestorePoint
# -------------------------------------------------------------------------------------------------
# Create a System Restore Point to allow rollback. This requires System Protection enabled.
# If -SkipRestorePoint is set, we skip this step (user explicitly accepted the risk).
# -------------------------------------------------------------------------------------------------
function New-SystemRestorePoint {
  param([string]$Description)
  try {
    # Preferred path: WMI API (often avoids certain throttling limits)
    $r = Invoke-CimMethod -Namespace "root/default" -ClassName "SystemRestore" -MethodName "CreateRestorePoint" -Arguments @{
      Description      = $Description
      RestorePointType = 0     # APPLICATION_INSTALL
      EventType        = 100   # BEGIN_SYSTEM_CHANGE
    } -ErrorAction Stop
    if ($r.ReturnValue -eq 0) { return $true }
    throw "WMI CreateRestorePoint returned code $($r.ReturnValue)"
  } catch {
    # Fallback: PowerShell cmdlet (may be throttled or disabled if System Protection is off)
    Checkpoint-Computer -Description $Description -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop | Out-Null
    return $true
  }
}
# BEGINNER NOTE:
# This function asks Windows to create a restore point so you can roll back system changes
# if needed. It tries two different methods to improve the odds it works.

if (-not $SkipRestorePoint) {
  try {
    Write-Host "$BUL Creating system restore point..." -ForegroundColor Cyan
    New-SystemRestorePoint -Description ("DXLegacy pre-install " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
    Write-Host "  $OK Restore point created." -ForegroundColor Green
  } catch {
    Stop-WithPause -Code 1003 -Message "Unable to create a system restore point: $($_.Exception.Message)`n       Enable System Protection for the OS drive or re-run with -SkipRestorePoint."
  }
} else {
  Write-Host "$WARN System restore point creation was skipped due to -SkipRestorePoint." -ForegroundColor Yellow
}
# BEGINNER NOTE:
# Unless you use -SkipRestorePoint, the script creates a restore point now. If that fails,
# the script stops to keep you safe. You can override with -SkipRestorePoint at your own risk.

# ---------- Helpers ----------
function New-Dir($p) {
  if (-not (Test-Path -LiteralPath $p)) {
    New-Item -ItemType Directory -Path $p | Out-Null
  }
}
# BEGINNER NOTE:
# New-Dir creates a folder if it doesn't already exist, staying quiet (no clutter) if it does.

function Get-FileVersionOrNull([string]$path) {
  try {
    $v = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($path).FileVersion
    if ($v) { return [version]$v } else { return $null }
  } catch { return $null }
}
# BEGINNER NOTE:
# Tries to read the file version of a DLL. If there is no version info, returns $null instead of crashing.

function Is-SrcPreferred([string]$src, [string]$dst) {
  $sv = Get-FileVersionOrNull $src
  $dv = Get-FileVersionOrNull $dst
  if ($sv -and $dv) { return ($sv -gt $dv) }
  elseif ($sv -and -not $dv) { return $true }
  elseif (-not $sv -and $dv) { return $false }
  else {
    $s = (Get-Item $src).LastWriteTimeUtc
    $d = (Get-Item $dst).LastWriteTimeUtc
    return ($s -gt $d)
  }
}
# BEGINNER NOTE:
# Decides whether to overwrite an existing DLL:
# 1) Prefer the one with the higher version.
# 2) If versions are missing, prefer the newer file by timestamp.
# This avoids downgrading newer files.

function Get-PEArch([string]$filePath) {
  $fs = [System.IO.File]::Open($filePath, 'Open', 'Read', 'ReadWrite')
  try {
    $br = New-Object System.IO.BinaryReader($fs)
    $fs.Seek(0x3C, 'Begin') | Out-Null
    $peOffset = $br.ReadInt32()
    $fs.Seek($peOffset, 'Begin') | Out-Null
    $sig = $br.ReadBytes(4) # "PE`0`0"
    if (-not ($sig[0] -eq 0x50 -and $sig[1] -eq 0x45 -and $sig[2] -eq 0x00 -and $sig[3] -eq 0x00)) {
      return "unknown"
    }
    $machine = $br.ReadUInt16()
    switch ($machine) {
      0x14c  { return "x86" }   # IMAGE_FILE_MACHINE_I386
      0x8664 { return "x64" }   # IMAGE_FILE_MACHINE_AMD64
      default { return "unknown" }
    }
  } finally { $br.Dispose(); $fs.Dispose() }
}
# BEGINNER NOTE:
# Opens each DLL and checks its internal header to learn if it's 32-bit (x86) or 64-bit (x64).

function Try-RegisterDll {
  param(
    [Parameter(Mandatory=$true)][string]$DllPath,
    [Parameter(Mandatory=$true)][ValidateSet('x86','x64')]$Arch
  )
  $regsvr = if ($Arch -eq 'x64') { "$env:WINDIR\System32\regsvr32.exe" } else { "$env:WINDIR\SysWOW64\regsvr32.exe" }
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName               = $regsvr
  $psi.Arguments              = "/s `"$DllPath`""
  $psi.UseShellExecute        = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  $p.WaitForExit()
  return [pscustomobject]@{
    Path   = $DllPath
    Arch   = $Arch
    Code   = $p.ExitCode
    StdOut = $p.StandardOutput.ReadToEnd()
    StdErr = $p.StandardError.ReadToEnd()
  }
}
# BEGINNER NOTE:
# regsvr32 registers certain types of DLLs with Windows (COM servers).
# Many DirectX DLLs are NOT COM servers—so it's normal if some don't register.
# This still tries and records success/failure for your reference.

# ---------- Paths & prep ----------
$absSource = (Resolve-Path $Source).Path
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
if (-not $BackupDir) { $BackupDir = "C:\DXLegacy_Backup_$timestamp" }
# BEGINNER NOTE:
# Resolve-Path makes sure the Source path exists and is absolute.
# If you didn't specify a BackupDir, we create one on C:\ with a timestamp in its name.

# FAIL-SAFE: if the desired BackupDir can't be created (ACL/policy), fall back to user's Desktop.
try {
  New-Dir $BackupDir
} catch {
  try {
    $fallback = Join-Path ([Environment]::GetFolderPath('Desktop')) "DXLegacy_Backup_$timestamp"
    Write-Host "  $WARN Could not create backup/log folder at '$BackupDir'. Falling back to Desktop: '$fallback'." -ForegroundColor Yellow
    $BackupDir = $fallback
    New-Dir $BackupDir
  } catch {
    Stop-WithPause -Code 1004 -Message "Failed to create a backup/log folder at both '$BackupDir' and Desktop. Aborting."
  }
}
# BEGINNER NOTE:
# We try to make the backup/log folder. If that fails (permissions, policy, etc.),
# we fall back to a folder on your Desktop. If even that fails, we stop for safety.

$logPath = Join-Path $BackupDir "Install-DXLegacy_$timestamp.log"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
# BEGINNER NOTE:
# $logPath is where the detailed text log goes. $sw is a stopwatch so we can report how long it took.

# Tidy log helpers (avoid -f to dodge brace parsing issues on bad encodings)
$LogDivider = ('-'*110)
function Write-LogHeader {
  @"
$LogDivider
DirectX Legacy Install Log
Machine   : $env:COMPUTERNAME
User      : $env:USERNAME
Source    : $absSource
BackupDir : $BackupDir
Started   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
$LogDivider
TIME                 | LEVEL | ACTION                | TARGET
$LogDivider
"@ | Out-File -FilePath $logPath -Encoding UTF8
}
function Write-Log([string]$level,[string]$action,[string]$target) {
  $ts = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  "$ts | $level | $action | $target" | Out-File -FilePath $logPath -Append -Encoding UTF8
}
# BEGINNER NOTE:
# These two functions write a neat log file to the path above so you can audit exactly what happened.

Write-LogHeader
Write-Log "INFO" "Start" "Processing CABs under $absSource"
# BEGINNER NOTE:
# Start the log so even early failures get recorded.

$destX64 = "$env:WINDIR\System32"
$destX86 = "$env:WINDIR\SysWOW64"
$bakX64  = Join-Path $BackupDir "System32_Backup"
$bakX86  = Join-Path $BackupDir "SysWOW64_Backup"
New-Dir $bakX64
New-Dir $bakX86
# BEGINNER NOTE:
# These are the final destination folders for 64-bit and 32-bit DLLs.
# Before overwriting an existing DLL, the script backs it up into these backup folders.

$tempRoot = Join-Path $env:TEMP "DXLegacy_$timestamp"
New-Dir $tempRoot
# BEGINNER NOTE:
# Temporary working folder where each CAB will be extracted before installing DLLs.

$x64Touched = New-Object System.Collections.Generic.List[string]
$x86Touched = New-Object System.Collections.Generic.List[string]
# BEGINNER NOTE:
# These lists collect the full paths of DLLs we actually installed/updated.
# Later, we attempt regsvr32 only on the ones we touched.

# ---------- Discover CABs ----------
$cabs = Get-ChildItem -LiteralPath $absSource -Filter *.cab -File -Recurse
# BEGINNER NOTE:
# Find all .cab files under the Source folder (and its subfolders).

if ($OnlyJune2010) {
  # Match ALL June 2010 component CABs (e.g., Jun2010_d3dx9_43_x86.cab, Jun2010_XAudio_x64.cab, etc.)
  $cabs = $cabs | Where-Object { $_.Name -match '^(?i)Jun2010_.*\.cab$' }
}
# BEGINNER NOTE:
# If you passed -OnlyJune2010, we filter to just the June 2010 CABs.

$cabs = $cabs | Sort-Object FullName
if (-not $cabs) {
  Write-Host "$FAIL No CABs found under $absSource" -ForegroundColor Red
  Write-Log "ERROR" "NoCABs" $absSource
  Stop-WithPause -Code 1
}
# BEGINNER NOTE:
# If no CABs are found after filtering, we stop and tell you why (with a log entry).

# ---------- CAB loop ----------
[int]$cabIdx = 0
[int]$cabTotal = $cabs.Count
# BEGINNER NOTE:
# These counters let us show progress like "(2/10)" while processing.

foreach ($cab in $cabs) {
  $cabIdx++
  $cabLabel = "$($cab.Name) ($cabIdx/$cabTotal)"
  Write-Progress -Id 1 -Activity "Extracting CABs" -Status $cabLabel -PercentComplete ([int](($cabIdx/$cabTotal)*100))
  Write-Host "$BUL Extracting: $cabLabel" -ForegroundColor Cyan
  Write-Log "INFO" "ExpandCAB" $cab.FullName

  $work = Join-Path $tempRoot ([IO.Path]::GetFileNameWithoutExtension($cab.Name))
  New-Dir $work
  & "$env:SystemRoot\System32\expand.exe" -F:* "`"$($cab.FullName)`"" "`"$work`"" | Out-Null
  # BEGINNER NOTE:
  # expand.exe is a built-in Windows tool that extracts the contents of CAB files.

  $dlls = Get-ChildItem -LiteralPath $work -Recurse -Include *.dll -File
  $dllCount = $dlls.Count
  [int]$dllIdx = 0
  # BEGINNER NOTE:
  # Find all DLLs we just extracted from this one CAB, so we can install them.

  foreach ($dll in $dlls) {
    $dllIdx++
    $pct = if ($dllCount -gt 0) { [int](($dllIdx/$dllCount)*100) } else { 100 }
    Write-Progress -Id 2 -ParentId 1 -Activity "Installing from $($cab.Name)" -Status "$($dll.Name) ($dllIdx/$dllCount)" -PercentComplete $pct

    $arch = Get-PEArch $dll.FullName
    switch ($arch) {
      "x64" { $dest = Join-Path $destX64 $dll.Name; $bak = Join-Path $bakX64 $dll.Name; $tList = $x64Touched; $archDisp="x64" }
      "x86" { $dest = Join-Path $destX86 $dll.Name; $bak = Join-Path $bakX86 $dll.Name; $tList = $x86Touched; $archDisp="x86" }
      default {
        if ($dll.FullName -match '(?i)x64') { $dest = Join-Path $destX64 $dll.Name; $bak = Join-Path $bakX64 $dll.Name; $tList = $x64Touched; $archDisp="x64?" }
        elseif ($dll.FullName -match '(?i)x86') { $dest = Join-Path $destX86 $dll.Name; $bak = Join-Path $bakX86 $dll.Name; $tList = $x86Touched; $archDisp="x86?" }
        else { $dest = Join-Path $destX86 $dll.Name; $bak = Join-Path $bakX86 $dll.Name; $tList = $x86Touched; $archDisp="x86*" }
      }
    }
    # BEGINNER NOTE:
    # Decide where to copy the DLL:
    # - 64-bit DLLs go to System32 (yes, that's correct).
    # - 32-bit DLLs go to SysWOW64.
    # - If we can't tell, use hints in the file path; otherwise assume 32-bit.

    $copied = $false
    if (Test-Path -LiteralPath $dest) {
      if (Is-SrcPreferred -src $dll.FullName -dst $dest) {
        if (-not (Test-Path -LiteralPath $bak)) { Copy-Item -LiteralPath $dest -Destination $bak -ErrorAction SilentlyContinue }
        Copy-Item -LiteralPath $dll.FullName -Destination $dest -Force
        Write-Host "  $OK Updated [$archDisp] $($dll.Name)" -ForegroundColor Green
        Write-Log "OK" "UpdateDLL" "$archDisp -> $dest"
        $copied = $true
      } else {
        Write-Host "  $WARN Skipped (existing newer) [$archDisp] $($dll.Name)" -ForegroundColor Yellow
        Write-Log "WARN" "SkipNewer" "$archDisp -> $dest"
      }
    } else {
      Copy-Item -LiteralPath $dll.FullName -Destination $dest
      Write-Host "  $OK Installed [$archDisp] $($dll.Name)" -ForegroundColor Green
      Write-Log "OK" "InstallDLL" "$archDisp -> $dest"
      $copied = $true
    }
    # BEGINNER NOTE:
    # If a DLL already exists, we only overwrite it when the new one looks "better"
    # (newer version or newer timestamp). The old file gets backed up first.

    if ($copied) { $tList.Add($dest) }
    # BEGINNER NOTE:
    # Keep track of files we actually changed, so we can try to register them later.
  }

  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
  # BEGINNER NOTE:
  # Clean up the temporary folder for this CAB to keep things tidy.
}

# ---------- Registration ----------
Write-Progress -Id 1 -Activity "Registering DLLs" -Status "x64 then x86" -PercentComplete 0
# BEGINNER NOTE:
# Now we try to register any DLLs we touched (when applicable).

$regOK = 0
$regFAIL = 0
# BEGINNER NOTE:
# Count how many registrations succeed/fail. Failures do NOT necessarily mean anything is broken.

# x64
$items = ($x64Touched | Sort-Object -Unique)
[int]$i=0; [int]$n=$items.Count
foreach ($dllPath in $items) {
  $i++
  Write-Progress -Id 2 -ParentId 1 -Activity "Registering x64 DLLs" -Status "$(Split-Path $dllPath -Leaf) ($i/$n)" -PercentComplete ([int](($i/$n)*100))
  $r = Try-RegisterDll -DllPath $dllPath -Arch x64
  if ($r.Code -eq 0) {
    Write-Host "  $OK regsvr32 OK [x64] $(Split-Path $dllPath -Leaf)" -ForegroundColor Green
    Write-Log "OK" "Register" "x64 -> $dllPath"
    $regOK++
  } else {
    Write-Host "  $FAIL regsvr32 FAIL($($r.Code)) [x64] $(Split-Path $dllPath -Leaf)" -ForegroundColor Red
    Write-Log "FAIL" "Register" "x64 -> $dllPath (Exit=$($r.Code))"
    $regFAIL++
  }
}
# BEGINNER NOTE:
# Register each 64-bit DLL we changed. Success is great; failure is often fine for non-COM DLLs.

# x86
$items = ($x86Touched | Sort-Object -Unique)
[int]$i=0; [int]$n=$items.Count
foreach ($dllPath in $items) {
  $i++
  Write-Progress -Id 2 -ParentId 1 -Activity "Registering x86 DLLs" -Status "$(Split-Path $dllPath -Leaf) ($i/$n)" -PercentComplete ([int](($i/$n)*100))
  $r = Try-RegisterDll -DllPath $dllPath -Arch x86
  if ($r.Code -eq 0) {
    Write-Host "  $OK regsvr32 OK [x86] $(Split-Path $dllPath -Leaf)" -ForegroundColor Green
    Write-Log "OK" "Register" "x86 -> $dllPath"
    $regOK++
  } else {
    Write-Host "  $FAIL regsvr32 FAIL($($r.Code)) [x86] $(Split-Path $dllPath -Leaf)" -ForegroundColor Red
    Write-Log "FAIL" "Register" "x86 -> $dllPath (Exit=$($r.Code))"
    $regFAIL++
  }
}
# BEGINNER NOTE:
# Same idea for 32-bit DLLs. Again, failures here are expected for many DirectX DLLs.

# ---------- Wrap-up ----------
Write-Progress -Id 1 -Activity "Completed" -Completed
Write-Progress -Id 2 -Activity "Completed" -Completed
# BEGINNER NOTE:
# Clear the on-screen progress bars.

$sw.Stop()
$summary = @()
$summary += "DLL installs/updates are listed above."
$summary += "regsvr32 successes: $regOK"
$summary += "regsvr32 failures : $regFAIL"
$summary += "Backups: $bakX64"
$summary += "         $bakX86"
$summary += "Log: $logPath"
$summary += ("Elapsed: {0:n1} sec" -f $sw.Elapsed.TotalSeconds)
# BEGINNER NOTE:
# Prepare a short human-readable summary for the console.

Write-Host ""
Write-Host "Summary:"
$summary | ForEach-Object { Write-Host "  $_" }
# BEGINNER NOTE:
# Print the summary to the screen so you don't have to open the log for the high-level view.

Write-Log "INFO" "Done" "Elapsed $([math]::Round($sw.Elapsed.TotalSeconds,1))s"
Add-Content -Path $logPath -Value $LogDivider
# BEGINNER NOTE:
# Add a "Done" entry to the log and a divider line to mark the end of this run.

# -------------------------------------------------------------------------------------------------
# SUCCESS PAUSE (NEW): keep the window open after successful completion
# -------------------------------------------------------------------------------------------------
# Purpose: When users start the script via "Run with PowerShell", the window would normally close
#          immediately on success. This pause mirrors the error-handling behavior so users can read
#          the final summary and any console output before closing the window themselves.
# -------------------------------------------------------------------------------------------------
try {
  if ($Host.Name -like "*ConsoleHost*") {
    Write-Host ""
    Read-Host "Done. Press Enter to close this window"
  }
} catch { }
# BEGINNER NOTE:
# After everything succeeds, we pause so you can review the output. Press Enter to close.