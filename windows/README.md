# Cloudflare Tunnel Manager (Windows)

A powerful and interactive PowerShell script to manage Cloudflare Tunnels from your terminal with ease. This is the Windows replica of the [Linux version](../cloudflare-tunnel-manager.sh), adapted for Windows services, MSI installers, and native tooling.

---

## 📦 Features

* Install and authenticate cloudflared (via MSI)
* Create and delete tunnels
* Edit tunnel config (ingress rules) with Notepad
* Route subdomains to tunnels
* Run tunnels manually
* Enable or disable auto-start on boot (via Windows Services)
* View / Restart / Stop service status
* Full cleanup of tunnels and services

---

## 🛠️ Requirements

* **Windows 10 / 11** (or Windows Server 2016+)
* **PowerShell 5.1+** (included with Windows 10/11)
* **Administrator privileges** required for:
  * Installing cloudflared (MSI)
  * Managing Windows Services (enable/disable auto-start, restart, stop)
  * Deleting the cloudflared service
  * Full uninstall

---

## 🚀 Installation

Clone the repo or download the files:

```
git clone https://github.com/ongudidan/cloudflare-tunnel-manager.git
cd cloudflare-tunnel-manager\windows
```

### Option A: Double-click the launcher

Simply double-click `cloudflare-tunnel-manager.bat` to start.

### Option B: Run from PowerShell (as Administrator)

```powershell
Set-ExecutionPolicy Bypass -Scope Process
.\cloudflare-tunnel-manager.ps1
```

> 💡 **Tip**: Right-click the `.bat` file and select **"Run as administrator"** for full functionality.

---

## 📘 Usage Guide

Once launched, use the interactive menu to manage tunnels.

---

### 1. Install cloudflared
Downloads the latest `.msi` from GitHub releases and installs it silently. Detects your architecture (AMD64, ARM64, x86) automatically.

---

### 2. Authenticate with Cloudflare
Launches the browser to log in to your Cloudflare account.

👉 **If you're on a headless server:**
When this option is selected, `cloudflared` will output a login link in the terminal.
Copy that link and open it in a browser from any device where you're logged in to Cloudflare.
Once approved, the server will save `cert.pem` in `%USERPROFILE%\.cloudflared\` and you're good to go.

✅ Alternatively, you can copy the cert file from another authenticated machine:

```powershell
Copy-Item \\other-machine\Users\username\.cloudflared\cert.pem $env:USERPROFILE\.cloudflared\
```

---

### 3. Create a New Tunnel
Prompts for a tunnel name, creates it, and auto-generates the config file (`.yml`) in `%USERPROFILE%\.cloudflared\`.

---

### 4. Edit Tunnel Config (Ingress Rules)
Opens the YAML file in Notepad for editing subdomain routes and services (e.g., ports).

---

### 5. Route Subdomains to Tunnel
Adds DNS routes for subdomains pointing to the tunnel.

---

### 6. Run Tunnel Manually
Starts the tunnel directly without needing a Windows Service.

---

### 7. Enable/Disable Auto-Start
Lets you choose to either enable or disable automatic startup of the tunnel using Windows Services.
Conflicting configs in `%ProgramData%\cloudflared\config.yml` will be detected and removed upon confirmation.

---

### 8. Restart / Stop / View Tunnel Service
Lets you manage the cloudflared Windows service:

* Restart it
* Stop it
* Check its status
* View log entries (from Windows Event Log or cloudflared log file)

---

### 9. Delete cloudflared Service
Stops and removes the Windows cloudflared service.

---

### 10. Full Uninstall and Cleanup
Completely removes everything — including:

* Installed binary (MSI uninstall)
* Credentials and configs
* Windows Service
* ProgramData cloudflared directory

---

### 11. Delete a Tunnel
Deletes a specific tunnel from Cloudflare and removes related local files.

---

### 0. Exit
Closes the menu and quits the script.

---

## 📁 Directory Structure

All configuration and credentials are saved in:

```
%USERPROFILE%\.cloudflared\
├── <tunnel-name>.yml
├── <tunnel-id>.json
├── cert.pem
```

---

## ⚠️ Notes

* Run as **Administrator** for any service-related operations (options 7, 8, 9, 10).
* Avoid manually placing configs in `%ProgramData%\cloudflared\config.yml` — it may override your tunnel-specific configs.
* When enabling auto-start, the script will remove conflicting system configs after your approval.

---

## 👨‍💻 Author
Dan Ong'udi
📧 [ongudidan@gmail.com](mailto:ongudidan@gmail.com)
🌐 https://github.com/ongudidan

Feel free to open issues or make suggestions via GitHub.
