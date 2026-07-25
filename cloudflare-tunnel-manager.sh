#!/bin/bash

USERNAME=$(whoami)
CLOUDFLARED_DIR="$HOME/.cloudflared"

show_menu() {
  echo -e "\n🚀 Cloudflare Tunnel Manager"
  echo "1. Install cloudflared"
  echo "2. Authenticate with Cloudflare"
  echo "3. Create new tunnel (auto config)"
  echo "4. Edit tunnel config (ingress rules)"
  echo "5. Route subdomains to tunnel"
  echo "6. Run tunnel manually"
  echo "7. Enable/Disable auto-start for tunnel"
  echo "8. Restart/Stop/View systemd service"
  echo "9. Delete cloudflared service"
  echo "10. Full uninstall and cleanup"
  echo "11. Delete a tunnel"
  echo "0. Exit"
  echo -n "Select an option [0-11]: "
}

get_tunnel_id() {
  local name="$1"
  [ -z "$name" ] && return 1
  cloudflared tunnel list 2>/dev/null | awk -v name="$name" '$1 ~ /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/ && $2 == name {print $1; exit}'
}

select_tunnel() {
  local provided_name="$1"
  if [ -n "$provided_name" ]; then
    TUNNEL_NAME="$provided_name"
    return 0
  fi

  mapfile -t TUNNEL_LIST < <(cloudflared tunnel list 2>/dev/null | awk '$1 ~ /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/ {print $2}')
  if [ ${#TUNNEL_LIST[@]} -eq 0 ]; then
    echo "❌ No tunnels found. Create one first."
    return 1
  fi

  echo -e "\n📜 Available Tunnels:"
  for i in "${!TUNNEL_LIST[@]}"; do
    echo "$((i+1)). ${TUNNEL_LIST[$i]}"
  done

  read -p "Select a tunnel by number: " num
  if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le ${#TUNNEL_LIST[@]} ]; then
    TUNNEL_NAME="${TUNNEL_LIST[$((num-1))]}"
  else
    echo "❌ Invalid selection."
    return 1
  fi
}

ensure_tunnel_credentials() {
  local tunnel_name="$1"
  local tunnel_id="$2"

  [ -z "$tunnel_name" ] || [ -z "$tunnel_id" ] && return 1

  mkdir -p "$CLOUDFLARED_DIR"
  local json_path="$CLOUDFLARED_DIR/$tunnel_id.json"

  if [ ! -f "$json_path" ]; then
    echo "🔍 Local credentials JSON missing for '$tunnel_name'. Fetching token from Cloudflare..."

    local token_raw
    token_raw=$(cloudflared tunnel token "$tunnel_name" 2>/dev/null | grep -vE 'INF|ERR|WARN' | tr -d '\r\n')

    if [ -n "$token_raw" ]; then
      if command -v python3 &>/dev/null; then
        TOKEN_RAW="$token_raw" JSON_PATH="$json_path" TUNNEL_NAME="$tunnel_name" python3 -c '
import os, base64, json, sys
token_raw = os.environ.get("TOKEN_RAW", "").strip()
json_path = os.environ.get("JSON_PATH", "")
tunnel_name = os.environ.get("TUNNEL_NAME", "")
try:
    if token_raw and json_path:
        bytes_data = base64.b64decode(token_raw)
        obj = json.loads(bytes_data.decode("utf-8"))
        if "a" in obj and "t" in obj and "s" in obj:
            cred = {
                "AccountTag": obj["a"],
                "TunnelID": obj["t"],
                "TunnelSecret": obj["s"]
            }
            with open(json_path, "w", encoding="utf-8") as f:
                json.dump(cred, f, indent=2)
            print(f"✅ Auto-generated local credentials JSON for '\''{tunnel_name}'\''.")
            sys.exit(0)
except Exception as e:
    print(f"⚠️ Failed to parse token for '\''{tunnel_name}'\'': {e}")
    sys.exit(1)
'
      elif command -v jq &>/dev/null; then
        local json_text
        json_text=$(echo "$token_raw" | base64 -d 2>/dev/null)
        if [ -n "$json_text" ]; then
          echo "$json_text" | jq '{AccountTag: .a, TunnelID: .t, TunnelSecret: .s}' > "$json_path" 2>/dev/null
          if [ -s "$json_path" ]; then
            echo "✅ Auto-generated local credentials JSON for '$tunnel_name'."
          fi
        fi
      fi
    fi
  fi

  [ -f "$json_path" ]
}

ensure_tunnel_config() {
  local tunnel_name="$1"
  [ -z "$tunnel_name" ] && return 1

  local tunnel_id
  tunnel_id=$(get_tunnel_id "$tunnel_name")

  if [ -z "$tunnel_id" ]; then
    echo "❌ Unable to find Tunnel ID for '$tunnel_name' in Cloudflare account."
    return 1
  fi

  mkdir -p "$CLOUDFLARED_DIR"

  # Ensure credentials JSON exists locally
  ensure_tunnel_credentials "$tunnel_name" "$tunnel_id"

  TUNNEL_CONFIG="$CLOUDFLARED_DIR/$tunnel_name.yml"
  CREDENTIALS_FILE="$CLOUDFLARED_DIR/$tunnel_id.json"

  # Auto-create missing .yml config file on demand
  if [ ! -f "$TUNNEL_CONFIG" ]; then
    echo "🛠️ Config file missing for pre-existing tunnel '$tunnel_name'."
    echo "⚙️ Auto-generating configuration file at: $TUNNEL_CONFIG"
    cat > "$TUNNEL_CONFIG" <<EOF
tunnel: $tunnel_id
credentials-file: $CREDENTIALS_FILE

ingress:
  # Main hostname ingress rule (e.g. dev server)
  - hostname: dev.fortunedevs.com
    service: http://localhost:80  # For WSL accessing Windows host services (e.g. QZ Tray), use http://host.wsl.internal:8182 or http://localhost:8182

  # Catch-all fallback for undefined subdomains
  - service: http_status:404
EOF
    echo "✅ Auto-created local configuration file for '$tunnel_name'."
  fi

  return 0
}

install_cloudflared() {
  local arch
  arch=$(dpkg --print-architecture 2>/dev/null || uname -m)
  case "$arch" in
    amd64|x86_64)
      DEB_ARCH="amd64"
      ;;
    arm64|aarch64)
      DEB_ARCH="arm64"
      ;;
    armhf|armv7l)
      DEB_ARCH="armhf"
      ;;
    arm|armv6l)
      DEB_ARCH="arm"
      ;;
    386|i386|i686)
      DEB_ARCH="386"
      ;;
    *)
      echo "❌ Unsupported architecture: $arch"
      return 1
      ;;
  esac

  echo "📥 Downloading cloudflared for $DEB_ARCH architecture..."
  wget "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${DEB_ARCH}.deb" -O "cloudflared-linux-${DEB_ARCH}.deb"
  sudo dpkg -i "cloudflared-linux-${DEB_ARCH}.deb"
  cloudflared --version
}

login_cloudflare() {
  cloudflared tunnel login
}

create_tunnel() {
  read -p "Enter a name for the tunnel: " TUNNEL_NAME
  if [ -z "$TUNNEL_NAME" ]; then
    echo "❌ Tunnel name cannot be empty."
    return 1
  fi

  echo "⛏️  Creating tunnel '$TUNNEL_NAME'..."
  cloudflared tunnel create "$TUNNEL_NAME"

  ensure_tunnel_config "$TUNNEL_NAME" || return 1

  echo "✅ Tunnel and config created successfully."
  echo "🔙 Now run option 4 to edit the config, or 5 to add DNS routes."
}

edit_tunnel_config() {
  select_tunnel || return 1
  ensure_tunnel_config "$TUNNEL_NAME" || return 1

  local editor="${EDITOR:-nano}"
  echo "📄 Opening $TUNNEL_CONFIG"
  "$editor" "$TUNNEL_CONFIG"
}

route_dns() {
  select_tunnel || return 1
  ensure_tunnel_config "$TUNNEL_NAME" || return 1

  while true; do
    read -p "Enter subdomain to route (e.g., dev.example.com), or 'done' to finish: " DOMAIN
    [ "$DOMAIN" == "done" ] && break
    [ -z "$DOMAIN" ] && continue

    echo "🔍 Checking if $DOMAIN is already routed..."
    OUTPUT=$(cloudflared tunnel route dns "$TUNNEL_NAME" "$DOMAIN" 2>&1)

    if echo "$OUTPUT" | grep -q "already configured"; then
      echo "⚠️  $DOMAIN is already routed to a tunnel."
      echo "ℹ️  If you want to reassign this domain:"
      echo "   🔙 Log in to the Cloudflare Dashboard and delete the existing DNS record for: $DOMAIN"
      echo "   🔁 Then come back and try routing it again."
      continue
    fi

    echo "$OUTPUT"
  done
}

run_tunnel() {
  select_tunnel || return 1
  ensure_tunnel_config "$TUNNEL_NAME" || return 1

  echo "🚀 Starting tunnel '$TUNNEL_NAME'..."
  cloudflared tunnel --config "$TUNNEL_CONFIG" run "$TUNNEL_NAME"
}

toggle_autostart() {
  select_tunnel || return 1
  ensure_tunnel_config "$TUNNEL_NAME" || return 1

  echo "⚙️  What would you like to do?"
  echo "1. Enable auto-start for '$TUNNEL_NAME'"
  echo "2. Disable auto-start for '$TUNNEL_NAME'"
  read -p "Select option [1-2]: " action

  case "$action" in
    1)
      if [ -f /etc/cloudflared/config.yml ]; then
        echo "⚠️  Conflict detected: /etc/cloudflared/config.yml exists."
        read -p "Do you want to overwrite /etc/cloudflared/config.yml to proceed cleanly? [y/N]: " delete_conf
        if [[ ! "$delete_conf" =~ ^[Yy]$ ]]; then
          echo "❌ Aborted to avoid conflict."
          return 1
        fi
      fi

      echo "🧹 Cleaning old systemd services if needed..."
      sudo systemctl stop cloudflared 2>/dev/null || true
      sudo systemctl disable cloudflared 2>/dev/null || true
      sudo rm -f /etc/systemd/system/cloudflared.service
      sudo rm -f /etc/systemd/system/cloudflared-update.service
      sudo rm -f /etc/systemd/system/cloudflared-update.timer
      sudo systemctl daemon-reload 2>/dev/null || true

      sudo mkdir -p /etc/cloudflared

      local tunnel_id
      tunnel_id=$(get_tunnel_id "$TUNNEL_NAME")
      if [ -n "$tunnel_id" ] && [ -f "$CLOUDFLARED_DIR/$tunnel_id.json" ]; then
        sudo cp "$CLOUDFLARED_DIR/$tunnel_id.json" "/etc/cloudflared/$tunnel_id.json"
        sudo chmod 600 "/etc/cloudflared/$tunnel_id.json"
      fi

      local temp_config="/tmp/cloudflared_config_$$.yml"
      cp "$TUNNEL_CONFIG" "$temp_config"

      if [ -n "$tunnel_id" ] && [ -f "/etc/cloudflared/$tunnel_id.json" ]; then
        sed -i "s|credentials-file:.*|credentials-file: /etc/cloudflared/$tunnel_id.json|g" "$temp_config"
      fi

      sudo cp "$temp_config" /etc/cloudflared/config.yml
      rm -f "$temp_config"

      echo "⚙️  Installing service for tunnel '$TUNNEL_NAME'..."
      sudo cloudflared --config /etc/cloudflared/config.yml service install
      sudo systemctl enable cloudflared
      sudo systemctl restart cloudflared 2>/dev/null || true

      sleep 2
      if systemctl is-active --quiet cloudflared 2>/dev/null; then
        echo "✅ Tunnel '$TUNNEL_NAME' is live and will auto-start on boot."
      else
        echo "✅ Service installed for '$TUNNEL_NAME'. Check status with option 8."
      fi
      ;;

    2)
      echo "🛑 Disabling cloudflared auto-start service..."
      sudo systemctl stop cloudflared 2>/dev/null || true
      sudo systemctl disable cloudflared 2>/dev/null || true
      sudo cloudflared service uninstall 2>/dev/null || true
      sudo rm -f /etc/systemd/system/cloudflared.service
      sudo rm -f /etc/systemd/system/cloudflared-update.service
      sudo rm -f /etc/systemd/system/cloudflared-update.timer
      sudo rm -f /etc/cloudflared/config.yml
      sudo systemctl daemon-reload 2>/dev/null || true
      echo "✅ Auto-start has been disabled for '$TUNNEL_NAME'."
      ;;

    *)
      echo "❌ Invalid selection."
      ;;
  esac
}

manage_service() {
  echo "a. Restart"
  echo "b. Stop"
  echo "c. Status"
  echo "d. View Logs"
  read -p "Choose action [a-d]: " action
  case $action in
    a) sudo systemctl restart cloudflared ;;
    b) sudo systemctl stop cloudflared ;;
    c) sudo systemctl status cloudflared ;;
    d) sudo journalctl -u cloudflared -f ;;
    *) echo "❌ Invalid option" ;;
  esac
}

delete_config_and_service() {
  echo "🧹 Cleaning up cloudflared service..."
  sudo systemctl stop cloudflared 2>/dev/null || true
  sudo systemctl disable cloudflared.service 2>/dev/null || true
  sudo rm -f /etc/systemd/system/cloudflared.service /etc/systemd/system/cloudflared-update.service
  sudo systemctl daemon-reload 2>/dev/null || true
  sudo cloudflared service uninstall 2>/dev/null || true
  sudo rm -rf /etc/cloudflared
  echo "✅ System cloudflared service removed."
}

full_cleanup() {
  echo "⚠️  This will completely remove cloudflared, all tunnels, configs, credentials, and services from your system."
  echo "❌ This action is irreversible and should only be done if you want a full reset."

  read -p "Are you sure you want to proceed? [y/N]: " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "❌ Full cleanup cancelled."
    return 1
  fi

  delete_config_and_service
  sudo rm -f "$CLOUDFLARED_DIR"/*.json "$CLOUDFLARED_DIR"/*.yml "$CLOUDFLARED_DIR"/cert.pem
  sudo rm -f cloudflared-linux-*.deb
  sudo rm -f "$(which cloudflared)" 2>/dev/null || true
  sudo apt remove cloudflared -y

  echo "✅ Everything has been removed."
}

delete_tunnel() {
  select_tunnel || return 1
  local tunnel_id
  tunnel_id=$(get_tunnel_id "$TUNNEL_NAME")
  [ -n "$tunnel_id" ] || { echo "❌ Unable to find tunnel ID for '$TUNNEL_NAME'."; return 1; }

  echo "⚠️  Are you sure you want to delete tunnel '$TUNNEL_NAME' (ID: $tunnel_id)? This cannot be undone."
  read -p "Type 'yes' to confirm: " confirm
  [ "$confirm" = "yes" ] || { echo "❌ Cancelled."; return 1; }

  echo "🛑 Stopping any running cloudflared services..."
  sudo systemctl stop cloudflared 2>/dev/null || true
  pkill -f "cloudflared.*$TUNNEL_NAME" 2>/dev/null || true

  echo "🧹 Cleaning up tunnel connections..."
  cloudflared tunnel cleanup "$TUNNEL_NAME" 2>/dev/null || true

  echo "🗑️ Attempting to delete the tunnel..."
  if ! cloudflared tunnel delete "$TUNNEL_NAME"; then
    echo "❌ Failed to delete tunnel. Please ensure no active cloudflared processes are using it."
    echo "   Run this to check: ps aux | grep cloudflared"
    return 1
  fi

  rm -f "$CLOUDFLARED_DIR/$tunnel_id.json" "$CLOUDFLARED_DIR/$TUNNEL_NAME.yml"
  sudo rm -f "/etc/cloudflared/$tunnel_id.json"
  echo "✅ Tunnel '$TUNNEL_NAME' and related files removed."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  while true; do
    show_menu
    read choice
    case $choice in
      1) install_cloudflared ;;
      2) login_cloudflare ;;
      3) create_tunnel ;;
      4) edit_tunnel_config ;;
      5) route_dns ;;
      6) run_tunnel ;;
      7) toggle_autostart ;;
      8) manage_service ;;
      9) delete_config_and_service ;;
      10) full_cleanup ;;
      11) delete_tunnel ;;
      0) echo "👋 Exiting..."; exit ;;
      *) echo "❌ Invalid choice." ;;
    esac
  done
fi
