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

select_tunnel() {
  mapfile -t TUNNEL_LIST < <(cloudflared tunnel list | awk 'NR>1 {print $2}')
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

install_cloudflared() {
  wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
  sudo dpkg -i cloudflared-linux-amd64.deb
  cloudflared --version
}

login_cloudflare() {
  cloudflared tunnel login
}

create_tunnel() {
  read -p "Enter a name for the tunnel: " TUNNEL_NAME
  echo "⛏️  Creating tunnel '$TUNNEL_NAME'..."
  cloudflared tunnel create "$TUNNEL_NAME"

  echo "🔍 Getting Tunnel ID..."
  TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
  CREDENTIALS_FILE="$CLOUDFLARED_DIR/$TUNNEL_ID.json"
  TUNNEL_CONFIG="$CLOUDFLARED_DIR/$TUNNEL_NAME.yml"

  if [[ -z "$TUNNEL_ID" ]]; then
    echo "❌ Failed to get Tunnel ID for '$TUNNEL_NAME'."
    return 1
  fi

  echo "🗘️ Creating config at: $TUNNEL_CONFIG"
  cat > "$TUNNEL_CONFIG" <<EOF
tunnel: $TUNNEL_ID
credentials-file: $CREDENTIALS_FILE

ingress:
  # Subdomain 1 (e.g., dev server)
  - hostname: dev.fortunedevs.com
    service: http://localhost:80  # Change to your local server port (e.g., port 80)

  # Subdomain 2 (optional, admin dashboard)
  - hostname: admin.fortunedevs.com
    service: http://localhost:8080

  # Catch-all fallback for undefined subdomains
  - service: http_status:404
EOF

  echo "✅ Tunnel and example config created successfully."
  echo "🔙 Now run option 4 to edit the config, or 5 to add DNS routes."
}

edit_tunnel_config() {
  select_tunnel || return 1
  TUNNEL_CONFIG="$CLOUDFLARED_DIR/$TUNNEL_NAME.yml"

  if [ ! -f "$TUNNEL_CONFIG" ]; then
    echo "❌ Config file not found for '$TUNNEL_NAME'."
    return 1
  fi

  echo "📄 Opening $TUNNEL_CONFIG"
  nano "$TUNNEL_CONFIG"
}

route_dns() {
  select_tunnel || return 1

  while true; do
    read -p "Enter subdomain to route (e.g., dev.example.com), or 'done' to finish: " DOMAIN
    [ "$DOMAIN" == "done" ] && break

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
  TUNNEL_CONFIG="$CLOUDFLARED_DIR/$TUNNEL_NAME.yml"

  [ -f "$TUNNEL_CONFIG" ] || { echo "❌ Config file not found: $TUNNEL_CONFIG"; return 1; }

  cloudflared tunnel --config "$TUNNEL_CONFIG" run "$TUNNEL_NAME"
}

toggle_autostart() {
  select_tunnel || return 1
  TUNNEL_CONFIG="$CLOUDFLARED_DIR/$TUNNEL_NAME.yml"

  [ -f "$TUNNEL_CONFIG" ] || {
    echo "❌ Config file not found: $TUNNEL_CONFIG"
    return 1
  }

  echo "⚙️  What would you like to do?"
  echo "1. Enable auto-start for '$TUNNEL_NAME'"
  echo "2. Disable auto-start for '$TUNNEL_NAME'"
  read -p "Select option [1-2]: " action

  case "$action" in
    1)
      if [ -f /etc/cloudflared/config.yml ]; then
        echo "⚠️  Conflict detected: /etc/cloudflared/config.yml exists."
        echo "⚠️  This may override your user-specific config and cause issues."
        read -p "Do you want to delete /etc/cloudflared/config.yml to proceed cleanly? [y/N]: " delete_conf
        if [[ "$delete_conf" =~ ^[Yy]$ ]]; then
          sudo rm -f /etc/cloudflared/config.yml
          echo "🧹 Deleted /etc/cloudflared/config.yml"
        else
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
      sudo systemctl daemon-reexec
      sudo systemctl daemon-reload

      echo "⚙️  Installing service for tunnel '$TUNNEL_NAME'..."
      sudo cloudflared --config "$TUNNEL_CONFIG" service install

      echo "✅ Tunnel '$TUNNEL_NAME' will auto-start on boot."
      ;;

    2)
      echo "🛑 Disabling cloudflared auto-start service..."
      sudo systemctl stop cloudflared 2>/dev/null || true
      sudo systemctl disable cloudflared.service 2>/dev/null || true
      sudo rm -f /etc/systemd/system/cloudflared.service
      sudo rm -f /etc/systemd/system/cloudflared-update.service
      sudo rm -f /etc/systemd/system/cloudflared-update.timer
      sudo systemctl daemon-reexec
      sudo cloudflared service uninstall 2>/dev/null || true
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
  echo "😚 Cleaning up cloudflared service..."
  sudo systemctl stop cloudflared 2>/dev/null || true
  sudo systemctl disable cloudflared.service 2>/dev/null || true
  sudo rm -f /etc/systemd/system/cloudflared.service /etc/systemd/system/cloudflared-update.service
  sudo systemctl daemon-reexec
  sudo cloudflared service uninstall 2>/dev/null || true
  echo "✅ System cloudflared service removed."
}

full_cleanup() {
  delete_config_and_service
  sudo rm -f "$CLOUDFLARED_DIR"/*.json "$CLOUDFLARED_DIR"/*.yml "$CLOUDFLARED_DIR"/cert.pem
  sudo rm -f cloudflared-linux-amd64.deb
  sudo rm -f $(which cloudflared)
  sudo apt remove cloudflared -y
  echo "✅ Everything removed."
}

delete_tunnel() {
  select_tunnel || return 1
  TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
  [ -n "$TUNNEL_ID" ] || { echo "❌ Unable to find tunnel ID for '$TUNNEL_NAME'."; return 1; }

  echo "⚠️  Are you sure you want to delete tunnel '$TUNNEL_NAME' (ID: $TUNNEL_ID)? This cannot be undone."
  read -p "Type 'yes' to confirm: " confirm
  [ "$confirm" = "yes" ] || { echo "❌ Cancelled."; return 1; }

  cloudflared tunnel delete "$TUNNEL_NAME"
  rm -f "$CLOUDFLARED_DIR/$TUNNEL_ID.json" "$CLOUDFLARED_DIR/$TUNNEL_NAME.yml"
  echo "🗑️ Tunnel '$TUNNEL_NAME' and related files removed."
}

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
