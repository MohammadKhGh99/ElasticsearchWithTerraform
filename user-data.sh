#!/bin/bash

# update 
apt-get update -y
apt update -y

# install unzip for aws
apt install -y unzip

# java
apt install -y openjdk-11-jdk

# download and install aws
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
./aws/install
# remove redundant installation files
rm awscliv2.zip
rm -rf aws

# download elasticsearch
wget -q -c https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-8.17.2-amd64.deb
wget -q -c https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-8.17.2-amd64.deb.sha512
shasum -a 512 -c elasticsearch-8.17.2-amd64.deb.sha512 
# install elasticsearch
dpkg -i elasticsearch-8.17.2-amd64.deb
# remove redundant installation files
rm elasticsearch-8.17.2-amd64.deb

# download kibana
wget -q -c https://artifacts.elastic.co/downloads/kibana/kibana-8.17.2-amd64.deb
shasum -a 512 kibana-8.17.2-amd64.deb 
# install kibana
dpkg -i kibana-8.17.2-amd64.deb
# remove redundant installation files
rm kibana-8.17.2-amd64.deb

# fetch all private IPs in Auto Scaling Group
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
LOCAL_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region)

# query private IPs of all instances in the Auto Scaling Group
SEED_HOSTS=$(aws ec2 describe-instances \
--region $REGION \
--filters "Name=tag:Name,Values=ASG-data-node" "Name=instance-state-name,Values=running" \
--query "Reservations[*].Instances[*].PrivateIpAddress" \
--output text | tr '\n' ',' | sed 's/,$//')

echo "Discovered Seed Hosts: $SEED_HOSTS"

# determine if this node should be part of the initial master nodes, take first 3 nodes
MASTER_NODES=$(echo "$SEED_HOSTS" | cut -d',' -f1-3)

echo "Master Nodes are: $MASTER_NODES"

if echo "$MASTER_NODES" | grep -q "$LOCAL_IP"; then
    INITIAL_MASTER_NODES="cluster.initial_master_nodes: [$MASTER_NODES]"
else
    INITIAL_MASTER_NODES=""
fi

# copy certificate for the ssl
cp /etc/elasticsearch/certs/http_ca.crt /usr/local/share/ca-certificates/
update-ca-certificates

# Update Elasticsearch config
bash -c "cat > /etc/elasticsearch/elasticsearch.yml <<EOL
cluster.name: my-cluster
node.name: $INSTANCE_ID
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
network.host: 0.0.0.0
discovery.seed_hosts: [$SEED_HOSTS]
$INITIAL_MASTER_NODES
xpack.security.enabled: false
xpack.security.enrollment.enabled: true
xpack.security.http.ssl:
  enabled: true
  keystore.path: certs/http.p12
xpack.security.transport.ssl:
  enabled: false
  verification_mode: certificate
  keystore.path: certs/transport.p12
  truststore.path: certs/transport.p12
http.host: 0.0.0.0
EOL"

# enable and start the services
systemctl daemon-reload
systemctl enable elasticsearch
systemctl start elasticsearch
systemctl enable kibana
systemctl start kibana

# Setup auto-update script, for each 5 minutes the nodes checks if there is a new node created and add it to the seed_hosts
cat << 'EOF' > /usr/local/bin/update_es_hosts.sh
#!/bin/bash
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region)

SEED_HOSTS=$(aws ec2 describe-instances \
--region $REGION \
--filters "Name=tag:Name,Values=ASG-data-node" "Name=instance-state-name,Values=running" \
--query "Reservations[*].Instances[*].PrivateIpAddress" \
--output text | tr '\n' ',' | sed 's/,$//')

CURRENT_CONFIG=$(grep 'discovery.seed_hosts' /etc/elasticsearch/elasticsearch.yml | awk -F'[][]' '{print $2}' | tr -d ' ')

if [ "$SEED_HOSTS" != "$CURRENT_CONFIG" ]; then
  sed -i "s|discovery.seed_hosts: \[.*\]|discovery.seed_hosts: [$SEED_HOSTS]|" /etc/elasticsearch/elasticsearch.yml
  echo "Updated discovery.seed_hosts to: $SEED_HOSTS"
  systemctl restart elasticsearch
fi
EOF

chmod +x /usr/local/bin/update_es_hosts.sh

# Add cron job to run every 5 minutes
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/update_es_hosts.sh") | crontab -
