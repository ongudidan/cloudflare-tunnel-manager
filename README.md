# Cloudflare Tunnel Manager

A powerful and interactive Bash script to manage [Cloudflare Tunnels](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/) from your terminal with ease. Supports creation, routing, service management, and full cleanup. Configurations are stored in user space (`~/.cloudflared`) to avoid system-level conflicts.

---

## 📦 Features

* Install and authenticate `cloudflared`
* Create and delete tunnels
* Edit tunnel config (ingress rules)
* Route subdomains to tunnels
* Run tunnels manually
* Enable or disable auto-start on boot (via systemd)
* View/Restart/Stop service status
* Full cleanup of tunnels and services

---

## 🛠️ Installation

Clone the repo or download the script manually:

```bash
git clone https://github.com/YOUR_USERNAME/cloudflare-tunnel-manager.git
cd cloudflare-tunnel-manager
chmod +x ./cloudflare-tunnel-manager.sh
```

Then run the script:

```bash
./cloudflare-tunnel-manager.sh
```

---

## 📘 Usage Guide

Once launched, use the interactive menu to manage tunnels.

### 1. Install cloudflared

Downloads and installs the latest `cloudflared` binary.

### 2. Authenticate with Cloudflare

Launches the browser to log in to your Cloudflare account.

### 3. Create a New Tunnel

Prompts for a name, creates a tunnel, and auto-generates a YAML config file in `~/.cloudflared/`.

### 4. Edit Tunnel Config (Ingress Rules)

Edit the YAML file using `nano` to change subdomain mappings or ports.

### 5. Route Subdomains to Tunnel

Add DNS routes to connect a subdomain to the tunnel.

### 6. Run Tunnel Manually

Start the tunnel without enabling auto-start.

### 7. Enable/Disable Auto-Start

Lets you choose whether to auto-start the tunnel via a systemd service at boot. Uses your personal config.

### 8. Restart / Stop / View Tunnel Service

Manage the `cloudflared` systemd service:

* Restart the service
* Stop it
* Check its status
* View logs

### 9. Delete cloudflared Service

Stops and deletes the system-wide `cloudflared` systemd service.

### 10. Full Uninstall and Cleanup

Completely removes `cloudflared`, tunnels, configs, credentials, and the systemd service.

### 11. Delete a Tunnel

Fully deletes a specific tunnel from Cloudflare and removes local credentials/config.

### 0. Exit

Quits the script.

---

## 📁 Directory Structure

All configs and credentials are stored in:

```
~/.cloudflared/
├── <tunnel-name>.yml
├── <tunnel-id>.json
├── cert.pem
```

---

## ⚠️ Notes

* Avoid manually using `/etc/cloudflared/config.yml` to prevent conflicts.
* When enabling auto-start, any conflicting system-wide config is removed after confirmation.

---

## 👨‍💻 Author

**Dan Ong'udi**
📧 [ongudidan@gmail.com](mailto:ongudidan@gmail.com)
🌐 [github.com/your\_username](https://github.com/your_username)

Feel free to open issues or suggestions on the GitHub repository.

---

## 📜 License

MIT License
