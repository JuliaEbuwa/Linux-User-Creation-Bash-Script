#!/bin/bash

TEXT_FILE="users_and_groups.txt"
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
sudo chmod 777 "$LOG_FILE"
sudo chmod 777 "$PASSWORD_FILE"

OWNER="root:root"
sudo chown "$OWNER" "$LOG_FILE"
sudo chown "$OWNER" "$PASSWORD_FILE"

# Function to log actions with a timestamp
log_action() { 
  local message="$1" 
  echo "$(date +'%Y-%m-%d %H:%M:%S') - $message" >> "$LOG_FILE"
}

# Read the file and create users
while IFS=';' read -r user groups; do
  user=$(echo "$user" | xargs)  # Trim whitespace
  groups=$(echo "$groups" | xargs)  # Trim whitespace

  # Check if user already exists
  if id -u "$user" >/dev/null 2>&1; then
    log_action "User $user already exists. Skipping creation."
  else
    # Check if groups exist, create if they don't
    IFS=',' read -ra group_array <<< "$groups"
    for group in "${group_array[@]}"; do
      group=$(echo "$group" | xargs)  # Trim whitespace from each group
      if ! getent group "$group" >/dev/null; then
        sudo groupadd "$group"
        log_action "Group $group created."
      fi
    done

    # Create user with personal group
    sudo useradd -m -s /bin/bash "$user"
    if [ $? -eq 0 ]; then
      log_action "User $user created."
    else
      log_action "Failed to create user $user."
      continue
    fi

    # Add user to specified groups
    for group in "${group_array[@]}"; do
      group=$(echo "$group" | xargs)  # Trim whitespace from each group again
      sudo usermod -aG "$group" "$user"
      log_action "User $user added to group $group."
    done

    # Generate random 8 character password for user
    PASSWORD=$(openssl rand -base64 6 | tr -dc 'A-Za-z0-9' | head -c 8)

    # Set the generated password for user
    echo "$user:$PASSWORD" | sudo chpasswd
    if [ $? -eq 0 ]; then
      log_action "Password set for $user."
      echo "$user:$PASSWORD" >> "$PASSWORD_FILE"
    else
      log_action "Failed to set password for $user."
      sudo userdel -r "$user"
      continue
    fi
  fi
done < "$TEXT_FILE"

log_action "All users processed."
