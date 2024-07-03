#!/bin/bash

TEXT_FILE="$1" 
LOG_FILE="/var/log/user_management.log"
PASSWORD_FILE="/var/secure/user_passwords.csv"

# Check if text file exists, if not end script
if ! [ -f "$TEXT_FILE" ]; then 
  echo "File $TEXT_FILE does not exist."
  exit 1
fi

# Check if log and password directories exist, if not create them
sudo mkdir -p /var/log && sudo touch "$LOG_FILE"
sudo mkdir -p /var/secure && sudo touch "$PASSWORD_FILE"

# Set appropriate permissions and ownership
sudo chmod 644 "$LOG_FILE"
sudo chmod 600 "$PASSWORD_FILE"

OWNER="root:root"
sudo chown "$OWNER" "$LOG_FILE"
sudo chown "$OWNER" "$PASSWORD_FILE"

# Function to log actions with a timestamp
log_action() { 
  local message="$1" 
  echo "$(date +'%Y-%m-%d %H:%M:%S') - $message" | sudo tee -a "$LOG_FILE" > /dev/null
}

# Read the file and create users
while IFS=';' read -r user groups; do
  user=$(echo "$user" | xargs)  # Trim whitespace
  groups=$(echo "$groups" | xargs)  # Trim whitespace

  # Check if user already exists
  if id -u "$user" >/dev/null 2>&1; then
    log_action "User $user already exists. Checking groups..."
  else
    # Create personal group for the user
    sudo groupadd "$user"
    log_action "Group $user created."

    # Create user with personal group and set home directory
    sudo useradd -m -s /bin/bash -g "$user" "$user"
    if [ $? -eq 0 ]; then
      log_action "User $user created."
    else
      log_action "Failed to create user $user."
      continue
    fi

    # Generate random 8 character password for user
    PASSWORD=$(openssl rand -base64 6 | tr -dc 'A-Za-z0-9' | head -c 8)

    # Set the generated password for user
    echo "$user:$PASSWORD" | sudo chpasswd
    if [ $? -eq 0 ]; then
      log_action "Password set for $user."
      echo "$user,$PASSWORD" | sudo tee -a "$PASSWORD_FILE" > /dev/null
    else
      log_action "Failed to set password for $user."
      sudo userdel -r "$user"
      continue
    fi
  fi

  # Check if groups exist and create if they don't, add user to groups
  IFS=',' read -ra group_array <<< "$groups"
  for group in "${group_array[@]}"; do
    group=$(echo "$group" | xargs)  # Trim whitespace from each group
    if ! getent group "$group" >/dev/null; then
      sudo groupadd "$group"
      log_action "Group $group created."
    fi

    # Check if user belongs to the group, if not, add user
    if id -nG "$user" | grep -qw "$group"; then
      log_action "User $user is already a member of group $group."
    else
      sudo usermod -aG "$group" "$user"
      log_action "User $user added to group $group."
    fi
  done
done < "$TEXT_FILE"

log_action "All users processed."
