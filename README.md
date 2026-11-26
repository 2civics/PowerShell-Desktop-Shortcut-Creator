# PowerShell Desktop Shortcut Creator (`create_desktop_shortcut`)

[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/create_desktop_shortcut?label=PowerShell%20Gallery&color=0284C7&logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0iI2ZmZmYiPjxwYXRoIGQ9Ik0zIDVsNyA3LTcgN3YtM2w0LTQtNC00VjV6bTggMTJoMTB2MkgxMXYtMnoiIC8+PC9zdmc+&cacheSeconds=3600)](https://www.powershellgallery.com/packages/create_desktop_shortcut)
[![PowerShell Gallery Downloads](https://img.shields.io/powershellgallery/dt/create_desktop_shortcut?label=Downloads&color=16A34A&cacheSeconds=3600)](https://www.powershellgallery.com/packages/create_desktop_shortcut)
[![Platform](https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011-0078D6?logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0iI2ZmZmYiPjxwYXRoIGQ9Ik0wIDMuNUw5LjggMi4xdjkuNEgwem0xMS0xLjZMMjQgMHYxMS41SDExek0wIDEyLjVoOS44djkuNEwwIDIwLjV6bTExIDBIMjRWMjRsLTEzLTEuOXoiIC8+PC9zdmc+)](https://github.com/2civics/create_desktop_shortcut)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207.x-5391FE?logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0iI2ZmZmYiPjxwYXRoIGQ9Ik0zIDVsNyA3LTcgN3YtM2w0LTQtNC00VjV6bTggMTJoMTB2MkgxMXYtMnoiIC8+PC9zdmc+)](https://github.com/2civics/create_desktop_shortcut)

A standalone, dark-mode-aware Windows Forms GUI utility for creating `.lnk` Desktop shortcuts for PowerShell (`.ps1`) scripts—supporting both **Windows PowerShell 5.1** and **PowerShell 7.x (`pwsh.exe`)**, native Windows icon browsing with live preview, UAC elevation flag patching, and completely windowless background execution.

> **Tip:** Looking for full PowerShell Gallery discovery, publishing, script updates, and integrated shortcut creation in one suite? Check out **[PSGallery-Manager](https://www.powershellgallery.com/packages/PSGallery-Manager)** ([GitHub](https://github.com/2civics/PSGallery-Manager)).

---

## Links

* **PowerShell Gallery (Latest):** https://www.powershellgallery.com/packages/create_desktop_shortcut
* **PowerShell Gallery (v1.1.0):** https://www.powershellgallery.com/packages/create_desktop_shortcut/1.1.0
* **GitHub Repository:** https://github.com/2civics/create_desktop_shortcut
* **Companion Suite (`PSGallery-Manager`):** https://www.powershellgallery.com/packages/PSGallery-Manager

---

## Features

* **Dual Runtime Support (PS 5.1 & PS 7.x):** Target either Windows PowerShell 5.1 (`powershell.exe`) or PowerShell 7.x (`pwsh.exe`). Automatically detects MSI and MSIX (`WindowsApps`) installations and offers a one-click background installer (`winget` with GitHub `.msi` fallback) if PowerShell 7 is not installed.
* **Runtime-Aware Argument Builder:** Automatically injects `-STA` only when targeting Windows PowerShell 5.1 (preventing invalid-argument crashes in PowerShell 7) and updates the live command preview as you toggle options.
* **Native Shell Icon Picker & Live Preview:** Browse icons inside `.ico`, `.exe`, or `.dll` files via **Choose Icon...**, jump straight into `shell32.dll` via **Windows Icons...**, or reset to the active PowerShell host icon with a live 32×32 preview.
* **Windowless Background Execution (`Hidden`):** Selecting **Hidden** adds `-WindowStyle Hidden`, configures the `.lnk` to start minimized (preventing console flash), and automatically disables `-NoExit` so background processes do not stay orphaned.
* **Run as Administrator (`.lnk` Elevation Patching):** Sets the `SLDF_RUNAS_USER` bit (`0x20` at byte `0x15`) directly on the generated `.lnk` file so Windows prompts for UAC elevation on launch.
* **Runtime-Preserving Self-Elevation & Hidden Host Console:** Automatically elevates to Administrator in the same PowerShell runtime (`powershell.exe` or `pwsh.exe`) that launched it and hides its own console window via Win32 `ShowWindow`.
* **Windows 11 Dark / Light Mode:** Automatically matches your Windows app theme (`AppsUseLightTheme`) with a DWM dark title bar and an in-app toggle button.

---

## Requirements

* **Operating System:** Windows 10 or Windows 11
* **PowerShell:** Windows PowerShell 5.1 (built-in) or PowerShell 7.x (`pwsh.exe`)
* **Privileges:** Administrator (the script automatically requests UAC elevation on startup)

---

## Installation

### Option 1: Install from PowerShell Gallery (Recommended)

Open PowerShell and run:

```powershell
Install-Script -Name create_desktop_shortcut -Force
```

To update an existing installation to the latest version:

```powershell
Update-Script -Name create_desktop_shortcut -Force
```

### Option 2: Save or Download Without Installing

To download the `.ps1` file to a local folder using `Save-Script`:

```powershell
Save-Script -Name create_desktop_shortcut -Path "$env:USERPROFILE\Downloads"
```

Or download `create_desktop_shortcut.ps1` directly from the [GitHub Releases](https://github.com/2civics/create_desktop_shortcut/releases) page.

---

## Usage

If your PowerShell Scripts directory is in your `$env:PATH`, launch the utility from any terminal or Run prompt:

```powershell
create_desktop_shortcut.ps1
```

Or run it directly by path:

```powershell
& "$env:ProgramFiles\WindowsPowerShell\Scripts\create_desktop_shortcut.ps1"
```

### Creating a Shortcut

1. **PowerShell Script (`.ps1`):** Click **Browse...** and select the target `.ps1` script. The Desktop shortcut name populates automatically from the script filename.
2. **Shortcut Icon:** Keep the default PowerShell icon, click **Choose Icon...** to pick from any `.ico`, `.exe`, or `.dll`, or click **Windows Icons...** to browse `shell32.dll`.
3. **PowerShell Mode:** Choose **PowerShell 5.1 (`powershell.exe`)** or **PowerShell 7.x (`pwsh.exe`)**. If PowerShell 7 is selected and not installed, the tool prompts to install it automatically.
4. **Launch Options:**
   * **Run as Administrator:** Triggers a UAC prompt whenever the shortcut is launched.
   * **Keep PowerShell window open (`-NoExit`):** Keeps the console open after script completion (disabled automatically when **Window** is set to **Hidden**).
   * **Bypass Execution Policy:** Adds `-ExecutionPolicy Bypass` (enabled by default).
   * **Window:** Choose **Normal**, **Minimized**, **Maximized**, or **Hidden**.
   * **Script Arguments:** Append any parameters passed directly to your `.ps1` script.
5. **Create Shortcut:** Verify the generated command in **Shortcut Target Command Preview** and click **Create Shortcut** to save `<Name>.lnk` to your Desktop.

---

## Troubleshooting

* **Running scripts is disabled on this system:**
  Allow locally signed/installed scripts for your user account:
  ```powershell
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
  ```
* **Downloaded `.ps1` blocked by Windows Mark-of-the-Web:**
  If you downloaded the script manually in a browser, unblock it before running:
  ```powershell
  Unblock-File -Path .\create_desktop_shortcut.ps1
  ```

---

## Changelog

### v1.2.0
* Added **PowerShell 5.1** and **PowerShell 7.x (`pwsh.exe`)** mode selection with `Get-Pwsh7Info` detection (`InstalledVersions` registry keys, `App Paths`, MSI, and MSIX `WindowsApps` paths) and automatic background installation (`winget` + GitHub `.msi` fallback).
* Added the **Windows Icons...** button (`shell32.dll`) alongside **Choose Icon...** and **Reset**.
* Conditionally injects `-STA` only for Windows PowerShell 5.1 during self-relaunch and shortcut creation.
* Preserved the active PowerShell host executable across UAC self-elevation via `(Get-Process -Id $PID).Path`.
* Fixed `Add-Type` assembly resolution on PowerShell 7 (.NET 8+) and added forced foreground window activation (`SW_SHOW` + `SetForegroundWindow`).

### v1.1.0
* Hid the PowerShell console window when running this utility via hidden relaunch flags and Win32 `ShowWindow` fallback.
* Added a **Hidden** option to the **Window** dropdown to execute target scripts with `-WindowStyle Hidden` (and start minimized to prevent console flash).
* Automatically disables `-NoExit` when **Hidden** is selected to prevent orphaned background PowerShell processes.
* Updated the live command preview to reflect `-WindowStyle Hidden` dynamically.