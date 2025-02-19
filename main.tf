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
  region = "us-east-1"
}

resource "aws_vpc" "private-vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "private-vpc"
  }
}

resource "aws_subnet" "subnet1" {
  vpc_id = aws_vpc.private-vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "subnet-1"
  } 
}

resource "aws_subnet" "subnet2" {
  vpc_id = aws_vpc.private-vpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "subnet-2"
  } 
}

resource "aws_instance" "elastic-ec2-1" {
  ami = "ami-04b4f1a9cf54c11d0"
  instance_type = "t2.micro"
  availability_zone = "us-east-1a"

  tags = {
    Name = "elastic ec2-1"
    Terraform = true
  }
}

resource "aws_instance" "elastic-ec2-2" {
  ami = "ami-04b4f1a9cf54c11d0"
  instance_type = "t2.micro"
  availability_zone = "us-east-1b"

  tags = {
    Name = "elastic ec2-2"
    Terraform = true
  }
}

resource "aws_instance" "elastic-ec2-3" {
  ami = "ami-04b4f1a9cf54c11d0"
  instance_type = "t2.micro"
  availability_zone = "us-east-1c"

  tags = {
    Name = "elastic ec2-3"
    Terraform = true
  }
}

resource "aws_launch_template" "data-nodes-lt" {
  name_prefix = "data-node"
  image_id = "ami-04b4f1a9cf54c11d0"
  instance_type = "t2.micro"

  tag_specifications {
    resource_type = "instance"
    tags = {
        Name = "ASG-data-node"
    }
  }
}

resource "aws_autoscaling_group" "data-nodes" {
  desired_capacity = 2
  min_size = 2
  max_size = 5
  vpc_zone_identifier = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]

  launch_template {
    id = aws_launch_template.data-nodes-lt.id
  }
}

resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.data-nodes.name
}


