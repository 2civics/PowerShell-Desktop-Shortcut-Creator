<#PSScriptInfo

.VERSION 1.2.1

.GUID 5991d012-5e7c-4ad2-8ccf-cdb75a0fdc73

.AUTHOR waresoft

.COMPANYNAME waresoft

.COPYRIGHT (c) 2026 waresoft. All rights reserved.

.TAGS PowerShell Shortcut ShortcutCreator DesktopShortcut LNK Launcher GUI WinForms Windows Desktop Utility Automation DarkMode UAC Elevation ExecutionPolicy HiddenWindow pwsh PowerShell7

.LICENSEURI https://opensource.org/licenses/MIT

.PROJECTURI https://github.com/2civics/PowerShell-Desktop-Shortcut-Creator

.RELEASENOTES
v1.2.1:
- Fixed PowerShell 7.x High-DPI & Multi-Resolution Rendering: Configured DpiUnawareGdiScaled high-DPI mode, DPI AutoScale baselines, dynamic ComboBox item heights, and WorkingArea screen clamping so the UI scales cleanly across resolutions and Windows display scales.
- Responsive 3-Zone Layout: Replaced fixed pixel coordinates with TableLayoutPanel/FlowLayoutPanel containers, pinned the command preview and action buttons at the bottom, and auto-sized initial form height to eliminate side scrollbars on startup while supporting AutoScroll on smaller displays.

v1.2.0:
- Aligned PowerShell 5.1 / 7.x mode selection, Get-Pwsh7Info detection, inline status indicator, and background winget/GitHub MSI installation with PSGallery-Manager.
- Added the "Windows Icons..." button (shell32.dll) alongside "Choose Icon..." and "Reset".
- Preserved the active PowerShell host executable across UAC self-elevation via (Get-Process -Id $PID).Path and restricted -STA to Windows PowerShell 5.1.
- Fixed Add-Type compilation on PowerShell 7 (.NET 8+) by dynamically resolving loaded assembly locations for -ReferencedAssemblies.
- Forced foreground window activation (SW_SHOW + SetForegroundWindow) on form startup and ensured deterministic COM release before binary UAC patching.

v1.1.0:
- Hid the PowerShell console window when running this utility via hidden relaunch flags and Win32 ShowWindow fallback.
- Added a "Hidden" option to the Window dropdown to create shortcuts that execute target scripts with -WindowStyle Hidden (and start minimized to prevent window flash).
- Automatically disables -NoExit when "Hidden" is selected to prevent orphaned background PowerShell processes.
- Updated the live command preview to reflect -WindowStyle Hidden dynamically.

#>

# =======================================================================

# AUTO-ELEVATION, STA APARTMENT & HIDDEN CONSOLE CHECK

# =======================================================================

<#
.SYNOPSIS
    GUI Utility to Create Desktop Shortcuts for PowerShell Scripts (PS 5.1 & 7.x + Dark Mode + Auto-Elevating + Windowless)
.DESCRIPTION
    Self-elevates to Administrator in the active PowerShell runtime (with STA mode on PS 5.1) with its
    own console window hidden, automatically matches Windows 11 Dark/Light mode (with an in-app toggle),
    lets you browse for a .ps1 script, choose between PowerShell 5.1 and PowerShell 7.x (with automatic
    installation if missing), pick and preview a custom or Windows shell icon, configure launch flags,
    preview the exact command, and save the resulting .lnk shortcut directly to the Desktop.
#>

$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$isPS51  = ($PSVersionTable.PSVersion.Major -lt 6)
$isSTA   = ([Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA')

$currentHostExe = (Get-Process -Id $PID).Path
if ([string]::IsNullOrWhiteSpace($currentHostExe) -or -not (Test-Path -LiteralPath $currentHostExe)) {
    $currentHostExe = if ($isPS51) {
        Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
    } else {
        Join-Path -Path $PSHOME -ChildPath 'pwsh.exe'
    }
}

if (-not $isAdmin -or ($isPS51 -and -not $isSTA)) {
    $relaunchArgs = [System.Collections.Generic.List[string]]::new()
    $relaunchArgs.Add('-NoProfile')
    $relaunchArgs.Add('-ExecutionPolicy')
    $relaunchArgs.Add('Bypass')
    $relaunchArgs.Add('-WindowStyle')
    $relaunchArgs.Add('Hidden')
    if ($isPS51) {
        $relaunchArgs.Add('-STA')
    }
    $relaunchArgs.Add('-File')
    $relaunchArgs.Add("`"$PSCommandPath`"")

    $startParams = @{
        FilePath     = $currentHostExe
        ArgumentList = $relaunchArgs
        WindowStyle  = 'Hidden'
    }
    if (-not $isAdmin) {
        $startParams['Verb'] = 'RunAs'
    }

    Start-Process @startParams
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if ($PSVersionTable.PSEdition -eq 'Core') {
    try {
        if (([System.Windows.Forms.Application]).GetMethod('SetHighDpiMode')) {
            [void][System.Windows.Forms.Application]::SetHighDpiMode([System.Windows.Forms.HighDpiMode]::DpiUnawareGdiScaled)
        }
    }
    catch { }
}
try {
    [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
}
catch { }
[System.Windows.Forms.Application]::EnableVisualStyles()

# Win32 helpers for Console Hiding, DWM Dark Title Bar, Cue Banners, Shell Icon Picker, and Icon Extraction
if (-not ([System.Management.Automation.PSTypeName]'Win32ShellHelper').Type) {
    $refAssemblies = if ($PSVersionTable.PSEdition -eq 'Core') {
        [AppDomain]::CurrentDomain.GetAssemblies() |
            Where-Object { -not $_.IsDynamic -and -not [string]::IsNullOrWhiteSpace($_.Location) } |
            ForEach-Object { $_.Location } |
            Select-Object -Unique
    } else {
        @('System.Drawing')
    }

    Add-Type -ReferencedAssemblies $refAssemblies -TypeDefinition @"
using System;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

public static class Win32ShellHelper {
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    public static void HideConsoleWindow() {
        IntPtr hwnd = GetConsoleWindow();
        if (hwnd != IntPtr.Zero) {
            ShowWindow(hwnd, 0); // 0 = SW_HIDE
        }
    }

    [DllImport("dwmapi.dll", PreserveSig = true)]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

    public static void SetDarkTitleBar(IntPtr hwnd, bool enabled) {
        if (hwnd == IntPtr.Zero) return;
        int val = enabled ? 1 : 0;
        // 20 = DWMWA_USE_IMMERSIVE_DARK_MODE (Win10 20H1+ & Win11), 19 = older Win10 builds
        if (DwmSetWindowAttribute(hwnd, 20, ref val, sizeof(int)) != 0) {
            DwmSetWindowAttribute(hwnd, 19, ref val, sizeof(int));
        }
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, string lParam);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern int PickIconDlg(IntPtr hwndOwner, StringBuilder lpstrFile, int nMaxFile, ref int lpdwIconIndex);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern uint ExtractIconEx(string lpszFile, int nIconIndex, IntPtr[] phiconLarge, IntPtr[] phiconSmall, uint nIcons);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool DestroyIcon(IntPtr hIcon);

    public static Bitmap GetIconBitmap(string filePath, int index) {
        if (string.IsNullOrWhiteSpace(filePath)) return null;
        string expanded = Environment.ExpandEnvironmentVariables(filePath.Trim().Trim('"'));
        if (!File.Exists(expanded)) return null;

        IntPtr[] large = new IntPtr[1];
        IntPtr[] small = new IntPtr[1];
        uint count = ExtractIconEx(expanded, index, large, small, 1);

        if (count > 0 && large[0] != IntPtr.Zero) {
            try {
                using (Icon ico = Icon.FromHandle(large[0])) {
                    return ico.ToBitmap();
                }
            } finally {
                DestroyIcon(large[0]);
                if (small[0] != IntPtr.Zero) DestroyIcon(small[0]);
            }
        }
        if (small[0] != IntPtr.Zero) DestroyIcon(small[0]);

        if (expanded.EndsWith(".ico", StringComparison.OrdinalIgnoreCase)) {
            try {
                using (Icon ico = new Icon(expanded, 32, 32)) {
                    return ico.ToBitmap();
                }
            } catch { }
        }
        return null;
    }
}
"@
}

# Ensure the hosting console window is hidden even if launched from an already-elevated STA session
[Win32ShellHelper]::HideConsoleWindow()

function Get-Pwsh7Info {
    $foundPath = $null

    # 1. PowerShellCore InstalledVersions registry keys
    foreach ($root in @(
        'HKLM:\SOFTWARE\Microsoft\PowerShellCore\InstalledVersions',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\PowerShellCore\InstalledVersions'
    )) {
        if (Test-Path -LiteralPath $root) {
            $subKeys = Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | Sort-Object PSChildName -Descending
            foreach ($sub in $subKeys) {
                $props = Get-ItemProperty -LiteralPath $sub.PSPath -ErrorAction SilentlyContinue
                if ($null -ne $props -and -not [string]::IsNullOrWhiteSpace($props.InstallLocation)) {
                    $candidate = Join-Path -Path $props.InstallLocation -ChildPath 'pwsh.exe'
                    if (Test-Path -LiteralPath $candidate) {
                        $foundPath = $candidate
                        break
                    }
                }
            }
        }
        if ($foundPath) { break }
    }

    # 2. App Paths registry entries
    if (-not $foundPath) {
        foreach ($appPathKey in @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\pwsh.exe',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\pwsh.exe'
        )) {
            try {
                $appVal = (Get-ItemProperty -LiteralPath $appPathKey -ErrorAction Stop).'(default)'
                if (-not [string]::IsNullOrWhiteSpace($appVal)) {
                    $cleaned = $appVal.Trim('"')
                    if (Test-Path -LiteralPath $cleaned) {
                        $foundPath = $cleaned
                        break
                    }
                }
            } catch { }
        }
    }

    # 3. Standard MSI and MSIX (WindowsApps) install paths
    if (-not $foundPath) {
        $candidates = [System.Collections.Generic.List[string]]::new()
        if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
            $candidates.Add((Join-Path -Path $env:ProgramFiles -ChildPath 'PowerShell\7\pwsh.exe'))
        }
        if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
            $candidates.Add((Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath 'PowerShell\7\pwsh.exe'))
        }
        if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
            $candidates.Add((Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\WindowsApps\pwsh.exe'))
        }
        foreach ($candidate in $candidates) {
            if (Test-Path -LiteralPath $candidate) {
                $foundPath = $candidate
                break
            }
        }
    }

    # 4. PATH fallback
    if (-not $foundPath) {
        $cmd = Get-Command -Name 'pwsh.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $cmd -and (Test-Path -LiteralPath $cmd.Source)) {
            $foundPath = $cmd.Source
        }
    }

    if (-not $foundPath) {
        return $null
    }

    # Resolve real package executable for icon extraction when ExePath is an MSIX App Execution Alias
    $iconPath = $foundPath
    if ($foundPath -like '*\Microsoft\WindowsApps\pwsh.exe') {
        try {
            $pkg = Get-AppxPackage -Name 'Microsoft.PowerShell' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -ne $pkg -and -not [string]::IsNullOrWhiteSpace($pkg.InstallLocation)) {
                $realExe = Join-Path -Path $pkg.InstallLocation -ChildPath 'pwsh.exe'
                if (Test-Path -LiteralPath $realExe) {
                    $iconPath = $realExe
                }
            }
        } catch { }
    }

    return [PSCustomObject]@{
        ExePath  = $foundPath
        IconPath = $iconPath
    }
}

$script:ActiveTimers = [System.Collections.Generic.List[System.Windows.Forms.Timer]]::new()

function Invoke-AsyncTask {
    param(
        [Parameter(Mandatory)][scriptblock]$Work,
        [hashtable]$State = @{},
        [Parameter(Mandatory)][scriptblock]$OnComplete
    )

    $ps = [PowerShell]::Create()
    [void]$ps.AddScript($Work)
    $asyncResult = $ps.BeginInvoke()

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 120
    [void]$script:ActiveTimers.Add($timer)

    $timer.Add_Tick({
        if (-not $asyncResult.IsCompleted) { return }
        $timer.Stop()
        [void]$script:ActiveTimers.Remove($timer)

        $result = $null
        $errMsg = $null
        try {
            $output = $ps.EndInvoke($asyncResult)
            if ($ps.HadErrors -and $ps.Streams.Error.Count -gt 0) {
                $errMsg = $ps.Streams.Error[0].ToString()
            } elseif ($null -ne $output -and $output.Count -gt 0) {
                $result = $output[$output.Count - 1]
            }
        } catch {
            $errMsg = $_.Exception.Message
        } finally {
            $ps.Dispose()
            $timer.Dispose()
        }

        & $OnComplete $result $errMsg $State
    }.GetNewClosure())

    $timer.Start()
}

$ps5ExePath  = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
$ps5IconSpec = "$ps5ExePath,0"
$winShellDll = Join-Path -Path $env:SystemRoot -ChildPath 'System32\shell32.dll'
$desktopPath = [Environment]::GetFolderPath('Desktop')

# Detect Windows App Theme (0 = Dark Mode, 1 = Light Mode)
function Get-SystemDarkMode {
    try {
        $val = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'AppsUseLightTheme' -ErrorAction Stop).AppsUseLightTheme
        return ($val -eq 0)
    } catch {
        return $true
    }
}

$script:IsDarkMode = Get-SystemDarkMode
$script:StatusKind = 'Neutral'

$script:Themes = @{
    Dark = @{
        FormBg       = [System.Drawing.Color]::FromArgb(15, 23, 42)
        HeaderBg     = [System.Drawing.Color]::FromArgb(9, 14, 26)
        Accent       = [System.Drawing.Color]::FromArgb(56, 189, 248)
        PrimaryBtn   = [System.Drawing.Color]::FromArgb(2, 132, 199)
        SecBtnBg     = [System.Drawing.Color]::FromArgb(30, 41, 59)
        SecBtnBorder = [System.Drawing.Color]::FromArgb(71, 85, 105)
        InputBg      = [System.Drawing.Color]::FromArgb(30, 41, 59)
        PreviewBg    = [System.Drawing.Color]::FromArgb(22, 32, 50)
        PreviewFg    = [System.Drawing.Color]::FromArgb(186, 230, 253)
        TextPrimary  = [System.Drawing.Color]::FromArgb(241, 245, 249)
        TextMuted    = [System.Drawing.Color]::FromArgb(148, 163, 184)
        GroupTitle   = [System.Drawing.Color]::FromArgb(56, 189, 248)
        Border       = [System.Drawing.Color]::FromArgb(51, 65, 85)
        SuccessText  = [System.Drawing.Color]::FromArgb(74, 222, 128)
        WarningText  = [System.Drawing.Color]::FromArgb(250, 204, 21)
        ErrorText    = [System.Drawing.Color]::FromArgb(248, 113, 113)
    }
    Light = @{
        FormBg       = [System.Drawing.Color]::FromArgb(248, 250, 252)
        HeaderBg     = [System.Drawing.Color]::FromArgb(15, 23, 42)
        Accent       = [System.Drawing.Color]::FromArgb(56, 189, 248)
        PrimaryBtn   = [System.Drawing.Color]::FromArgb(2, 132, 199)
        SecBtnBg     = [System.Drawing.Color]::FromArgb(226, 232, 240)
        SecBtnBorder = [System.Drawing.Color]::FromArgb(148, 163, 184)
        InputBg      = [System.Drawing.Color]::White
        PreviewBg    = [System.Drawing.Color]::FromArgb(241, 245, 249)
        PreviewFg    = [System.Drawing.Color]::FromArgb(51, 65, 85)
        TextPrimary  = [System.Drawing.Color]::FromArgb(15, 23, 42)
        TextMuted    = [System.Drawing.Color]::FromArgb(100, 116, 139)
        GroupTitle   = [System.Drawing.Color]::FromArgb(2, 132, 199)
        Border       = [System.Drawing.Color]::FromArgb(203, 213, 225)
        SuccessText  = [System.Drawing.Color]::FromArgb(22, 163, 74)
        WarningText  = [System.Drawing.Color]::FromArgb(180, 120, 10)
        ErrorText    = [System.Drawing.Color]::FromArgb(220, 38, 38)
    }
}

# =======================================================================
# MAIN FORM & RESPONSIVE 3-ZONE LAYOUT
# =======================================================================
$fontUi = New-Object System.Drawing.Font('Segoe UI', 9.5)
$cmbItemHeight = [Math]::Max(19, [System.Windows.Forms.TextRenderer]::MeasureText('Ag', $fontUi).Height + 2)

$form = New-Object System.Windows.Forms.Form
$form.SuspendLayout()
$form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
$form.AutoScaleMode       = [System.Windows.Forms.AutoScaleMode]::Dpi
$form.Font                = $fontUi
$form.Text                = 'PowerShell Desktop Shortcut Creator (Administrator)'
$form.Size                = New-Object System.Drawing.Size(610, 638)
$form.MinimumSize         = New-Object System.Drawing.Size(460, 400)
$form.StartPosition       = 'CenterScreen'
$form.FormBorderStyle     = 'Sizable'
$form.MaximizeBox         = $false

# --- Top Header Banner ---
$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Dock   = 'Top'
$headerPanel.Height = 64

$accentBar = New-Object System.Windows.Forms.Panel
$accentBar.Dock   = 'Bottom'
$accentBar.Height = 3
$headerPanel.Controls.Add($accentBar)

$headerRight = New-Object System.Windows.Forms.Panel
$headerRight.Dock    = 'Right'
$headerRight.Width   = 118
$headerRight.Padding = New-Object System.Windows.Forms.Padding(6, 16, 16, 16)
$headerPanel.Controls.Add($headerRight)

$btnTheme = New-Object System.Windows.Forms.Button -Property @{
    Text      = 'Light Mode'
    Dock      = 'Fill'
    Font      = New-Object System.Drawing.Font('Segoe UI', 8.5)
    FlatStyle = 'Flat'
    Cursor    = [System.Windows.Forms.Cursors]::Hand
}
$btnTheme.FlatAppearance.BorderSize = 1
$headerRight.Controls.Add($btnTheme)

$headerLeft = New-Object System.Windows.Forms.Panel
$headerLeft.Dock    = 'Fill'
$headerLeft.Padding = New-Object System.Windows.Forms.Padding(18, 9, 6, 4)
$headerPanel.Controls.Add($headerLeft)

$lblSubtitle = New-Object System.Windows.Forms.Label -Property @{
    Text      = 'Browse to a .ps1 file, pick an icon, and configure how PowerShell runs it.'
    Dock      = 'Top'
    ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
    Font      = New-Object System.Drawing.Font('Segoe UI', 8.75)
    AutoSize  = $true
}
$headerLeft.Controls.Add($lblSubtitle)

$lblTitle = New-Object System.Windows.Forms.Label -Property @{
    Text      = 'PowerShell Desktop Shortcut Creator'
    Dock      = 'Top'
    ForeColor = [System.Drawing.Color]::FromArgb(248, 250, 252)
    Font      = New-Object System.Drawing.Font('Segoe UI Semibold', 12)
    AutoSize  = $true
}
$headerLeft.Controls.Add($lblTitle)
$lblSubtitle.BringToFront()

$accentBar.SendToBack()
$headerLeft.BringToFront()
$form.Controls.Add($headerPanel)

# --- Bottom Status & Action Buttons Bar ---
$pnlBottom = New-Object System.Windows.Forms.TableLayoutPanel
$pnlBottom.Dock         = 'Bottom'
$pnlBottom.AutoSize     = $true
$pnlBottom.AutoSizeMode = 'GrowAndShrink'
$pnlBottom.ColumnCount  = 2
$pnlBottom.RowCount     = 1
$pnlBottom.Padding      = New-Object System.Windows.Forms.Padding(16, 6, 16, 10)
[void]$pnlBottom.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$pnlBottom.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$pnlBottom.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$form.Controls.Add($pnlBottom)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text      = 'Select a PowerShell script to begin.'
$lblStatus.Dock      = 'Fill'
$lblStatus.TextAlign = 'MiddleLeft'
$lblStatus.Margin    = New-Object System.Windows.Forms.Padding(0, 2, 8, 2)
$pnlBottom.Controls.Add($lblStatus, 0, 0)

$flpBottomBtns = New-Object System.Windows.Forms.FlowLayoutPanel
$flpBottomBtns.Dock         = 'Right'
$flpBottomBtns.AutoSize     = $true
$flpBottomBtns.AutoSizeMode = 'GrowAndShrink'
$flpBottomBtns.WrapContents = $false
$flpBottomBtns.Margin       = New-Object System.Windows.Forms.Padding(0)
$pnlBottom.Controls.Add($flpBottomBtns, 1, 0)

$btnCreate = New-Object System.Windows.Forms.Button -Property @{
    Text      = 'Create Shortcut'
    Size      = New-Object System.Drawing.Size(124, 32)
    Enabled   = $false
    ForeColor = [System.Drawing.Color]::White
    FlatStyle = 'Flat'
    Cursor    = [System.Windows.Forms.Cursors]::Hand
    Margin    = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
}
$btnCreate.FlatAppearance.BorderSize = 0
$flpBottomBtns.Controls.Add($btnCreate)

$btnClose = New-Object System.Windows.Forms.Button -Property @{
    Text      = 'Close'
    Size      = New-Object System.Drawing.Size(76, 32)
    FlatStyle = 'Flat'
    Cursor    = [System.Windows.Forms.Cursors]::Hand
    Margin    = New-Object System.Windows.Forms.Padding(0)
}
$btnClose.FlatAppearance.BorderSize = 1
$flpBottomBtns.Controls.Add($btnClose)

# --- Pinned Command Preview Scroll Box ---
$pnlPreview = New-Object System.Windows.Forms.Panel
$pnlPreview.Dock    = 'Bottom'
$pnlPreview.Height  = 74
$pnlPreview.Padding = New-Object System.Windows.Forms.Padding(16, 4, 16, 4)
$form.Controls.Add($pnlPreview)

$txtPreview = New-Object System.Windows.Forms.TextBox -Property @{
    Dock        = 'Fill'
    Multiline   = $true
    ReadOnly    = $true
    ScrollBars  = 'Vertical'
    BorderStyle = 'FixedSingle'
    Font        = New-Object System.Drawing.Font('Consolas', 8.5)
}
$pnlPreview.Controls.Add($txtPreview)

$lblPreview = New-Object System.Windows.Forms.Label -Property @{
    Text     = 'Shortcut Target Command Preview:'
    Dock     = 'Top'
    AutoSize = $true
    Padding  = New-Object System.Windows.Forms.Padding(0, 0, 0, 3)
}
$pnlPreview.Controls.Add($lblPreview)
$txtPreview.BringToFront()

# --- Scrollable Middle Body (Inputs & Launch Options) ---
$pnlScroll = New-Object System.Windows.Forms.Panel
$pnlScroll.Dock       = 'Fill'
$pnlScroll.AutoScroll = $true
$pnlScroll.Padding    = New-Object System.Windows.Forms.Padding(16, 10, 16, 4)
$form.Controls.Add($pnlScroll)

# Enforce exact dock order: Header (Top), Bottom (Bottom), Preview (above Bottom), Scroll (Fill)
$headerPanel.BringToFront()
$pnlBottom.BringToFront()
$pnlPreview.BringToFront()
$pnlScroll.BringToFront()

$tlpMain = New-Object System.Windows.Forms.TableLayoutPanel
$tlpMain.Dock         = 'Top'
$tlpMain.AutoSize     = $true
$tlpMain.AutoSizeMode = 'GrowAndShrink'
$tlpMain.ColumnCount  = 1
[void]$tlpMain.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$pnlScroll.Controls.Add($tlpMain)

$pnlScroll.Add_SizeChanged({
    $avail = [Math]::Max(200, $pnlScroll.ClientSize.Width - $pnlScroll.Padding.Horizontal)
    $tlpMain.MaximumSize = New-Object System.Drawing.Size($avail, 0)
})

# 1. Target Script Selection
$lblScript = New-Object System.Windows.Forms.Label -Property @{
    Text     = 'PowerShell Script (.ps1):'
    AutoSize = $true
    Margin   = New-Object System.Windows.Forms.Padding(0, 0, 0, 2)
}
$tlpMain.Controls.Add($lblScript)

$tlpScript = New-Object System.Windows.Forms.TableLayoutPanel
$tlpScript.Dock         = 'Top'
$tlpScript.AutoSize     = $true
$tlpScript.AutoSizeMode = 'GrowAndShrink'
$tlpScript.ColumnCount  = 2
$tlpScript.Margin       = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
[void]$tlpScript.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$tlpScript.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
$tlpMain.Controls.Add($tlpScript)

$txtScriptPath = New-Object System.Windows.Forms.TextBox -Property @{
    Dock        = 'Fill'
    BorderStyle = 'FixedSingle'
    Margin      = New-Object System.Windows.Forms.Padding(0, 1, 8, 1)
}
$tlpScript.Controls.Add($txtScriptPath, 0, 0)

$btnBrowse = New-Object System.Windows.Forms.Button -Property @{
    Text      = 'Browse...'
    Size      = New-Object System.Drawing.Size(88, 26)
    FlatStyle = 'Flat'
    Cursor    = [System.Windows.Forms.Cursors]::Hand
    Margin    = New-Object System.Windows.Forms.Padding(0)
}
$btnBrowse.FlatAppearance.BorderSize = 1
$tlpScript.Controls.Add($btnBrowse, 1, 0)

# 2. Shortcut Name
$lblName = New-Object System.Windows.Forms.Label -Property @{
    Text     = 'Desktop Shortcut Name:'
    AutoSize = $true
    Margin   = New-Object System.Windows.Forms.Padding(0, 0, 0, 2)
}
$tlpMain.Controls.Add($lblName)

$txtShortcutName = New-Object System.Windows.Forms.TextBox -Property @{
    Dock        = 'Top'
    BorderStyle = 'FixedSingle'
    Margin      = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
}
$tlpMain.Controls.Add($txtShortcutName)

# 3. Custom Icon Picker & Live Preview
$lblIcon = New-Object System.Windows.Forms.Label -Property @{
    Text     = 'Shortcut Icon (.ico, .exe, .dll):'
    AutoSize = $true
    Margin   = New-Object System.Windows.Forms.Padding(0, 0, 0, 2)
}
$tlpMain.Controls.Add($lblIcon)

$tlpIcon = New-Object System.Windows.Forms.TableLayoutPanel
$tlpIcon.Dock         = 'Top'
$tlpIcon.AutoSize     = $true
$tlpIcon.AutoSizeMode = 'GrowAndShrink'
$tlpIcon.ColumnCount  = 3
$tlpIcon.Margin       = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
[void]$tlpIcon.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$tlpIcon.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$tlpIcon.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
$tlpMain.Controls.Add($tlpIcon)

$pnlIconBox = New-Object System.Windows.Forms.Panel -Property @{
    Size        = New-Object System.Drawing.Size(42, 42)
    BorderStyle = 'FixedSingle'
    Margin      = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
}
$tlpIcon.Controls.Add($pnlIconBox, 0, 0)

$picIcon = New-Object System.Windows.Forms.PictureBox -Property @{
    Location = New-Object System.Drawing.Point(4, 4)
    Size     = New-Object System.Drawing.Size(32, 32)
    SizeMode = 'Zoom'
}
$pnlIconBox.Controls.Add($picIcon)

$txtIconPath = New-Object System.Windows.Forms.TextBox -Property @{
    Dock        = 'Fill'
    Text        = $ps5IconSpec
    BorderStyle = 'FixedSingle'
    Margin      = New-Object System.Windows.Forms.Padding(0, 9, 8, 8)
}
$tlpIcon.Controls.Add($txtIconPath, 1, 0)

$flpIconBtns = New-Object System.Windows.Forms.FlowLayoutPanel
$flpIconBtns.AutoSize     = $true
$flpIconBtns.AutoSizeMode = 'GrowAndShrink'
$flpIconBtns.WrapContents = $false
$flpIconBtns.Margin       = New-Object System.Windows.Forms.Padding(0, 7, 0, 0)
$tlpIcon.Controls.Add($flpIconBtns, 2, 0)

$btnBrowseIcon = New-Object System.Windows.Forms.Button -Property @{
    Text      = 'Choose Icon...'
    Size      = New-Object System.Drawing.Size(98, 27)
    FlatStyle = 'Flat'
    Cursor    = [System.Windows.Forms.Cursors]::Hand
    Margin    = New-Object System.Windows.Forms.Padding(0, 0, 4, 0)
}
$btnBrowseIcon.FlatAppearance.BorderSize = 1
$flpIconBtns.Controls.Add($btnBrowseIcon)

$btnWinIcon = New-Object System.Windows.Forms.Button -Property @{
    Text      = 'Windows Icons...'
    Size      = New-Object System.Drawing.Size(110, 27)
    FlatStyle = 'Flat'
    Cursor    = [System.Windows.Forms.Cursors]::Hand
    Margin    = New-Object System.Windows.Forms.Padding(0, 0, 4, 0)
}
$btnWinIcon.FlatAppearance.BorderSize = 1
$flpIconBtns.Controls.Add($btnWinIcon)

$btnResetIcon = New-Object System.Windows.Forms.Button -Property @{
    Text      = 'Reset'
    Size      = New-Object System.Drawing.Size(56, 27)
    FlatStyle = 'Flat'
    Cursor    = [System.Windows.Forms.Cursors]::Hand
    Margin    = New-Object System.Windows.Forms.Padding(0)
}
$btnResetIcon.FlatAppearance.BorderSize = 1
$flpIconBtns.Controls.Add($btnResetIcon)

# 4. Execution Options Group (Custom-painted for clean dark borders)
$grpOptions = New-Object System.Windows.Forms.GroupBox -Property @{
    Text         = 'PowerShell Launch Options'
    Dock         = 'Top'
    AutoSize     = $true
    AutoSizeMode = 'GrowAndShrink'
    Padding      = New-Object System.Windows.Forms.Padding(12, 20, 12, 8)
    Margin       = New-Object System.Windows.Forms.Padding(0, 0, 0, 2)
}
$tlpMain.Controls.Add($grpOptions)

$grpOptions.Add_Paint({
    param($sender, $e)
    $t = if ($script:IsDarkMode) { $script:Themes.Dark } else { $script:Themes.Light }
    $e.Graphics.Clear($sender.BackColor)
    $textSize = $e.Graphics.MeasureString($sender.Text, $sender.Font)
    $topOffset = [int]($textSize.Height / 2)
    $borderRect = New-Object System.Drawing.Rectangle(0, $topOffset, ($sender.Width - 1), ($sender.Height - $topOffset - 1))

    $pen = New-Object System.Drawing.Pen($t.Border)
    $e.Graphics.DrawRectangle($pen, $borderRect)
    $pen.Dispose()

    $textRect = New-Object System.Drawing.Rectangle(10, 0, ([int]$textSize.Width + 6), ([int]$textSize.Height + 2))
    $bgBrush = New-Object System.Drawing.SolidBrush($sender.BackColor)
    $e.Graphics.FillRectangle($bgBrush, $textRect)
    $bgBrush.Dispose()

    $fgBrush = New-Object System.Drawing.SolidBrush($t.GroupTitle)
    $e.Graphics.DrawString($sender.Text, $sender.Font, $fgBrush, 12, 0)
    $fgBrush.Dispose()
})

$tlpOpts = New-Object System.Windows.Forms.TableLayoutPanel
$tlpOpts.Dock         = 'Top'
$tlpOpts.AutoSize     = $true
$tlpOpts.AutoSizeMode = 'GrowAndShrink'
$tlpOpts.ColumnCount  = 1
[void]$tlpOpts.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$grpOptions.Controls.Add($tlpOpts)

$flpModeRow = New-Object System.Windows.Forms.FlowLayoutPanel
$flpModeRow.Dock         = 'Top'
$flpModeRow.AutoSize     = $true
$flpModeRow.AutoSizeMode = 'GrowAndShrink'
$flpModeRow.WrapContents = $true
$flpModeRow.Margin       = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)
$tlpOpts.Controls.Add($flpModeRow)

$lblMode = New-Object System.Windows.Forms.Label -Property @{
    Text     = 'PowerShell Mode:'
    AutoSize = $true
    Margin   = New-Object System.Windows.Forms.Padding(0, 5, 8, 2)
}
$flpModeRow.Controls.Add($lblMode)

$cmbMode = New-Object System.Windows.Forms.ComboBox
$cmbMode.Width         = 212
$cmbMode.DropDownStyle = 'DropDownList'
$cmbMode.DrawMode      = 'OwnerDrawFixed'
$cmbMode.FlatStyle     = 'Flat'
$cmbMode.ItemHeight    = $cmbItemHeight
$cmbMode.Margin        = New-Object System.Windows.Forms.Padding(0, 1, 10, 2)
[void]$cmbMode.Items.AddRange(@('PowerShell 5.1 (powershell.exe)', 'PowerShell 7.x (pwsh.exe)'))
$cmbMode.SelectedIndex = if (-not $isPS51 -and $null -ne (Get-Pwsh7Info)) { 1 } else { 0 }
$flpModeRow.Controls.Add($cmbMode)

$lblModeStatus = New-Object System.Windows.Forms.Label -Property @{
    Text     = ''
    AutoSize = $true
    Margin   = New-Object System.Windows.Forms.Padding(0, 5, 0, 2)
}
$flpModeRow.Controls.Add($lblModeStatus)

$flpRunAsRow = New-Object System.Windows.Forms.FlowLayoutPanel
$flpRunAsRow.Dock         = 'Top'
$flpRunAsRow.AutoSize     = $true
$flpRunAsRow.AutoSizeMode = 'GrowAndShrink'
$flpRunAsRow.WrapContents = $true
$flpRunAsRow.Margin       = New-Object System.Windows.Forms.Padding(0, 0, 0, 2)
$tlpOpts.Controls.Add($flpRunAsRow)

$chkRunAs = New-Object System.Windows.Forms.CheckBox -Property @{
    Text     = 'Run as Administrator (UAC prompt on launch)'
    AutoSize = $true
    Margin   = New-Object System.Windows.Forms.Padding(0, 4, 14, 2)
}
$flpRunAsRow.Controls.Add($chkRunAs)

$lblWindow = New-Object System.Windows.Forms.Label -Property @{
    Text     = 'Window:'
    AutoSize = $true
    Margin   = New-Object System.Windows.Forms.Padding(0, 5, 6, 2)
}
$flpRunAsRow.Controls.Add($lblWindow)

$cmbWindow = New-Object System.Windows.Forms.ComboBox
$cmbWindow.Width         = 108
$cmbWindow.DropDownStyle = 'DropDownList'
$cmbWindow.DrawMode      = 'OwnerDrawFixed'
$cmbWindow.FlatStyle     = 'Flat'
$cmbWindow.ItemHeight    = $cmbItemHeight
$cmbWindow.Margin        = New-Object System.Windows.Forms.Padding(0, 1, 0, 2)
[void]$cmbWindow.Items.AddRange(@('Normal', 'Minimized', 'Maximized', 'Hidden'))
$cmbWindow.SelectedIndex = 0
$flpRunAsRow.Controls.Add($cmbWindow)

$drawComboItem = {
    param($sender, $e)
    if ($e.Index -lt 0) { return }
    $t = if ($script:IsDarkMode) { $script:Themes.Dark } else { $script:Themes.Light }
    $isSelected = ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -eq [System.Windows.Forms.DrawItemState]::Selected
    $bgColor = if ($isSelected) { $t.PrimaryBtn } else { $t.InputBg }
    $fgColor = if ($isSelected) { [System.Drawing.Color]::White } else { $t.TextPrimary }

    $bgBrush = New-Object System.Drawing.SolidBrush($bgColor)
    $fgBrush = New-Object System.Drawing.SolidBrush($fgColor)
    $e.Graphics.FillRectangle($bgBrush, $e.Bounds)
    $yPos = [Math]::Max(1, [int](($e.Bounds.Height - $sender.Font.Height) / 2))
    $e.Graphics.DrawString($sender.Items[$e.Index].ToString(), $sender.Font, $fgBrush, ($e.Bounds.X + 4), ($e.Bounds.Y + $yPos))
    $bgBrush.Dispose()
    $fgBrush.Dispose()
}

$cmbMode.Add_DrawItem($drawComboItem)
$cmbWindow.Add_DrawItem($drawComboItem)

$chkNoExit = New-Object System.Windows.Forms.CheckBox -Property @{
    Text     = 'Keep PowerShell window open after script finishes (-NoExit)'
    AutoSize = $true
    Margin   = New-Object System.Windows.Forms.Padding(0, 1, 0, 2)
}
$tlpOpts.Controls.Add($chkNoExit)

$chkBypass = New-Object System.Windows.Forms.CheckBox -Property @{
    Text     = 'Bypass Execution Policy (-ExecutionPolicy Bypass)'
    Checked  = $true
    AutoSize = $true
    Margin   = New-Object System.Windows.Forms.Padding(0, 1, 0, 4)
}
$tlpOpts.Controls.Add($chkBypass)

$tlpArgs = New-Object System.Windows.Forms.TableLayoutPanel
$tlpArgs.Dock         = 'Top'
$tlpArgs.AutoSize     = $true
$tlpArgs.AutoSizeMode = 'GrowAndShrink'
$tlpArgs.ColumnCount  = 2
$tlpArgs.Margin       = New-Object System.Windows.Forms.Padding(0)
[void]$tlpArgs.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$tlpArgs.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$tlpOpts.Controls.Add($tlpArgs)

$lblArgs = New-Object System.Windows.Forms.Label -Property @{
    Text     = 'Script Arguments (optional):'
    AutoSize = $true
    Margin   = New-Object System.Windows.Forms.Padding(0, 4, 8, 2)
}
$tlpArgs.Controls.Add($lblArgs, 0, 0)

$txtArgs = New-Object System.Windows.Forms.TextBox -Property @{
    Dock        = 'Fill'
    BorderStyle = 'FixedSingle'
    Margin      = New-Object System.Windows.Forms.Padding(0, 1, 0, 1)
}
$tlpArgs.Controls.Add($txtArgs, 1, 0)

$form.ResumeLayout($false)
$form.PerformLayout()

$form.Add_Load({
    $wa   = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $maxW = [Math]::Max(420, $wa.Width - 20)
    $maxH = [Math]::Max(340, $wa.Height - 20)

    $form.PerformLayout()
    $availW = [Math]::Max(200, $pnlScroll.ClientSize.Width - $pnlScroll.Padding.Horizontal)
    $tlpMain.MaximumSize = New-Object System.Drawing.Size($availW, 0)
    $form.PerformLayout()

    $needScrollH = $tlpMain.Height + $pnlScroll.Padding.Vertical
    $overflow    = $needScrollH - $pnlScroll.ClientSize.Height
    $targetH     = if ($overflow -gt 0) { $form.Height + $overflow + 6 } else { $form.Height }

    $form.MinimumSize = New-Object System.Drawing.Size(
        [Math]::Min($form.MinimumSize.Width, $maxW),
        [Math]::Min($form.MinimumSize.Height, $maxH)
    )
    $form.Size = New-Object System.Drawing.Size(
        [Math]::Min($form.Width, $maxW),
        [Math]::Min($targetH, $maxH)
    )
})

# =======================================================================
# THEME ENGINE & SHORTCUT LOGIC
# =======================================================================
$getDefaultIconForMode = {
    if ($cmbMode.SelectedIndex -eq 1) {
        $info = Get-Pwsh7Info
        if ($null -ne $info -and -not [string]::IsNullOrWhiteSpace($info.IconPath)) {
            return "$($info.IconPath),0"
        }
    }
    return $ps5IconSpec
}

$resolveIcon = {
    param([string]$Spec)
    $fallback = & $getDefaultIconForMode
    $raw   = if ([string]::IsNullOrWhiteSpace($Spec)) { $fallback } else { $Spec.Trim() }
    $file  = $raw
    $index = 0
    if ($raw -match '^(.*),\s*(-?\d+)$') {
        $file  = $Matches[1].Trim().Trim('"')
        $index = [int]$Matches[2]
    }
    else {
        $file = $raw.Trim('"')
    }
    $expanded = [Environment]::ExpandEnvironmentVariables($file)
    [PSCustomObject]@{ File = $expanded; Index = $index; Spec = "$expanded,$index" }
}

$refreshIcon = {
    $parsed = & $resolveIcon $txtIconPath.Text
    $bmp = [Win32ShellHelper]::GetIconBitmap($parsed.File, $parsed.Index)
    $old = $picIcon.Image
    $picIcon.Image = $bmp
    if ($null -ne $old) { $old.Dispose() }
}

$buildArgs = {
    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add('-NoProfile')
    if ($cmbMode.SelectedIndex -eq 0) { $parts.Add('-STA') }
    if ($chkBypass.Checked) { $parts.Add('-ExecutionPolicy Bypass') }
    if ($cmbWindow.SelectedItem -eq 'Hidden') { $parts.Add('-WindowStyle Hidden') }
    if ($chkNoExit.Checked) { $parts.Add('-NoExit') }
    $target = $txtScriptPath.Text.Trim()
    if (-not [string]::IsNullOrWhiteSpace($target)) { $parts.Add("-File `"$target`"") }
    if (-not [string]::IsNullOrWhiteSpace($txtArgs.Text)) { $parts.Add($txtArgs.Text.Trim()) }
    return ($parts -join ' ')
}

$refreshModeStatus = {
    $t = if ($script:IsDarkMode) { $script:Themes.Dark } else { $script:Themes.Light }
    if ($cmbMode.SelectedIndex -eq 0) {
        $lblModeStatus.ForeColor = $t.TextMuted
        $lblModeStatus.Text      = 'Built-in (Windows)'
    }
    else {
        $info = Get-Pwsh7Info
        if ($null -ne $info) {
            $lblModeStatus.ForeColor = $t.SuccessText
            $lblModeStatus.Text      = 'Installed (Ready)'
        }
        else {
            $lblModeStatus.ForeColor = $t.WarningText
            $lblModeStatus.Text      = 'Not installed'
        }
    }
}

$refreshState = {
    $path = $txtScriptPath.Text.Trim()
    $valid = (-not [string]::IsNullOrWhiteSpace($path)) -and (Test-Path -LiteralPath $path -PathType Leaf)
    $btnCreate.Enabled = $valid

    $previewExe = if ($cmbMode.SelectedIndex -eq 1) {
        $info = Get-Pwsh7Info
        if ($null -ne $info) { $info.ExePath } else { 'pwsh.exe' }
    }
    else {
        $ps5ExePath
    }
    $txtPreview.Text = if ($valid) { "`"$previewExe`" $(& $buildArgs)" } else { '' }
}

function Apply-StatusStyle {
    $t = if ($script:IsDarkMode) { $script:Themes.Dark } else { $script:Themes.Light }
    $lblStatus.ForeColor = switch ($script:StatusKind) {
        'Success' { $t.SuccessText }
        'Warning' { $t.WarningText }
        'Error'   { $t.ErrorText }
        default   { $t.TextMuted }
    }
}

function Apply-Theme {
    $t = if ($script:IsDarkMode) { $script:Themes.Dark } else { $script:Themes.Light }

    if ($form.IsHandleCreated) {
        [Win32ShellHelper]::SetDarkTitleBar($form.Handle, $script:IsDarkMode)
    }

    $form.BackColor        = $t.FormBg
    $headerPanel.BackColor = $t.HeaderBg
    $headerLeft.BackColor  = $t.HeaderBg
    $headerRight.BackColor = $t.HeaderBg
    $accentBar.BackColor   = $t.Accent

    foreach ($pnl in @($pnlBottom, $flpBottomBtns, $pnlPreview, $pnlScroll, $tlpMain, $tlpScript, $tlpIcon, $flpIconBtns, $tlpOpts, $flpModeRow, $flpRunAsRow, $tlpArgs)) {
        $pnl.BackColor = $t.FormBg
    }

    $btnTheme.Text      = if ($script:IsDarkMode) { 'Light Mode' } else { 'Dark Mode' }
    $btnTheme.BackColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
    $btnTheme.ForeColor = [System.Drawing.Color]::FromArgb(226, 232, 240)
    $btnTheme.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(71, 85, 105)

    foreach ($lbl in @($lblScript, $lblName, $lblIcon, $lblPreview, $lblMode, $lblWindow, $lblArgs)) {
        $lbl.ForeColor = $t.TextPrimary
    }

    foreach ($chk in @($chkRunAs, $chkNoExit, $chkBypass)) {
        $chk.ForeColor = $t.TextPrimary
        $chk.BackColor = $t.FormBg
    }

    foreach ($tb in @($txtScriptPath, $txtShortcutName, $txtIconPath, $txtArgs)) {
        $tb.BackColor = $t.InputBg
        $tb.ForeColor = $t.TextPrimary
    }

    $pnlIconBox.BackColor = $t.InputBg
    $txtPreview.BackColor = $t.PreviewBg
    $txtPreview.ForeColor = $t.PreviewFg

    foreach ($cmb in @($cmbMode, $cmbWindow)) {
        $cmb.BackColor = $t.InputBg
        $cmb.ForeColor = $t.TextPrimary
        $cmb.Invalidate()
    }

    $btnCreate.BackColor  = $t.PrimaryBtn
    $btnCreate.ForeColor  = [System.Drawing.Color]::White

    foreach ($btn in @($btnBrowse, $btnBrowseIcon, $btnWinIcon, $btnResetIcon, $btnClose)) {
        $btn.BackColor = $t.SecBtnBg
        $btn.ForeColor = $t.TextPrimary
        $btn.FlatAppearance.BorderColor = $t.SecBtnBorder
    }

    $grpOptions.BackColor = $t.FormBg
    $grpOptions.Invalidate()
    & $refreshModeStatus
    Apply-StatusStyle
}

$writeShortcutFile = {
    param(
        [string]$TargetExePath,
        [string]$ShortcutFilePath,
        [string]$ScriptFilePath,
        [string]$IconSpec,
        [string]$ModeLabel
    )

    $wsh = New-Object -ComObject WScript.Shell
    $lnk = $null
    try {
        $lnk = $wsh.CreateShortcut($ShortcutFilePath)
        $lnk.TargetPath       = $TargetExePath
        $lnk.Arguments        = (& $buildArgs)
        $lnk.WorkingDirectory = Split-Path -Path $ScriptFilePath -Parent
        $lnk.IconLocation     = $IconSpec
        $lnk.WindowStyle      = switch ($cmbWindow.SelectedItem) {
            'Normal'    { 1 }
            'Minimized' { 7 }
            'Maximized' { 3 }
            'Hidden'    { 7 }
            default     { 1 }
        }
        $lnk.Description = "Run $(Split-Path -Path $ScriptFilePath -Leaf) via $ModeLabel"
        $lnk.Save()
    }
    finally {
        if ($null -ne $lnk) {
            [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($lnk)
        }
        if ($null -ne $wsh) {
            [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh)
        }
    }

    if ($chkRunAs.Checked) {
        $bytes = [System.IO.File]::ReadAllBytes($ShortcutFilePath)
        $bytes[21] = $bytes[21] -bor 0x20
        [System.IO.File]::WriteAllBytes($ShortcutFilePath, $bytes)
    }
}

$startPwsh7Install = {
    param(
        [bool]$CreateAfterInstall,
        [string]$ShortcutPath,
        [string]$ScriptPath,
        [string]$CleanName,
        [string]$IconSpec
    )

    $btnCreate.Enabled  = $false
    $btnClose.Enabled   = $false
    $btnBrowse.Enabled  = $false
    $cmbMode.Enabled    = $false
    $script:StatusKind  = 'Warning'
    $lblStatus.Text     = 'Installing PowerShell 7.x... Please wait.'
    Apply-StatusStyle

    $installWork = {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        # 1. Try winget first when available
        $wingetCmd = Get-Command -Name 'winget.exe' -ErrorAction SilentlyContinue
        if ($null -ne $wingetCmd) {
            $wgArgs = 'install --id Microsoft.PowerShell --exact --source winget --accept-package-agreements --accept-source-agreements --silent'
            $proc = Start-Process -FilePath $wingetCmd.Source -ArgumentList $wgArgs -Wait -PassThru -WindowStyle Hidden
            if ($proc.ExitCode -eq 0) {
                return 'winget'
            }
        }

        # 2. Fallback: Download latest official PowerShell 7 MSI from GitHub and install
        $arch    = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'win-arm64.msi' } else { 'win-x64.msi' }
        $headers = @{ 'User-Agent' = 'PowerShell-Desktop-Shortcut-Creator' }
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest' -Headers $headers -TimeoutSec 25 -ErrorAction Stop
        $asset   = $release.assets | Where-Object { $_.name -like "*$arch" } | Select-Object -First 1
        if ($null -eq $asset) {
            throw "No matching PowerShell 7 installer ($arch) was found on GitHub."
        }

        $msiPath = Join-Path -Path $env:TEMP -ChildPath $asset.name
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $msiPath -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop

        $msiArgs = "/i `"$msiPath`" /passive ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1 USE_MU=1 ENABLE_MU=1"
        $msiProc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru
        Remove-Item -LiteralPath $msiPath -Force -ErrorAction SilentlyContinue

        if ($msiProc.ExitCode -ne 0 -and $msiProc.ExitCode -ne 3010) {
            throw "PowerShell 7 installer exited with code $($msiProc.ExitCode)."
        }
        return 'msi'
    }

    $state = @{
        CreateAfterInstall = $CreateAfterInstall
        ShortcutPath       = $ShortcutPath
        ScriptPath         = $ScriptPath
        CleanName          = $CleanName
        IconSpec           = $IconSpec
    }

    Invoke-AsyncTask -Work $installWork -State $state -OnComplete {
        param($res, $err, $st)
        if ($form.IsDisposed) { return }

        $btnClose.Enabled  = $true
        $btnBrowse.Enabled = $true
        $cmbMode.Enabled   = $true
        & $refreshState

        if ($err) {
            & $refreshModeStatus
            $script:StatusKind = 'Error'
            $lblStatus.Text = "Install failed: $err"
            Apply-StatusStyle
            [void][System.Windows.Forms.MessageBox]::Show($form, "PowerShell 7 installation failed:`n$err", 'Installation Error', 'OK', 'Error')
            return
        }

        $installedInfo = Get-Pwsh7Info
        if ($null -eq $installedInfo) {
            & $refreshModeStatus
            $script:StatusKind = 'Error'
            $lblStatus.Text = 'PowerShell 7 installed, but pwsh.exe was not found.'
            Apply-StatusStyle
            [void][System.Windows.Forms.MessageBox]::Show($form, 'PowerShell 7 finished installing, but pwsh.exe could not be located automatically. Click Create Shortcut again to retry.', 'Detection Needed', 'OK', 'Warning')
            return
        }

        # Upgrade default PS 5.1 icon to the new PS 7 icon if user hadn't chosen a custom icon
        $finalIconSpec = $st.IconSpec
        if ([string]::IsNullOrWhiteSpace($finalIconSpec) -or ($finalIconSpec -ieq $ps5IconSpec)) {
            $finalIconSpec = "$($installedInfo.IconPath),0"
            $txtIconPath.Text = $finalIconSpec
        }

        & $refreshModeStatus
        & $refreshState

        if ($st.CreateAfterInstall) {
            try {
                & $writeShortcutFile $installedInfo.ExePath $st.ShortcutPath $st.ScriptPath $finalIconSpec 'PowerShell 7.x'
                $script:StatusKind = 'Success'
                $lblStatus.Text = "Installed PowerShell 7.x and created '$($st.CleanName).lnk'."
                Apply-StatusStyle
            }
            catch {
                $script:StatusKind = 'Error'
                $lblStatus.Text = "Installed PS 7, but shortcut failed: $($_.Exception.Message)"
                Apply-StatusStyle
            }
        }
        else {
            $script:StatusKind = 'Success'
            $lblStatus.Text = 'PowerShell 7.x installed. Ready to create shortcut.'
            Apply-StatusStyle
        }
    }
}

# =======================================================================
# EVENT HANDLERS
# =======================================================================
$cmbMode.Add_SelectedIndexChanged({
    $isPs7 = ($cmbMode.SelectedIndex -eq 1)
    $curIcon = $txtIconPath.Text.Trim()

    if ($isPs7) {
        $info = Get-Pwsh7Info
        if ($null -ne $info) {
            if ([string]::IsNullOrWhiteSpace($curIcon) -or ($curIcon -ieq $ps5IconSpec)) {
                $txtIconPath.Text = "$($info.IconPath),0"
            }
        }
        else {
            & $refreshModeStatus
            & $refreshState
            $askNow = [System.Windows.Forms.MessageBox]::Show(
                $form,
                "PowerShell 7.x (pwsh.exe) is not currently installed on this PC.`n`nWould you like to download and install PowerShell 7 now?",
                'PowerShell 7.x Not Installed',
                'YesNo',
                'Question'
            )
            if ($askNow -eq 'Yes') {
                & $startPwsh7Install $false '' '' '' $txtIconPath.Text
            }
            return
        }
    }
    else {
        if ([string]::IsNullOrWhiteSpace($curIcon) -or ($curIcon -match '\\pwsh\.exe,0$')) {
            $txtIconPath.Text = $ps5IconSpec
        }
    }

    & $refreshModeStatus
    & $refreshState
})

$btnBrowse.Add_Click({
    $initDir = $desktopPath
    $currentText = $txtScriptPath.Text.Trim()
    if (-not [string]::IsNullOrWhiteSpace($currentText)) {
        if (Test-Path -LiteralPath $currentText -PathType Container) {
            $initDir = $currentText
        } elseif (Test-Path -LiteralPath $currentText -PathType Leaf) {
            $initDir = Split-Path -Path $currentText -Parent
        }
    }

    $dlg = New-Object System.Windows.Forms.OpenFileDialog -Property @{
        Title            = 'Select a PowerShell Script (.ps1)'
        Filter           = 'PowerShell Scripts (*.ps1)|*.ps1|All Files (*.*)|*.*'
        InitialDirectory = $initDir
        CheckFileExists  = $true
        Multiselect      = $false
    }
    if ($dlg.ShowDialog($form) -eq 'OK') {
        $txtScriptPath.Text   = $dlg.FileName
        $txtShortcutName.Text = [System.IO.Path]::GetFileNameWithoutExtension($dlg.FileName)
        $script:StatusKind    = 'Neutral'
        $lblStatus.Text       = 'Ready to create Desktop shortcut.'
        Apply-StatusStyle
        & $refreshState
    }
    $dlg.Dispose()
})

$openIconPickerForFile = {
    param([string]$SeedPath, [int]$SeedIndex)
    $sb = New-Object System.Text.StringBuilder(260)
    [void]$sb.Append($SeedPath)
    $idx = [int]$SeedIndex
    if ([Win32ShellHelper]::PickIconDlg($form.Handle, $sb, $sb.Capacity, [ref]$idx) -ne 0) {
        $txtIconPath.Text = "$([Environment]::ExpandEnvironmentVariables($sb.ToString())),$idx"
    }
}

$btnBrowseIcon.Add_Click({
    $parsed   = & $resolveIcon $txtIconPath.Text
    $pwshInfo = if ($cmbMode.SelectedIndex -eq 1) { Get-Pwsh7Info } else { $null }
    $fallback = if ($null -ne $pwshInfo) { $pwshInfo.IconPath } else { $ps5ExePath }
    $seedFile = if (Test-Path -LiteralPath $parsed.File) { $parsed.File } else { $fallback }
    $seedIdx  = if (Test-Path -LiteralPath $parsed.File) { $parsed.Index } else { 0 }
    & $openIconPickerForFile $seedFile $seedIdx
})

$btnWinIcon.Add_Click({
    & $openIconPickerForFile $winShellDll 0
})

$btnResetIcon.Add_Click({ $txtIconPath.Text = (& $getDefaultIconForMode) })
$txtIconPath.Add_TextChanged({ & $refreshIcon })
$txtScriptPath.Add_TextChanged({ & $refreshState })
$chkBypass.Add_CheckedChanged({ & $refreshState })
$chkNoExit.Add_CheckedChanged({ & $refreshState })
$txtArgs.Add_TextChanged({ & $refreshState })

$cmbWindow.Add_SelectedIndexChanged({
    if ($cmbWindow.SelectedItem -eq 'Hidden') {
        $chkNoExit.Checked = $false
        $chkNoExit.Enabled = $false
    }
    else {
        $chkNoExit.Enabled = $true
    }
    & $refreshState
})

$btnCreate.Add_Click({
    try {
        $scriptPath = $txtScriptPath.Text.Trim()
        if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
            $script:StatusKind = 'Error'
            $lblStatus.Text = 'Error: The selected script file does not exist.'
            Apply-StatusStyle
            return
        }
        $iconInfo = & $resolveIcon $txtIconPath.Text
        if (-not (Test-Path -LiteralPath $iconInfo.File)) {
            $script:StatusKind = 'Error'
            $lblStatus.Text = 'Error: The selected icon file does not exist.'
            Apply-StatusStyle
            return
        }

        $rawName = if ([string]::IsNullOrWhiteSpace($txtShortcutName.Text)) {
            [System.IO.Path]::GetFileNameWithoutExtension($scriptPath)
        } else {
            $txtShortcutName.Text.Trim()
        }
        $invalidRegex = [Regex]::Escape(([System.IO.Path]::GetInvalidFileNameChars() -join ''))
        $cleanName = ($rawName -replace "[$invalidRegex]", '').Trim()
        if ([string]::IsNullOrWhiteSpace($cleanName)) {
            $cleanName = [System.IO.Path]::GetFileNameWithoutExtension($scriptPath)
        }
        $txtShortcutName.Text = $cleanName

        $shortcutPath = Join-Path -Path $desktopPath -ChildPath "$cleanName.lnk"
        if (Test-Path -LiteralPath $shortcutPath) {
            $ow = [System.Windows.Forms.MessageBox]::Show($form, "Overwrite existing '$cleanName.lnk' on Desktop?", 'Confirm Overwrite', 'YesNo', 'Question')
            if ($ow -ne 'Yes') { return }
        }

        # PowerShell 5.1 Mode
        if ($cmbMode.SelectedIndex -eq 0) {
            & $writeShortcutFile $ps5ExePath $shortcutPath $scriptPath $iconInfo.Spec 'PowerShell 5.1'
            $script:StatusKind = 'Success'
            $lblStatus.Text = "Created '$cleanName.lnk' (PowerShell 5.1) on your Desktop."
            Apply-StatusStyle
            return
        }

        # PowerShell 7.x Mode
        $pwsh7Info = Get-Pwsh7Info
        if ($null -ne $pwsh7Info) {
            & $writeShortcutFile $pwsh7Info.ExePath $shortcutPath $scriptPath $iconInfo.Spec 'PowerShell 7.x'
            $script:StatusKind = 'Success'
            $lblStatus.Text = "Created '$cleanName.lnk' (PowerShell 7.x) on your Desktop."
            Apply-StatusStyle
            return
        }

        # PowerShell 7.x is not installed -> Ask user before installing, then create shortcut
        $ask = [System.Windows.Forms.MessageBox]::Show(
            $form,
            "PowerShell 7.x (pwsh.exe) is not currently installed on this PC.`n`nWould you like to download and install PowerShell 7 now, and then create '$cleanName.lnk'?",
            'PowerShell 7.x Not Installed',
            'YesNo',
            'Question'
        )
        if ($ask -ne 'Yes') {
            $script:StatusKind = 'Neutral'
            $lblStatus.Text = 'Canceled: PowerShell 7.x is not installed.'
            Apply-StatusStyle
            return
        }

        & $startPwsh7Install $true $shortcutPath $scriptPath $cleanName $iconInfo.Spec
    }
    catch {
        $script:StatusKind = 'Error'
        $lblStatus.Text = "Failed: $($_.Exception.Message)"
        Apply-StatusStyle
    }
})

$btnTheme.Add_Click({
    $script:IsDarkMode = -not $script:IsDarkMode
    Apply-Theme
})

$btnClose.Add_Click({ $form.Close() })

if ($cmbMode.SelectedIndex -eq 1) {
    $initialInfo = Get-Pwsh7Info
    if ($null -ne $initialInfo) {
        $txtIconPath.Text = "$($initialInfo.IconPath),0"
    }
}

Apply-Theme
& $refreshModeStatus
& $refreshIcon
& $refreshState

$form.Add_Shown({
    [Win32ShellHelper]::SetDarkTitleBar($form.Handle, $script:IsDarkMode)
    [void][Win32ShellHelper]::SendMessage($txtScriptPath.Handle, 0x1501, [IntPtr]1, 'Click Browse to select a .ps1 script...')
    & $refreshIcon

    $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    $form.Activate()
    $form.BringToFront()
    [void][Win32ShellHelper]::ShowWindow($form.Handle, 5) # 5 = SW_SHOW
    [void][Win32ShellHelper]::SetForegroundWindow($form.Handle)
})

$form.Add_FormClosing({
    foreach ($t in @($script:ActiveTimers)) {
        try { $t.Stop(); $t.Dispose() } catch { }
    }
    $script:ActiveTimers.Clear()
})

[void]$form.ShowDialog()
if ($null -ne $picIcon.Image) { $picIcon.Image.Dispose() }
$form.Dispose()

