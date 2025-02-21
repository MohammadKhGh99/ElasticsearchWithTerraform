#!/bin/bash

# update 
sudo apt-get update -y
sudo apt update -y

# install unzip for aws
sudo apt install -y unzip

# download and install aws
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
# remove redundant installation files
rm awscliv2.zip
rm -rf aws

# download elasticsearch
wget -c https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-8.17.2-amd64.deb
wget -c https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-8.17.2-amd64.deb.sha512
shasum -a 512 -c elasticsearch-8.17.2-amd64.deb.sha512 
# install elasticsearch
sudo dpkg -i elasticsearch-8.17.2-amd64.deb
# remove redundant installation files
rm elasticsearch-8.17.2-amd64.deb
# download kibana
wget -c https://artifacts.elastic.co/downloads/kibana/kibana-8.17.2-amd64.deb
shasum -a 512 kibana-8.17.2-amd64.deb 
# install kibana
sudo dpkg -i kibana-8.17.2-amd64.deb
# remove redundant installation files
rm kibana-8.17.2-amd64.deb

# Fetch all private IPs in Auto Scaling Group
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
LOCAL_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region)

# Query private IPs of all instances in the Auto Scaling Group
SEED_HOSTS=$(aws ec2 describe-instances \
--region $REGION \
--filters "Name=tag:Name,Values=ASG-data-node" "Name=instance-state-name,Values=running" \
--query "Reservations[*].Instances[*].PrivateIpAddress" \
--output text | tr '\n' ',' | sed 's/,$//')

echo "Discovered Seed Hosts: $SEED_HOSTS"

# Update Elasticsearch config
sudo bash -c "cat > /etc/elasticsearch/elasticsearch.yml <<EOL
cluster.name: my-cluster
node.name: $INSTANCE_ID
network.host: _site_
discovery.seed_hosts: ["$SEED_HOSTS"]
cluster.initial_master_nodes: [$INSTANCE_ID]
bootstrap.memory_lock: true
xpack.security.enabled: false
xpack.security.transport.ssl.enabled: false
EOL"

sudo systemctl daemon-reload
sudo systemctl enable elasticsearch
sudo systemctl start elasticsearch
sudo systemctl enable kibana.service
sudo systemctl start kibana.service