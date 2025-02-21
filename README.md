# ElasticsearchWithTerraform

Scaling Elasticsearch on AWS EC2 using Terraform

## Prerequisites

- AWS account
- Terraform installed, if not follow [this guide](https://learn.hashicorp.com/tutorials/terraform/install-cli?in=terraform/aws-get-started)
- AWS CLI configured

## Setup

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

4. Apply the deployment:

    ```sh
    terraform apply
    ```

## Configuration

- Modify the `variables.tf` file to customize your deployment.

## Cleanup

To destroy the infrastructure created by Terraform, run:

```sh
terraform destroy
```

## Deploying the Cluster

To deploy the Elasticsearch cluster, follow the steps in the [Setup](#setup) section. This will initialize, plan, and apply the Terraform configuration to create the necessary AWS infrastructure.

## Node Discovery

Elasticsearch nodes discover each other by adding the private EC2 IPs in "discovery.seed_hosts" field to the file "/etc/elasticsearch/elasticsearch.yml" when each private EC2 created, they added by default by the user data file.

## Scaling Data Nodes

To scale the data nodes, you can adjust the `desired_capacity` parameter in the `variables.tf` file. After modifying this value, run the following commands to apply the changes:

```sh
terraform plan
terraform apply
```

This will update the Auto Scaling group to the desired number of data nodes.
Or if the CPU has got 70% or more of his power usage in at least one of the instances.
