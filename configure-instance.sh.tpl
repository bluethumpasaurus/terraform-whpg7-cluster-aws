#!/bin/bash
set -e

# --- User Creation and Initial Setup ---
echo "Creating user: gpadmin"
useradd -m -s /bin/bash "gpadmin"
echo "gpadmin ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/gpadmin"

# Set passwords
echo "Setting passwords..."
echo "gpadmin:changeme@123" | chpasswd
echo "rocky:changeme@123" | chpasswd
echo "Passwords set for users: gpadmin and rocky"

## Run as gpadmin create and set correct permissions for .ssh directories
sudo -u gpadmin bash -c "mkdir /home/gpadmin/.ssh"
sudo -u gpadmin bash -c "chmod 700 /home/gpadmin/.ssh"
sudo -u gpadmin bash -c "chown -R gpadmin:gpadmin /home/gpadmin/.ssh"

# --- Run Root Commands for Software Installation ---
echo "Installing EnterpriseDB and other packages as root"
curl -1sSLf https://downloads.enterprisedb.com/${edb_token}/gpsupp/setup.rpm.sh | bash
dnf -y install epel-release
dnf -y install xerces-c-devel
dnf -y install warehouse-pg-7
dnf install -y strace sysstat gdb lsof htop telnet sshpass nano tree wget

# Set ownership for WarehousePG directories
echo "Setting ownership for WarehousePG directories"
chown -R "gpadmin:gpadmin" /usr/local/greenplum*
chgrp -R "gpadmin" /usr/local/greenplum*


# --- Final SSH Configuration ---
echo "Securing sshd: Disabling password authentication by default"
# Ensure the default is 'no'. This handles both commented and uncommented lines.
sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

# Define the conditional block to be added
SSHD_MATCH_BLOCK="
# Allow password authentication only from the internal network
Match Address 10.0.0.0/8
  PasswordAuthentication yes
"

# Append the Match block to the end of the file
echo "$SSHD_MATCH_BLOCK" >> /etc/ssh/sshd_config

systemctl restart sshd

# --- Set system resources limits per WarehousePG docs & core size to unlimited ---
# Define the target configuration file
CONF_FILE="/etc/security/limits.d/99-gpadmin-limits.conf"

# Append the configuration using a Here Document
# The '<<' operator creates the file or appends if it exists
cat << EOF >> "$CONF_FILE"
* soft nofile 524288
* hard nofile 524288
* soft nproc 131072
* hard nproc 131072
* soft core unlimited
EOF


# Copy setup_whpg.sh file from repo to server 1 - WarehousePG Coordinator (index 0)
if [ ${server_index} -eq 0 ]; then
  echo "Downloading setup_whpg.sh file to server 1"
  wget https://raw.githubusercontent.com/bluethumpasaurus/terraform-whpg7-cluster-aws/refs/heads/main/setup_whpg.sh
  chmod +x setup_whpg.sh
  mv setup_whpg.sh /home/gpadmin/setup_whpg.sh
  chown gpadmin:gpadmin /home/gpadmin/setup_whpg.sh
fi

# Install MinIO client (mc) on server 1 - WarehousePG Coordinator (index 0)
if [ ${server_index} -eq 0 ]; then
  echo "Installing MinIO client (mc) on server 1"
  wget https://dl.min.io/client/mc/release/linux-amd64/mc
  chmod +x mc
  mv mc /usr/local/bin/
fi

# Install MinIO on server 2 - WarehousePG Standby Coordinator (index 1)
if [ ${server_index} -eq 1 ]; then
  echo "Installing MinIO on server 2"
  wget https://dl.min.io/server/minio/release/linux-amd64/minio.rpm
  rpm -Uhv minio.rpm

  # Create a user and group for MinIO
  groupadd -r minio-user
  useradd -M -r -g minio-user minio-user

  # Create a data directory
  mkdir -p /data/minio-storage
  chown -R minio-user:minio-user /data/minio-storage

  # Create the environment file
  cat << EOF > /etc/default/minio
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=minioadmin
MINIO_VOLUMES="/data/minio-storage/"
MINIO_OPTS="--console-address :9001"
EOF

  # Start and enable the MinIO service
  systemctl daemon-reload
  systemctl enable minio
  systemctl start minio
fi

echo "Instance configuration complete."