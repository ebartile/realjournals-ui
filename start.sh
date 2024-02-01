#!/usr/bin/env bash
set -euo pipefail

# # Older versions of Docker were called docker, docker.io, or docker-engine. 
# # If these are installed, uninstall them:
# # sudo apt-get remove docker docker-engine docker.io containerd runc 
# sudo apt-get update
 
# # Update the apt package index and install packages to allow apt to use a repository over HTTPS: 
# sudo apt-get install \
#     ca-certificates \
#     curl \
#     gnupg \
#     lsb-release

# # Add Docker’s official GPG key: 
# sudo mkdir -p /etc/apt/keyrings
# curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# # Use the following command to set up the stable repository
# echo \
# "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
# $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# # Update the apt package index, and install the latest version of Docker Engine and containerd:
# sudo apt-get update
# sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-compose

# Verify that Docker Engine is installed correctly
sudo service docker start

# Check if the "docker" group already exists
if getent group docker &>/dev/null; then
  echo "The 'docker' group already exists."
else
  echo "Creating the 'docker' group..."
  sudo groupadd docker
fi

# Define the list of users
users=("realjournals" "adminuser" "terminaluser")

# Iterate over the list of users
for user in "${users[@]}"; do
  # Check if the user already exists
  if id "$user" &>/dev/null; then
    echo "User '$user' already exists."
  else
    echo "Creating user '$user'..."
    sudo useradd -m "$user"
    sudo chsh -s /bin/bash "$user"
  fi

  # Check if the user is already a member of the "docker" group
  if groups "$user" | grep -q "docker"; then
    echo "User '$user' is already a member of the 'docker' group."
  else
    echo "Adding user '$user' to the 'docker' group..."
    sudo usermod -aG docker "$user"
  fi
done

# Get the directory of the main script
script_directory=$(dirname "$(readlink -f "$0")")

# Specify the path to setup.sh relative to the script's directory
setup_script="$script_directory/setup.sh"

chmod o+rx .
chown -R realjournals:realjournals .

# Check if setup.sh exists
if [ -f "$setup_script" ]; then
  sudo -u realjournals bash -c "cd '$script_directory' && ./setup.sh $*"
else
  echo "setup.sh not found in the same directory as this script."
fi
