#!/bin/bash

# update 
apt-get update -y
apt update -y

# install unzip for aws
apt install -y unzip

# java
sudo apt update -y
sudo apt install -y openjdk-11-jdk

# download and install aws
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
# remove redundant installation files
rm awscliv2.zip
rm -rf aws

# # install docker
# for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done
# # Add Docker's official GPG key:
# apt-get update
# apt-get install ca-certificates curl
# install -m 0755 -d /etc/apt/keyrings
# curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
# chmod a+r /etc/apt/keyrings/docker.asc

# # Add the repository to Apt sources:
# echo \
#   "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
#   $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
#   tee /etc/apt/sources.list.d/docker.list > /dev/null
# apt-get update
# apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# AWS_REGION="${var.aws_region}"
# SEED_HOSTS=$(aws ec2 describe-instances \
#     --filters "Name=tag:aws:autoscaling:groupName,Values=${aws_autoscaling_group.es.name}" \
#     --query "Reservations[*].Instances[*].PrivateIpAddress" \
#     --region $AWS_REGION --output text | tr '\t' ',')

# docker run -d --name elasticsearch \
#   -e "node.name=$(hostname)" \
#   -e "cluster.name=my-cluster" \
#   -e "discovery.seed_hosts=$SEED_HOSTS" \
#   -e "cluster.initial_master_nodes=$SEED_HOSTS" \
#   -e "xpack.security.enabled=false" \
#   -e "ES_JAVA_OPTS=-Xms512m -Xmx512m" \
#   -p 9200:9200 -p 9300:9300 \
#   docker.elastic.co/elasticsearch/elasticsearch:8.17.2

# download elasticsearch
wget -c https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-8.17.2-amd64.deb
wget -c https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-8.17.2-amd64.deb.sha512
shasum -a 512 -c elasticsearch-8.17.2-amd64.deb.sha512 
# install elasticsearch
dpkg -i elasticsearch-8.17.2-amd64.deb
# remove redundant installation files
rm elasticsearch-8.17.2-amd64.deb
# download kibana
wget -c https://artifacts.elastic.co/downloads/kibana/kibana-8.17.2-amd64.deb
shasum -a 512 kibana-8.17.2-amd64.deb 
# install kibana
dpkg -i kibana-8.17.2-amd64.deb
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

cp /etc/elasticsearch/certs/http_ca.crt /usr/local/share/ca-certificates/
update-ca-certificates

# Update Elasticsearch config
sudo bash -c "cat > /etc/elasticsearch/elasticsearch.yml <<EOL
cluster.name: my-cluster
node.name: $INSTANCE_ID
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
network.host: 0.0.0.0
discovery.seed_hosts: [$SEED_HOSTS]
cluster.initial_master_nodes: [$SEED_HOSTS]
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

sudo systemctl daemon-reload
sudo systemctl enable elasticsearch
sudo systemctl start elasticsearch
sudo systemctl enable kibana.service
sudo systemctl start kibana.service