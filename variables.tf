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