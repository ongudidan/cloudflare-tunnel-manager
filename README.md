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

## 👨‍💻 Author
Dan Ong'udi
📧 [ongudidan@gmail.com](mailto:ongudidan@gmail.com)
🌐 https://github.com/ongudidan

Feel free to open issues or make suggestions via GitHub.


