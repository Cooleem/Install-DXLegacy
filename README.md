# Install-DXLegacy (PowerShell) — README
## Script introduction (what it does)
This PowerShell script extracts legacy DirectX CABs (e.g., from the **June 2010** redistributable), installs their DLLs directly into `C:\Windows\System32` (x64) and `C:\Windows\SysWOW64` (x86), optionally backs up any existing files before overwrite, and attempts `regsvr32` registration for each installed/updated DLL. It's built for systems where the official DirectX installer fails or is blocked (embedded / LTSC / IoT scenarios, e.g., **Windows 11 IoT Enterprise LTSC 2024**).
## Key capabilities
- Auto-elevates to Admin when required.
- Creates a **System Restore Point** before any changes (can be bypassed with `-SkipRestorePoint`).
- Verifies the **active Windows drive** (defaults to `C:`; can be confirmed with `-WindowsDrive`).
- Recursively discovers `.cab` files under your `-Source` path and extracts them with Windows' built-in `expand.exe`.
- Copies DLLs into the correct system folders with **version/timestamp-aware** replacement and **backups**.
- Attempts `regsvr32` on touched DLLs (failures are expected for non-COM DLLs).
- **Readable logging**, progress bars, and a **final pause** so you can review output.
## Why I built this (context & symptoms)
- Software that relies on legacy DirectX (e.g., **RivaTuner Statistics Server**) either wouldn't launch or wouldn't enable legacy DirectX-dependent features like the On-Screen Display (OSD) in RivaTuner Statistics Server's case.
- RTSS showed:
  - `Required DirectX runtimes are not installed! On-Screen Display may not function properly!`
- Running the legacy DirectX installers (web installer or `DXSETUP.exe` from `directx_Jun2010_redist.exe`) consistently failed with:
  - `An internal system error occurred. Please refer to DXError.log and DirectX.log in your Windows folder to determine problem.`
- No `DXError.log` / `DirectX.log` were generated and **Event Viewer** contained no related entries.
### Test hygiene (to avoid cross-contamination)
- After any failed attempt, Windows was **reinstalled** to ensure a clean baseline for the next test.
- When switching ISOs, hashes were **verified** and **Rufus → "Enable runtime UEFI media validation"** was kept on to rule out corrupt media.
- **All ISOs were untouched** (no modifications).
## What I tried (all failed on my system)
- **Fully update** Windows via Windows Update.
- Verify policy that controls optional component installs/repairs:  
  - `Computer Configuration → Administrative Templates → System → Specify settings for optional component installation and component repair.`
- Add/verify OS media features:
  - **Graphics Tools** (Optional Features/Features on Demand)
  - **Windows Media Player** (Optional Features/Features on Demand)
  - **Media Feature Pack**
    - On a clean install, used:
      - `DISM /Online /Add-Capability /CapabilityName:Media.WindowsMediaPlayer~~~~0.0.12.0` → **reboot**
      - `DISM /Online /Add-Capability /CapabilityName:Media.MediaFeaturePack~~~~0.0.1.0` → **reboot**
- Install runtime prerequisites:
  - **ALL** .NET Framework versions (at minimum **.NET 3.5 SP1**)
  - **ALL** Visual C++ Redistributable packages
- System integrity/health checks (despite the fact I was using a brand new NVMe SSD):
  - `DISM /Online /Cleanup-Image /RestoreHealth`
  - `sfc /scannow`
  - `chkdsk /f /r /x`
- Standard DirectX installers:
  - **DirectX End-User Runtime Web Installer**
  - **DirectX End-User Runtimes (June 2010)** via `DXSETUP.exe`
  - **Compatibility mode** for both `dxwebsetup.exe` and `DXSETUP.exe`, testing **every** available Windows version
- Driver sanity:
  - Clean reinstall of **NVIDIA** GPU drivers
  - Clean reinstall of **Intel Graphics** drivers (iGPU)
- Last-resort OS actions:
  - **Fresh Windows reinstall**, verified ISO hashes, and used Rufus' **"Enable runtime UEFI media validation"**
- Hail-Mary steps:
  - Anecdotal **Registry tweaks** (e.g., `HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\DirectX`)
- Firmware:
  - **Reflashed BIOS** and loaded **stock/default settings**
## What finally worked (resolution summary)
Following the approach documented in this README—**extracting the June 2010 CABs and running this script**—installed the necessary legacy DirectX DLLs into `System32` and `SysWOW64`, resolving the RTSS OSD issue on **Windows 11 IoT Enterprise LTSC 2024**. (For exact commands and options, see **Quick start** and **Usage** in this README.)
## Quick start
- Extract the Microsoft **[DirectX End-User Runtimes (June 2010)](https://www.microsoft.com/en-us/download/details.aspx?id=8109)** EXE to a folder (it produces many `*.cab` files).
- Run only the final June 2010 component CABs:
  - `powershell -ExecutionPolicy Bypass -File .\Install-DXLegacy.ps1 -Source "C:\DXRedist" -OnlyJune2010`
- `-Source` must point at the folder that contains the **extracted** CAB files (not the EXE).
- The script **auto-elevates**; if you're not already Admin, it relaunches itself elevated.
- When done, the window **stays open** so you can read the summary; press **Enter** to close.
## Usage
- `powershell -ExecutionPolicy Bypass -File .\Install-DXLegacy.ps1 [-Source "<path>"] [-BackupDir "<path>"] [-OnlyJune2010] [-WindowsDrive "<drive>"] [-SkipRestorePoint]`
## Parameters
- `-Source <string>`
  - **What:** Path to the directory that contains the extracted DirectX CAB files.
  - **Default:** `.` (current directory)
  - **Behavior:** Recurses through all subfolders to find `*.cab`.

- `-BackupDir <string>`
  - **What:** Path for backups and the log file.
  - **Default:** `C:\DXLegacy_Backup_<YYYYMMDD_HHMMSS>`
  - **Behavior:**
    - Creates subfolders `System32_Backup` and `SysWOW64_Backup`.
    - If an existing DLL is replaced, the previous copy is saved to the appropriate backup folder.
    - **Fail-safe:** If the backup/log folder cannot be created on the system drive (policy/ACLs), the script falls back to a folder on the **current user's Desktop**.

- `-OnlyJune2010` (switch)
  - **What:** Processes only June 2010 component CABs (matching `Jun2010_*.cab`, such as `Jun2010_d3dx9_43_x86.cab`, `Jun2010_XAudio_x64.cab`, etc.).
  - **Use when:** You want the final legacy D3DX / D3DCompiler / XAudio / XInput files most games/tools expect without scanning older incremental CABs.
  - Omit to process **all** CABs under `-Source`.

- `-WindowsDrive <string>`
  - **What:** Explicitly confirm the active Windows drive letter (e.g., `"C:"` or `"D:"`).
  - **Behavior:** The script checks that `%WINDIR%` is actually on the supplied drive. If there's a mismatch, it stops.
  - **Why:** Prevents modifying the wrong Windows volume in multi-boot or atypical layouts. If Windows isn't on `C:`, you **must** provide this parameter.

- `-SkipRestorePoint` (switch)
  - **What:** Skip creating a System Restore Point.
  - **Why:** Only use if you understand the risk or System Protection is unavailable. By default, the script creates a restore point before any changes.
## How it works (flow)
1. Elevation & safety checks
   - Relaunches itself as Admin if not already elevated.
   - Determines the actual Windows drive from `%WINDIR%` and enforces `-WindowsDrive` if you're not on `C:`.
   - Creates a **System Restore Point** (unless `-SkipRestorePoint`).

2. Logging & prep
   - Creates a timestamped backup/log folder (falls back to Desktop if needed).
   - Logs start info (machine, user, source path, backup dir).
   - Prepares per-arch backup folders and a temporary extraction area.

3. CAB discovery & extraction
   - Recursively finds `*.cab` in `-Source` (optionally filters to `Jun2010_*.cab`).
   - Extracts each CAB using `expand.exe` into a temp subfolder.

4. DLL install/update
   - Detects each DLL's architecture via its PE header:
     - x64 → `C:\Windows\System32`
     - x86 → `C:\Windows\SysWOW64`
   - If a destination file exists, replaces only when the source appears **newer/better** by **version** or **timestamp**.
   - Backs up any overwritten file to the backup folder.

5. Registration attempts
   - Runs `regsvr32 /s` against each **touched** DLL using the correct bitness (x86/x64).
   - Many legacy DirectX DLLs are **not** COM servers; registration failures here are normal and **do not** imply a broken install.

6. Wrap-up
   - Writes a concise **summary** (installs/updates, `regsvr32` successes/failures, backup and log locations, elapsed time).
   - Leaves the window **open** so you can review output; press **Enter** to close.
## Notes
- The script automatically **decompresses** CABs with Windows' built-in `expand.exe` — no 3rd-party tools needed.
- DLL **registration failures are expected** for many DirectX files. The important part is that the correct DLLs are now present in:
  - `C:\Windows\System32` (x64)
  - `C:\Windows\SysWOW64` (x86)
- Don't place DLLs in subfolders inside `System32`/`SysWOW64` — they need to live **directly** in those folders to be found.
- Some well-known files provided by the June 2010 redist include: `d3dx9_43.dll`, `d3dx10_43.dll`, `d3dx11_43.dll`, `D3DCompiler_43.dll`, `XAudio2_7.dll`, `XInput1_3.dll` (in both 32-bit and 64-bit variants).
- `dxdiag` typically won't show these legacy components explicitly; validation is usually via your app/tool (e.g., RTSS OSD working again).
- Added `BEGINNER NOTE` and other additional comments throughout the PowerShell script for anyone unfamiliar with PowerShell scripting.
## Examples
- Process all CABs below a source folder
  - `powershell -ExecutionPolicy Bypass -File .\Install-DXLegacy.ps1 -Source "D:\Packages\DX2010"`

- Only the June 2010 component CABs
  - `powershell -ExecutionPolicy Bypass -File .\Install-DXLegacy.ps1 -Source "C:\DXRedist" -OnlyJune2010`

- Custom backup/log location
  - `powershell -ExecutionPolicy Bypass -File .\Install-DXLegacy.ps1 -Source "C:\DXRedist" -BackupDir "E:\Temp\DXLegacyBackups"`

- Windows installed on a non-C: drive
  - `powershell -ExecutionPolicy Bypass -File .\Install-DXLegacy.ps1 -Source "F:\DX2010" -WindowsDrive "D:"`

- Skip restore point (advanced users)
  - `powershell -ExecutionPolicy Bypass -File .\Install-DXLegacy.ps1 -Source "C:\DXRedist" -OnlyJune2010 -SkipRestorePoint`
## Logging & progress
- Log file: `Install-DXLegacy_<timestamp>.log` inside `-BackupDir` (or the Desktop fallback).
- Progress bars: show CAB extraction and DLL install/registration status.
- Console output: clear `[OK]`, `[X]`, `[!]` markers; a summary is printed at the end.
## Exit codes (for automation)
- `0` — Success
- `1` — No CABs found under `-Source`
- `1001` — Windows drive isn't `C:` and `-WindowsDrive` wasn't provided
- `1002` — `-WindowsDrive` doesn't match the actual `%WINDIR%` drive
- `1003` — Restore point creation failed (and `-SkipRestorePoint` not used)
- `1004` — Couldn't create backup/log directory (including Desktop fallback)
- `999` — Unhandled error caught by global trap
## Troubleshooting
- "[X] No CABs found under \<path>"
  - Ensure you pointed `-Source` at the folder containing the **extracted** `Jun2010_*.cab` files (not the EXE).
  - If using `-OnlyJune2010`, verify the CAB names begin with `Jun2010_`.
- Restore point creation fails
  - Turn on **System Protection** for the OS drive, or re-run with `-SkipRestorePoint` (accepting the risk).
- Mismatched OS drive
  - If Windows isn't on `C:`, re-run with `-WindowsDrive "<actualDrive>:"` (e.g., `-WindowsDrive "D:"`).
- `regsvr32` failures
  - Normal for non-COM DirectX DLLs. Presence of the DLLs in the correct folders is the key outcome.
## Requirements
- PowerShell (Windows PowerShell 5.x or PowerShell 7+).
- Administrator privileges (the script auto-elevates).
- Access to the **June 2010** DirectX redistributable **CABs** (extracted from the **[official Microsoft redist EXE](https://www.microsoft.com/en-us/download/details.aspx?id=8109)**).
