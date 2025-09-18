#!/bin/bash
set -e
#set -x

# ==============================================================================
# IMPORTANT: UPDATE THESE IP ADDRESSES
# ==============================================================================
# Replace these placeholder IPs with the values from the 'terraform output'.
SERVER1_PRIVATE_IP="10.0.1.100" # coordinator_private_ip
SERVER2_PRIVATE_IP="10.0.1.101" # coordinator_standby_private_ip
SERVER3_PRIVATE_IP="10.0.2.200" # segment_server_1_private_ip
SERVER4_PRIVATE_IP="10.0.2.201" # segment_server_2_private_ip

# ==============================================================================
# SCRIPT CONFIGURATION (No changes needed below this line)
# ==============================================================================
AWS_REGION="eu-west-2" # From variables.tf

# Construct the AWS fully qualified domain names (FQDNs)
FQDN_S1="ip-$(echo ${SERVER1_PRIVATE_IP} | tr . -).${AWS_REGION}.compute.internal"
FQDN_S2="ip-$(echo ${SERVER2_PRIVATE_IP} | tr . -).${AWS_REGION}.compute.internal"
FQDN_S3="ip-$(echo ${SERVER3_PRIVATE_IP} | tr . -).${AWS_REGION}.compute.internal"
FQDN_S4="ip-$(echo ${SERVER4_PRIVATE_IP} | tr . -).${AWS_REGION}.compute.internal"

echo
echo "--- 1. Creating host files in /home/gpadmin ---"
echo
# Create the all_hosts file
cat > /home/gpadmin/all_hosts << EOH
${FQDN_S1}
${FQDN_S2}
${FQDN_S3}
${FQDN_S4}
EOH

echo
# Create the seg_hosts file for server 3 and server 4
cat > /home/gpadmin/seg_hosts << EOH
${FQDN_S3}
${FQDN_S4}
EOH

echo
echo "--- 2. Creating gpinitsystem_config file ---"
echo
# Create the gpinitsystem_config file
cat > /home/gpadmin/gpinitsystem_config << EOC
SEG_PREFIX=gpseg
PORT_BASE=6000
declare -a DATA_DIRECTORY=(/data/primary /data/primary /data/primary)
COORDINATOR_HOSTNAME=${FQDN_S1}
COORDINATOR_DIRECTORY=/data/coordinator
COORDINATOR_PORT=5432
TRUSTED_SHELL=ssh
ENCODING=UNICODE
MIRROR_PORT_BASE=7000
declare -a MIRROR_DATA_DIRECTORY=(/data/mirror /data/mirror /data/mirror)
DATABASE_NAME=aws_whpg7
EOC

echo "--- 3. Verifying file creation ---"
echo
ls -l /home/gpadmin
echo
echo "Contents of all_hosts:"
cat /home/gpadmin/all_hosts
echo
echo "Contents of seg_hosts:"
cat /home/gpadmin/seg_hosts

echo
echo "--- 4. Setting up passwordless SSH across the cluster ---"
echo
# Generate a new SSH key for gpadmin without a passphrase
ssh-keygen -t rsa -f ~/.ssh/id_rsa -q -P ''
echo
# Add the new public key to authorized_keys
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
echo
# Set correct permissions for the .ssh directory and authorized_keys file
chmod 700 ~/.ssh/
chmod 600 ~/.ssh/authorized_keys

# Copy the SSH key to all hosts in the cluster using the password 'changeme@123'
echo
for i in $(cat /home/gpadmin/all_hosts); do
    echo "----- Copying SSH ID to $i -----"
    SSHPASS='changeme@123' sshpass -e ssh-copy-id -o StrictHostKeyChecking=no $i
done

echo "--- 5. Initializing Greenplum environment and exchanging keys ---"
echo
# Source the Greenplum environment file
source /usr/local/greenplum-db/greenplum_path.sh
echo
# Exchange the gpadmin user's ssh keys with all hosts to ensure seamless communication between all
gpssh-exkeys -f /home/gpadmin/all_hosts

echo
echo "--- 6. Creating data directories on segment hosts (servers 3 & 4) ---"
echo
gpssh -f /home/gpadmin/seg_hosts "sudo mkdir -p /data/primary"
gpssh -f /home/gpadmin/seg_hosts "sudo mkdir -p /data/mirror"
gpssh -f /home/gpadmin/seg_hosts "sudo chown -R gpadmin:gpadmin /data/"

echo
echo "--- 7. Creating data directory on the Coordinator host (server 1) ---"
echo
sudo mkdir -p /data/coordinator
sudo chown -R gpadmin:gpadmin /data

echo
echo "--- 8. Initializing the Greenplum Database system ---"
echo
gpinitsystem -h /home/gpadmin/seg_hosts -c /home/gpadmin/gpinitsystem_config -a

echo
echo "--- 9. Updating .bashrc for gpadmin user with environment variables ---"
echo
cat >> /home/gpadmin/.bashrc << 'EOF'

# Greenplum Database environment variables
source /usr/local/greenplum-db/greenplum_path.sh
export COORDINATOR_DATA_DIRECTORY=/data/coordinator/gpseg-1
export PGPORT=5432
export PGUSER=gpadmin
export PGDATABASE=aws_whpg7
EOF

# Source the updated .bashrc file

source /home/gpadmin/.bashrc

echo "--- Greenplum setup complete! .bashrc has been updated & sourced. ---"

echo

echo
echo "--- 10. Add trust entries in the Coordinator's pg_hba.conf for the 2 Segment hosts ---"
echo
# Append the new entry to the end of the file
echo "host    all         gpadmin         ${SERVER3_PRIVATE_IP}/32       trust" >> /data/coordinator/gpseg-1/pg_hba.conf
echo "host    all         gpadmin         ${SERVER4_PRIVATE_IP}/32       trust" >> /data/coordinator/gpseg-1/pg_hba.conf

# Reload the Greenplum configuration to apply the change
gpstop -u

echo
echo "--- 11. Creating data directories on Coordinator Standby host (server 2) ---"
echo
gpssh -h ${FQDN_S2} "sudo mkdir -p /data/coordinator"
gpssh -h ${FQDN_S2} "sudo chown -R gpadmin:gpadmin /data/"

echo
echo "--- 12. Initialise the Coordinator Standby host (server 2) ---"
echo
gpinitstandby -s ${FQDN_S2} -a

echo
echo "--- 13. Verify that the Coordinator Standby host has been initialised and that replication is started ---"
echo
gpstate -f

echo
echo "--- 14. Verify in 'gp_segment_configuration' that the Coordinator Standby host has been initialised ---"
echo
psql -c "select * from gp_segment_configuration order by 2;"
