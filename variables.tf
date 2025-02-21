variable "region" {
  description = "AWS region"
  type = string
}

variable "ec2_ami" {
  description = "AMI id for EC2s"
  type = string
}

variable "key_pair" {
  description = "key pair name for accessing ec2"
  type = string
}

variable "instance_type" {
    description = "EC2 instance type for launch template for auto scaling group"
    type = string
}

variable "availability_zones" {
  description = "The availability zone to deploy the resources"
  type        = list(string)
}