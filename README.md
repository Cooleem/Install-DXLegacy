# Install-DXLegacy
This PowerShell script extracts legacy DirectX CABs (e.g., from the June 2010 redistributable), installs their DLLs directly into System32 (x64) and SysWOW64 (x86), optionally backs up any existing files before overwrite, and attempts regsvr32 registration for each installed/updated DLL.
