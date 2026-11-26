# AsusNatView

[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/AsusNatView?label=PowerShell%20Gallery&color=0078D6&cacheSeconds=3600)](https://www.powershellgallery.com/packages/AsusNatView/1.0.0)
[![GitHub Release](https://img.shields.io/github/v/release/2civics/Asus-Nat-View?label=GitHub%20Release&color=2EA44F&cacheSeconds=3600)](https://github.com/2civics/Asus-Nat-View/releases/tag/v.1.0.0)
[![PowerShell 5.1 | 7.x](https://img.shields.io/badge/PowerShell-5.1%20%7C%207.x-5391FE)](https://www.powershellgallery.com/packages/AsusNatView/1.0.0)
[![Platform Windows](https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011-0078D6)](https://github.com/2civics/Asus-Nat-View)

[PowerShell Gallery](https://www.powershellgallery.com/packages/AsusNatView/1.0.0) | [GitHub Releases](https://github.com/2civics/Asus-Nat-View/releases) | [Report an Issue](https://github.com/2civics/Asus-Nat-View/issues)

A lightweight, read-only Windows WPF GUI for inspecting live `iptables` NAT rules (`PREROUTING`, `POSTROUTING`, `VSERVER`) on ASUS (Asuswrt / Asuswrt-Merlin) routers over SSH.

## Features

* **Read-Only Inspection:** Queries `iptables -t nat -L <CHAIN> -v -n -x` over SSH without modifying router firewall state.
* **Live Search Filter:** Filters across all columns (ports, IP addresses, targets, interfaces, and rule details) in real time as you type.
* **Native Dark & Light Themes:** Automatically detects your Windows 10/11 app theme (including native DWM dark title bars) or accepts manual `Dark` / `Light` overrides.
* **Exact Packet & Byte Counters:** Displays unrounded packet and byte totals for verifying port forwards and custom NAT redirects.

## Prerequisites

1. **Windows 10 or Windows 11** with PowerShell 5.1 or PowerShell 7+.
2. **Windows OpenSSH Client** (`ssh.exe` available in your system `PATH`).
3. **ASUS Router** running stock Asuswrt or Asuswrt-Merlin firmware.

## Router & SSH Key Setup

Because `AsusNatView.ps1` connects non-interactively (`BatchMode=yes`), you need an SSH key pair on your PC and your public key added to your router.

### 1. Generate an SSH Key Pair on Windows

Open PowerShell and run the following commands to create the `.ssh` directory (if it does not exist) and generate an Ed25519 key pair:

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.ssh" | Out-Null
ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\id_ed25519" -N ""
```

> **Note:** Leaving the passphrase empty (`-N ""`) allows `AsusNatView.ps1` to connect automatically without prompting. If you prefer a passphrase-protected key, load it into the Windows `ssh-agent` service first.

Copy your new **public** key to the Windows clipboard:

```powershell
Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub" | Set-Clipboard
```

### 2. Enable SSH and Add Your Public Key on the Router

1. Log into your ASUS router's web interface (`http://192.168.50.1` or `http://router.asus.com`).
2. Navigate to **Administration > System**.
3. Under the **Service** section, set **Enable SSH** to **LAN only**.
   > **Security Note:** Always select **LAN only**—never **LAN & WAN**—so SSH is never exposed to the public internet.
4. Set **Allow SSH password login** to **No** (optional, recommended once key login is verified).
5. Paste your copied `id_ed25519.pub` key (a single line starting with `ssh-ed25519 ...`) into the **Authorized Keys** box.
6. Click **Apply** at the bottom of the page.

### 3. Trust the Router's Host Key (First-Time Connection)

Connect once manually in PowerShell so OpenSSH saves your router's fingerprint to `$env:USERPROFILE\.ssh\known_hosts`:

```powershell
ssh -i "$env:USERPROFILE\.ssh\id_ed25519" admin@192.168.50.1
```

Type `yes` when prompted to continue connecting, then type `exit` to close the session.

## Installation

### Option 1: PowerShell Gallery

Install directly from the [PowerShell Gallery](https://www.powershellgallery.com/packages/AsusNatView/1.0.0):

```powershell
Install-Script -Name AsusNatView
```

To update an existing installation to the latest version:

```powershell
Update-Script -Name AsusNatView
```

### Option 2: Manual Download

Download `AsusNatView.ps1` from the [Releases](https://github.com/2civics/Asus-Nat-View/releases) page and save it to your preferred scripts directory.

## Configuration

Edit the `# --- Configuration ---` section at the top of `AsusNatView.ps1` to match your router and SSH key setup:

```powershell
# --- Configuration ---
$RouterIP     = "192.168.50.1"
$User         = "admin"
$KeyPath      = "$env:USERPROFILE\.ssh\id_ed25519"
$DeviceLabel  = "ASUS Router"
$Chains       = @("PREROUTING", "POSTROUTING", "VSERVER")
$DefaultChain = "PREROUTING"
$Theme        = "Auto"   # Options: "Auto", "Dark", "Light"
```

| Variable | Default | Description |
| :--- | :--- | :--- |
| `$RouterIP` | `"192.168.50.1"` | IP address or hostname of your ASUS router |
| `$User` | `"admin"` | Router SSH login username |
| `$KeyPath` | `"$env:USERPROFILE\.ssh\id_ed25519"` | Path to your OpenSSH private key file |
| `$DeviceLabel` | `"ASUS Router"` | Router name displayed in the window title and error dialogs |
| `$Chains` | `@("PREROUTING", "POSTROUTING", "VSERVER")` | `iptables` NAT chains shown in the dropdown selector |
| `$DefaultChain` | `"PREROUTING"` | Initial NAT chain loaded when the window opens |
| `$Theme` | `"Auto"` | UI color scheme (`"Auto"`, `"Dark"`, or `"Light"`) |

## Usage

If installed via `Install-Script` (and your PowerShell Scripts folder is in `PATH`):

```powershell
AsusNatView.ps1
```

Or run directly from a local folder:

```powershell
.\AsusNatView.ps1
```

## Creating a Windowless Desktop Shortcut

You can launch `AsusNatView.ps1` directly from your Desktop without leaving a PowerShell console window open in the background.

### Option 1: Use PowerShell Desktop Shortcut Creator (Recommended)

For an easy point-and-click setup, download **[PowerShell Desktop Shortcut Creator](https://github.com/2civics/PowerShell-Desktop-Shortcut-Creator)** from GitHub (also available on the PowerShell Gallery via `Install-Script -Name create_desktop_shortcut`). It gives you a dark-mode GUI to browse for `AsusNatView.ps1`, enable windowless background execution, choose PowerShell 5.1 or 7.x, and pick a Windows system icon automatically.

### Option 2: Create Manually in Windows

1. **Locate your script path:**
   * If you downloaded `AsusNatView.ps1` manually, note its full path (for example, `C:\Scripts\AsusNatView.ps1`).
   * If you installed it via `Install-Script`, run the following in PowerShell to get its exact path:
     ```powershell
     (Get-Command AsusNatView.ps1).Source
     ```
2. Right-click an empty area on your **Desktop** and select **New > Shortcut**.
3. In the **Type the location of the item** box, enter the following command (replacing `C:\Path\To\AsusNatView.ps1` with your actual path):
   ```text
   powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Path\To\AsusNatView.ps1"
   ```
4. Click **Next**, type `AsusNatView` as the shortcut name, and click **Finish**.
5. *(Optional)* To assign a network icon, right-click the shortcut, select **Properties > Change Icon...**, enter `%SystemRoot%\System32\netshell.dll` (or `shell32.dll`), choose an icon, and click **OK**.

### Option 3: Create Automatically via PowerShell

Run this snippet in PowerShell to create the shortcut on your Desktop automatically (if you downloaded the script manually, replace `"C:\Path\To\AsusNatView.ps1"` with your saved file path):

```powershell
$ScriptPath = (Get-Command AsusNatView.ps1 -ErrorAction SilentlyContinue).Source
if (-not $ScriptPath) {$ScriptPath = "C:\Path\To\AsusNatView.ps1" }

$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\Desktop\AsusNatView.lnk")
$Shortcut.TargetPath = "powershell.exe"
$Shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""
$Shortcut.WorkingDirectory = Split-Path -Path$ScriptPath -Parent
$Shortcut.IconLocation = "$env:SystemRoot\System32\netshell.dll,0"
$Shortcut.Description = "Inspect live iptables NAT rules on ASUS routers"
$Shortcut.Save()
```

## Keyboard Shortcuts

* **Type in Filter box:** Filter displayed rules in real time
* **F5:** Refresh packet and byte counters for the selected chain
* **Esc:** Close the window

## Troubleshooting

### "Connection refused" or "Connection timed out"
* **SSH is disabled on the router:** Verify **Enable SSH** is set to **LAN only** under **Administration > System** and that you clicked **Apply**.
* **Wrong router IP address:** Newer ASUS models default to `192.168.50.1`, while older models or custom subnets often use `192.168.1.1`. Update `$RouterIP` in the Configuration section to match your gateway IP.
* **Custom SSH port:** If you changed the router's SSH port away from `22`, add `-p <port>` to the `ssh` command inside `Get-NatRules`.

### "Host key verification failed" on First Run
* Because `AsusNatView.ps1` runs OpenSSH with `-o BatchMode=yes`, it cannot answer interactive fingerprint prompts.
* **Fix:** Run `ssh -i "$env:USERPROFILE\.ssh\id_ed25519" admin@192.168.50.1` once manually in PowerShell, type `yes` to trust the host key, and exit.

### "Permission denied (publickey)"
* **Verify your username:** ASUS routers let you customize the web UI login username during initial setup. Ensure `$User` matches the exact admin username configured on your router (it may not be `admin`).
* **Check your key paths:** `$KeyPath` in `AsusNatView.ps1` must point to your **private** key file (`id_ed25519`), while the contents of your **public** key file (`id_ed25519.pub`) must be pasted into **Administration > System > Authorized Keys** on the router.
* **Key has a passphrase:** If you created the key with a passphrase instead of `-N ""`, `BatchMode=yes` will reject it unless the key is loaded into the Windows `ssh-agent` service (`Start-Service ssh-agent; ssh-add "$env:USERPROFILE\.ssh\id_ed25519"`).

### "'ssh' is not recognized..."
* The built-in Windows OpenSSH Client is not installed or enabled. Open **Windows Settings > System > Optional features**, click **Add an optional feature**, and install **OpenSSH Client** (or run `Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0` in an elevated PowerShell prompt).

### "Unable to retrieve VSERVER rules" or Empty Table
* `VSERVER` is an Asuswrt / Asuswrt-Merlin chain used for port forwarding (Virtual Server). If you are querying a non-ASUS Linux router that lacks a `VSERVER` chain, remove `"VSERVER"` from the `$Chains` array in the Configuration block.
* If the window opens with `0` rows, no active NAT or port-forwarding rules are currently configured in that chain.

### Script Blocked by PowerShell Execution Policy
* If Windows blocks local scripts from running, allow locally created scripts for your user account:
  ```powershell
  Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
  ```

## License

MIT License