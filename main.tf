terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = ">=5.55"
    }
  }
  required_version = ">= 1.7.0"
}

provider "aws" {
  region = var.region
}

# VPC - 2.1
resource "aws_vpc" "private-vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "elasticsearch-vpc"
  }
}

# Subnets - 2.1
resource "aws_subnet" "public_subnet" {
  vpc_id = aws_vpc.private-vpc.id
  cidr_block = "10.0.4.0/24"
  map_public_ip_on_launch = true
  availability_zone = "us-east-1a"

  tags = {
    Name = "public-subnet"
  }
}
resource "aws_subnet" "subnets" {
  count = 3
  vpc_id = aws_vpc.private-vpc.id
  cidr_block = "10.0.${count.index}.0/24"
  availability_zone = element(["us-east-1a", "us-east-1b", "us-east-1c"], count.index)

  tags = {
    Name = "private-subnet-${count.index}"
  } 
}

# Internet Gateway
resource "aws_internet_gateway" "elasticsearch_igw" {
  vpc_id = aws_vpc.private-vpc.id

  tags = {
    Name = "elasticsearch-igw"
  }
}

resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name = "nat_eip"
  }
}

# NAT Gateway
resource "aws_nat_gateway" "my_nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id

  tags = {
    Name = "my_nat"
  }

  depends_on = [aws_internet_gateway.elasticsearch_igw]
}

# Public Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.private-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.elasticsearch_igw.id
  }

  tags = {
    Name = "elasticsearch-public-rt"
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# Private route table
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.private-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.my_nat.id
  }

  tags = {
    Name = "elasticsearch-private-rt"
  }
}

resource "aws_route_table_association" "private_assoc" {
  count = 3
  subnet_id      = aws_subnet.subnets[count.index].id
  route_table_id = aws_route_table.private_rt.id
}

# EC2s - 1.1
resource "aws_instance" "public_instance" {
  vpc_security_group_ids = [aws_security_group.public_instance_sg.id]
  ami = var.ec2_ami
  key_name = var.key_pair
  subnet_id = aws_subnet.public_subnet.id
  instance_type = "t2.micro"

  # user_data = base64encode(<<-EOF
  #             #!/bin/bash
  #             sudo apt-get update
  #             wget -c https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-8.17.2-amd64.deb
  #             wget -c https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-8.17.2-amd64.deb.sha512
  #             shasum -a 512 -c elasticsearch-8.17.2-amd64.deb.sha512 
  #             EOF
  # )

  tags = {
    Terraform = true
    Name = "public_instance"
  }
}
resource "aws_launch_template" "data-nodes-lt" {
  name_prefix = "data-node"

  image_id = var.ec2_ami
  instance_type = "t2.medium"
  vpc_security_group_ids = [aws_security_group.cluster_security_group.id]
  ebs_optimized = true
  key_name = var.key_pair

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_elasticsearch_instance_profile.name
  }

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_type = "gp3"
      volume_size = 20
    }
  }

  user_data = base64encode(file("${path.module}/user-data.sh"))

  tags = {
    Terraform = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
        Name = "ASG-data-node"
    }
  }
}

resource "aws_iam_role" "ec2_elasticsearch_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "ec2_elasticsearch_policy" {
  name        = "EC2ElasticsearchPolicy"
  description = "Allow EC2 instances to query other instances for Elasticsearch discovery"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_policy" {
  role       = aws_iam_role.ec2_elasticsearch_role.name
  policy_arn = aws_iam_policy.ec2_elasticsearch_policy.arn
}

resource "aws_iam_instance_profile" "ec2_elasticsearch_instance_profile" {
  name = "ec2-elasticsearch-instance-profile"
  role = aws_iam_role.ec2_elasticsearch_role.name
}

# Auto Scaling Group - 1.2
resource "aws_autoscaling_group" "data-nodes" {
  desired_capacity = 3
  min_size = 2
  max_size = 5
  vpc_zone_identifier = aws_subnet.subnets[*].id

  launch_template {
    id = aws_launch_template.data-nodes-lt.id
  }

  tag {
    key = "Terraform"
    value = true
    propagate_at_launch = true
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "high-cpu-usage"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Alarm when CPU exceeds 70%"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.data-nodes.name
  }
  actions_enabled     = true
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]
}

resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 120
  autoscaling_group_name = aws_autoscaling_group.data-nodes.name
}

resource "aws_security_group" "public_instance_sg" {
  name = "public_instance_sg"
  description = "Allow ssh communication from public IPs"
  vpc_id = aws_vpc.private-vpc.id

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "public_instance_sg"
  }
}

resource "aws_security_group" "cluster_security_group" {
  name = "cluster_security_group"
  description = "Allow communication only within cluster"
  vpc_id = aws_vpc.private-vpc.id

  # ingress {
  #   from_port = 9200
  #   to_port = 9200
  #   protocol = "tcp"
  # }

  # ingress {
  #   from_port = 9300
  #   to_port = 9300
  #   protocol = "tcp"
  # }

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    security_groups = [aws_security_group.public_instance_sg.id]
    cidr_blocks = ["10.0.0.0/16"]
  }

  # If there is a need for external access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Elasticsearch-cluster-sg"
  }
}

# resource "aws_security_group_rule" "allow_ssh_from_public_instance" {
#   type                     = "ingress"
#   from_port                = 22
#   to_port                  = 22
#   protocol                 = "tcp"
#   source_security_group_id = aws_security_group.public_instance_sg.id
#   security_group_id        = aws_security_group.cluster_security_group.id
# }
