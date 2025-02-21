# ElasticsearchWithTerraform

Scaling Elasticsearch on AWS EC2 using Terraform
We are given a setup where Elasticsearch is installed on a single EC2 instance.
Our task is to modify this setup and implement a scalable Elasticsearch cluster using Terraform.

**Requirements:**

- **Deploy a Highly Available Elasticsearch Cluster**
  - To meet this requirement, I made an **Auto Scaling Group** which have 2 as minimum number of instances and 5 as maximum number of instances, and the desired capacity in realtime is 3 as required, they deployed in **3 different availability zones**.
  - If there is a high usage of cpu the ASG scale up, and if we want to scale up or down manually we can just modify the **desired_capacity in the main.tf file** to whatever number we want but not smaller that the minimum and not bigger than the maximum.
- **Ensure Secure & Optimized Deployment**
  - For security, a private VPC with no public access has been made.
  - For more Security, a security group that allow only communications within the cluster has been made and attched to the nodes.
  - For optimization, we should use the EBS optimization with GP3 storage to ensure perfect performance.
- **Automate Cluster Configuration**
  - All this made with an IaC terraform to easily handle AWS services we want.
  - Elasticsearch node discovery has been made by collecting the private IPs of all the nodes that elasticsearch run on them and save them as the nodes that combine the cluster in each time a new node been created.
  - Running Elasticsearch handled by systemd to enable running the service when the node created automatically.

## Prerequisites

- AWS account
- Terraform installed, if not follow [this guide](https://learn.hashicorp.com/tutorials/terraform/install-cli?in=terraform/aws-get-started)
- AWS CLI configured

## Configuration

- Add tfvars file to set the variables in [varibales.tf](variables.tf) file.

## Setup

**Note:**\
For **plan** or **apply** command in terraform we used varibales, there are two ways to set them: with **tfvars** file or **manually** in terminal when running plan or apply command.\
See [variables.tf](variables.tf) file for more details about which variables to set

1. Clone the repository:

    ```sh
    git clone https://github.com/yourusername/ElasticsearchWithTerraform.git
    cd ElasticsearchWithTerraform
    ```

2. Initialize Terraform:

    ```sh
    terraform init
    ```

3. Plan the deployment:

    ```sh
    terraform plan
    ```

    **OR**

    ```sh
    terraform plan -var-file=<filename>
    ```

4. Apply the deployment:

    ```sh
    terraform apply
    ```

    **OR**

    ```sh
    terraform apply -var-file=<filename>
    ```

## Cleanup

To destroy the infrastructure created by Terraform, run:

  ```sh
    terraform destroy
  ```

If you used tfvars in apply command you have to specify the tfvars when using **destroy** command.

  ```sh
    terraform destroy -var-file=<filename>
  ```

## Deploying the Cluster

To deploy the Elasticsearch cluster, follow the steps in the [Setup](#setup) section. This will initialize, plan, and apply the Terraform configuration to create the necessary AWS infrastructure.

## Node Discovery

Elasticsearch nodes discover each other by adding the private EC2 IPs in "discovery.seed_hosts" field to the file "/etc/elasticsearch/elasticsearch.yml" when each private EC2 created, they added by default by the user data file.
This has been made by using describe-instances command from aws cli.

## Scaling Data Nodes

To scale the data nodes, you can adjust the `desired_capacity` parameter in the `variables.tf` file. After modifying this value, run the following commands to apply the changes:

```sh
terraform plan
terraform apply
```

***Remember to add `-var-file` option if you are using `tfvars` file.***

This will update the Auto Scaling group to the desired number of data nodes.
Or if the CPU has got 70% or more of his power usage in at least one of the instances.
