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
dnf install -y strace sysstat gdb lsof htop telnet sshpass nano tree

# Set ownership for greenplum directories
echo "Setting ownership for Greenplum directories"
chown -R "gpadmin:gpadmin" /usr/local/greenplum*
chgrp -R "gpadmin" /usr/local/greenplum*

# --- Final SSH Configuration ---
echo "Enabling PasswordAuthentication in sshd_config"
sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart sshd

echo "Instance configuration complete."