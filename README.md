# Cloudflare Tunnel Manager

A powerful and interactive Bash script to manage Cloudflare Tunnels from your terminal with ease. Supports creation, routing, service management, and full cleanup. Configurations are stored in user space (`~/.cloudflared`) to avoid system-level conflicts.

---

## 📦 Features

* Install and authenticate cloudflared
* Create and delete tunnels
* Edit tunnel config (ingress rules)
* Route subdomains to tunnels
* Run tunnels manually
* Enable or disable auto-start on boot (via systemd)
* View / Restart / Stop service status
* Full cleanup of tunnels and services

---

## 🛠️ Installation
Clone the repo or download the script manually:

```
git clone https://github.com/ongudidan/cloudflare-tunnel-manager.git  
cd cloudflare-tunnel-manager  
chmod +x ./cloudflare-tunnel-manager.sh  
```

Then run the script:

```
./cloudflare-tunnel-manager.sh
```

---

## 📘 Usage Guide
Once launched, use the interactive menu to manage tunnels.

---

### 1. Install cloudflared:
Downloads and installs the latest cloudflared binary.

---

### 2. Authenticate with Cloudflare:
Launches the browser to log in to your Cloudflare account.

👉 **If you're on a server (headless environment):**
When this option is selected, `cloudflared` will output a login link in the terminal.
Copy that link and open it in a browser from any device where you're logged in to Cloudflare.
Once approved, the server will save `cert.pem` in `~/.cloudflared/` and you're good to go.

✅ Alternatively, you can copy the cert file from another authenticated machine using `scp`:

```
scp ~/.cloudflared/cert.pem user@your-server-ip:~/.cloudflared/
```

---

### 3. Create a New Tunnel:
Prompts for a tunnel name, creates it, and auto-generates the config file (`.yml`) in `~/.cloudflared/`.

---

### 4. Edit Tunnel Config (Ingress Rules):
Opens the YAML file in nano for editing subdomain routes and services (e.g. ports).

---

### 5. Route Subdomains to Tunnel:
Adds DNS routes for subdomains pointing to the tunnel.

---

### 6. Run Tunnel Manually:
Starts the tunnel without needing systemd or auto-start.

---

### 7. Enable/Disable Auto-Start:
Lets you choose to either enable or disable automatic startup of the tunnel using systemd.
Conflicting configs in `/etc/cloudflared/config.yml` will be detected and removed upon confirmation.

---

### 8. Restart / Stop / View Tunnel Service:
Lets you manage the cloudflared systemd service:

* Restart it
* Stop it
* Check its status
* View logs in real-time

---

### 9. Delete cloudflared Service:
Stops and removes the system-wide cloudflared service (systemd).

---

### 10. Full Uninstall and Cleanup:
Completely removes everything — including:

* Installed binary
* Credentials and configs
* Systemd service
* `.deb` installer file

---

### 11. Delete a Tunnel:
Deletes a specific tunnel from Cloudflare and removes related local files.

---

### 0. Exit:
Closes the menu and quits the script.

---

**📁 Directory Structure**
All configuration and credentials are saved in:

```
~/.cloudflared/
├── <tunnel-name>.yml
├── <tunnel-id>.json
├── cert.pem
```

---

## ⚠️ Notes

* Avoid using `/etc/cloudflared/config.yml` directly — it may override your tunnel configs.
* When enabling auto-start, the script will remove conflicting system configs after your approval.

---

## 🐧 WSL Setup Guide (Windows Host Access & Auto-Start on Boot)

If you are running **WSL Ubuntu** on Windows, follow these steps to configure **Windows host access** (e.g., accessing **QZ Tray** or host services via `host.wsl.internal:8182`) and **auto-starting WSL Ubuntu on Windows boot**.

---

### 1. Accessing Windows Host Services from WSL
To connect to services running on your Windows host machine (such as QZ Tray on port `8182` / `8181`), configure your tunnel ingress rule using `host.wsl.internal`:

```yaml
ingress:
  - hostname: print.fortunedevs.com
    service: http://host.wsl.internal:8182
```

👉 **Optional (Localhost Mirroring):**
To also allow `localhost` inside WSL to map directly to Windows `localhost`, run in Windows **PowerShell**:

```powershell
Set-Content -Path "$env:USERPROFILE\.wslconfig" -Value "[wsl2]`nnetworkingMode=mirrored"
```

---

### 2. Auto-Start WSL Ubuntu on Windows Boot

#### Option A: Auto-start on User Login (Recommended - Silent Background)
Run this single command in Windows **PowerShell** to create a silent startup script in your Windows Startup folder:

```powershell
$path = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\StartWSL.vbs"; Set-Content -Path $path -Value 'Set WshShell = CreateObject("WScript.Shell")'; Add-Content -Path $path -Value 'WshShell.Run "wsl -d Ubuntu", 0, False'
```

#### Option B: Auto-start on PC Boot (Unattended - Before User Login)
1. Press `Win + R`, type **`taskschd.msc`** and press **Enter**.
2. Click **Create Task...** on the right panel.
3. Under **General**:
   * Name: `Start WSL Ubuntu`
   * Select: **Run whether user is logged on or not**
4. Under **Triggers**:
   * Click **New...** -> Select **At startup**.
5. Under **Actions**:
   * Click **New...** -> Program: `wsl.exe`, Arguments: `-d Ubuntu`
6. Click **OK** and enter your Windows credentials to save.

---

### 3. Enable Systemd Service Auto-Start & Default User Auto-Login
Inside your WSL Ubuntu terminal, set `systemd=true` and set your default user so WSL automatically logs in as your user on boot without prompting for a password:

```bash
sudo bash -c 'echo -e "[boot]\nsystemd=true\n\n[user]\ndefault=$USER" > /etc/wsl.conf'
```

> **Note:** WSL automatically logs in as your default user (`default=$USER`) without requiring a password on boot. Password prompts are only required when running `sudo` commands inside the terminal.

---

### 4. Restart WSL to Apply All Changes
Run in Windows **PowerShell**:

```powershell
wsl --shutdown
```

---

### 5. Verify Setup in WSL Ubuntu
Open your Ubuntu terminal and test:

```bash
# Test connection to QZ Tray via host.wsl.internal (Port 8182)
curl http://host.wsl.internal:8182

# Test secure endpoint (Port 8181)
curl -k https://host.wsl.internal:8181

# Test via localhost (if mirrored networking mode is enabled)
curl http://localhost:8182
```

---

## 👨‍💻 Author
Dan Ong'udi
📧 [ongudidan@gmail.com](mailto:ongudidan@gmail.com)
🌐 https://github.com/ongudidan

Feel free to open issues or make suggestions via GitHub.


