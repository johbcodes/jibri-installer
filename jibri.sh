#!/bin/bash

# Variables - Replace these with your actual values
DOMAIN="yourdomain.com"                  # Your domain name
JIBRI_PASS="jibriauthpass"              # Password for Jibri control login
RECORDER_PASS="jibrirecorderpass"       # Password for Jibri recorder login

# Exit on any error
set -e

echo "Starting Jitsi Meet and Jibri installation on Ubuntu 20.04..."

# Step 1: Update and Upgrade System
echo "Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Step 2: Set Hostname
echo "Setting hostname to $DOMAIN..."
sudo hostnamectl set-hostname "$DOMAIN"

# Step 3: Configure /etc/hosts
echo "Configuring /etc/hosts..."
echo "127.0.0.1 localhost" | sudo tee /etc/hosts
echo "127.0.0.1 $DOMAIN" | sudo tee -a /etc/hosts

# Step 4: Configure Firewall
echo "Configuring firewall with UFW..."
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 10000/udp
sudo ufw allow 5222/tcp
sudo ufw enable -y

# Step 5: Install Jitsi Meet
echo "Installing Jitsi Meet..."
# Add Jitsi repository key
wget -qO - https://download.jitsi.org/jitsi-key.gpg.key | sudo apt-key add -
# Add Jitsi repository
echo "deb https://download.jitsi.org stable/" | sudo tee /etc/apt/sources.list.d/jitsi-stable.list
# Update package list
sudo apt update
# Install Jitsi Meet (interactive step)
echo "During installation, enter '$DOMAIN' when prompted for the hostname."
sudo apt install -y jitsi-meet
# Obtain SSL certificate with Let's Encrypt
sudo /usr/share/jitsi-meet/scripts/install-letsencrypt-cert.sh

# Step 6: Install Jibri Prerequisites
echo "Installing Jibri prerequisites..."

# Load ALSA loopback module (required for audio capture)
if ! lsmod | grep -q snd_aloop; then
    echo "Loading snd_aloop module..."
    sudo modprobe snd_aloop
    echo "snd_aloop" | sudo tee -a /etc/modules
fi

# Install FFmpeg
sudo apt install -y ffmpeg

# Install Google Chrome
sudo apt install -y wget curl gnupg jq unzip
curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/google-chrome-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome-keyring.gpg] http://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/google-chrome.list
sudo apt update
sudo apt install -y google-chrome-stable
sudo apt-mark hold google-chrome-stable

# Set Chrome policies to disable security warnings
sudo mkdir -p /etc/opt/chrome/policies/managed
echo '{ "CommandLineFlagSecurityWarningsEnabled": false }' | sudo tee /etc/opt/chrome/policies/managed/managed_policies.json

# Install Chromedriver (matching Chrome version)
CHROME_VER=$(google-chrome --version | cut -d " " -f3 | cut -d. -f1-3)
CHROMELAB_LINK="https://googlechromelabs.github.io/chrome-for-testing"
CHROMEDRIVER_LINK=$(curl -s "$CHROMELAB_LINK/known-good-versions-with-downloads.json" | jq -r ".versions[] | select(.version == \"$CHROME_VER\") | .downloads.chromedriver[] | select(.platform == \"linux64\") | .url")
if [ -z "$CHROMEDRIVER_LINK" ]; then
    echo "Error: Could not find Chromedriver for Chrome version $CHROME_VER"
    exit 1
fi
wget -O /tmp/chromedriver-linux64.zip "$CHROMEDRIVER_LINK"
unzip -o /tmp/chromedriver-linux64.zip -d /tmp
sudo mv /tmp/chromedriver-linux64/chromedriver /usr/local/bin/
sudo chown root:root /usr/local/bin/chromedriver
sudo chmod 755 /usr/local/bin/chromedriver

# Step 7: Install Jibri
echo "Installing Jibri..."
# Jitsi repository already added; just install Jibri
sudo apt install -y jibri

# Step 8: Configure Jibri User
echo "Configuring Jibri user..."
sudo usermod -aG adm,audio,video,plugdev jibri

# Step 9: Configure Jibri (Manual Step)
echo "Manual step required: Configure /etc/jitsi/jibri/jibri.conf"
echo "Edit the file with: sudo nano /etc/jitsi/jibri/jibri.conf"
echo "Update the following:"
echo "  - Replace 'yourdomain.com' with '$DOMAIN'"
echo "  - Set 'control-login.password' to '$JIBRI_PASS'"
echo "  - Set 'call-login.password' to '$RECORDER_PASS'"
echo "Example configuration snippet:"
cat << EOF
jibri {
    api {
        xmpp {
            environments = [
                {
                    name = "$DOMAIN"
                    xmpp-server-hosts = ["$DOMAIN"]
                    xmpp-domain = "$DOMAIN"
                    control-login {
                        domain = "auth.$DOMAIN"
                        username = "jibri"
                        password = "$JIBRI_PASS"
                        port = 5222
                    }
                    control-muc {
                        domain = "internal.auth.$DOMAIN"
                        room-name = "JibriBrewery"
                        nickname = "myjibri-1"
                    }
                    call-login {
                        domain = "recorder.$DOMAIN"
                        username = "recorder"
                        password = "$RECORDER_PASS"
                    }
                    strip-from-room-domain = "conference."
                    trust-all-xmpp-certs = true
                    usage-timeout = 0
                }
            ]
        }
    }
}
EOF

# Step 10: Configure Prosody
echo "Configuring Prosody..."
PROSODY_CFG="/etc/prosody/conf.avail/$DOMAIN.cfg.lua"
sudo bash -c "cat << EOF >> $PROSODY_CFG

-- Internal MUC component for Jibri
Component \"internal.auth.$DOMAIN\" \"muc\"
    modules_enabled = { \"ping\"; }
    storage = \"memory\"
    muc_room_cache_size = 1000

-- Recorder virtual host
VirtualHost \"recorder.$DOMAIN\"
    modules_enabled = { \"ping\"; }
    authentication = \"internal_hashed\"
EOF"

# Register Jibri accounts
sudo prosodyctl register jibri "auth.$DOMAIN" "$JIBRI_PASS"
sudo prosodyctl register recorder "recorder.$DOMAIN" "$RECORDER_PASS"

# Step 11: Configure Jicofo
echo "Configuring Jicofo..."
JICOFO_CFG="/etc/jitsi/jicofo/config"
sudo bash -c "echo 'JICOFO_OPTS=\"--domain=$DOMAIN --brewery-jid=JibriBrewery@internal.auth.$DOMAIN --pending-timeout=90\"' >> $JICOFO_CFG"

# Step 12: Configure Jitsi Meet for Recording
echo "Configuring Jitsi Meet for recording..."
MEET_CFG="/etc/jitsi/meet/$DOMAIN-config.js"
sudo sed -i "s|// recordingService|recordingService|" "$MEET_CFG"
sudo sed -i "s|// hiddenDomain:.*|hiddenDomain: 'recorder.$DOMAIN',|" "$MEET_CFG"
sudo sed -i "s|// liveStreaming|liveStreaming|" "$MEET_CFG"

# Step 13: Create Recordings Directory
echo "Creating recordings directory..."
sudo mkdir -p /recordings
sudo chown jibri:jibri /recordings

# Step 14: Start and Enable Services
echo "Starting services..."
sudo systemctl enable jibri
sudo systemctl restart prosody
sudo systemctl restart jicofo
sudo systemctl restart jitsi-videobridge2
sudo systemctl restart jibri

echo "Installation and configuration completed!"
echo "Next steps:"
echo "1. Verify /etc/jitsi/jibri/jibri.conf is correctly configured."
echo "2. Test recording functionality in Jitsi Meet."
echo "3. Check logs if issues arise: /var/log/jitsi/jibri/"