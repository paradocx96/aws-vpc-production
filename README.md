# AWS VPC Production Infrastructure - Terraform

[![Terraform](https://img.shields.io/badge/Terraform-IaC-7B42BC?logo=terraform&logoColor=white)](https://developer.hashicorp.com/terraform)
[![AWS](https://img.shields.io/badge/Cloud-AWS-FF9900?logo=amazonaws&logoColor=white)](https://aws.amazon.com/)
[![Region](https://img.shields.io/badge/Default%20Region-ap--southeast--1-232F3E?logo=amazonaws&logoColor=white)](https://aws.amazon.com/about-aws/global-infrastructure/regions_az/)
[![License](https://img.shields.io/badge/License-not%20specified-lightgrey)](#license)

A production-oriented AWS networking foundation provisioned with **Terraform**. The repository focuses on a multi-AZ
VPC, subnet segmentation, controlled routing, security groups, network ACLs, private AWS service connectivity, and
centralized VPC Flow Logs.

> **Scope:** This repository builds the network foundation and supporting controls. It does not create an Application
> Load Balancer, application compute, a database, or application workloads. Those can be deployed into the relevant
> subnets by separate stacks.

## Table of contents

- [Architecture](#architecture)
- [Key capabilities](#key-capabilities)
- [Repository layout](#repository-layout)
- [Prerequisites](#prerequisites)
- [Backend and state](#backend-and-state)
- [Configuration](#configuration)
- [Deploy](#deploy)
- [Operate and troubleshoot](#operate-and-troubleshoot)
- [Cost considerations](#cost-considerations)
- [Security notes](#security-notes)
- [Teardown](#teardown)
- [Limitations and next steps](#limitations-and-next-steps)
- [License](#license)

## Architecture

<p>
  <img
    src="https://blogs.navindachandrasiri.com/images/blogs/blog-12/production-aws-vpc-architecture.webp"
    alt="Production AWS VPC Architecture"
    width="1024"
  />
</p>


[//]: # (```mermaid)
[//]: # (flowchart TB)
[//]: # (    Internet&#40;&#40;Internet&#41;&#41;)
[//]: # (    IGW[Internet Gateway])
[//]: # ()
[//]: # (subgraph VPC["VPC · default CIDR 10.0.0.0/16"])
[//]: # (subgraph Public["Public subnets · one per AZ"])
[//]: # (PubRT[Public route table<br/>0.0.0.0/0 → IGW])
[//]: # (NAT1[NAT Gateway · AZ A])
[//]: # (NAT2[NAT Gateway · AZ B])
[//]: # (NAT3[NAT Gateway · AZ C])
[//]: # (end)
[//]: # ()
[//]: # (subgraph Private["Private application subnets · one per AZ"])
[//]: # (PrivRT1[Private route table A])
[//]: # (PrivRT2[Private route table B])
[//]: # (PrivRT3[Private route table C])
[//]: # (AppSG[Application security group<br/>Ingress from ALB security group])
[//]: # (InterfaceEP[Interface VPC endpoints<br/>ECR · CloudWatch Logs · STS<br/>Secrets Manager · Systems Manager])
[//]: # (end)
[//]: # ()
[//]: # (subgraph Data["Data subnets · one per AZ"])
[//]: # (DataRT[Data route table<br/>No default internet route])
[//]: # (DataSG[Database security group<br/>Ingress from application security group])
[//]: # (end)
[//]: # ()
[//]: # (GWEP[Gateway VPC endpoints<br/>S3 · DynamoDB])
[//]: # (FlowLogs[VPC Flow Logs<br/>All traffic · CloudWatch Logs])
[//]: # (end)
[//]: # ()
[//]: # (Internet <--> IGW)
[//]: # (IGW --- PubRT)
[//]: # (PubRT --- NAT1)
[//]: # (PubRT --- NAT2)
[//]: # (PubRT --- NAT3)
[//]: # (NAT1 --> PrivRT1)
[//]: # (NAT2 --> PrivRT2)
[//]: # (NAT3 --> PrivRT3)
[//]: # (PrivRT1 --- AppSG)
[//]: # (PrivRT2 --- AppSG)
[//]: # (PrivRT3 --- AppSG)
[//]: # (PrivRT1 --- InterfaceEP)
[//]: # (PrivRT2 --- InterfaceEP)
[//]: # (PrivRT3 --- InterfaceEP)
[//]: # (GWEP --- PrivRT1)
[//]: # (GWEP --- PrivRT2)
[//]: # (GWEP --- PrivRT3)
[//]: # (GWEP --- DataRT)
[//]: # (AppSG --> DataSG)
[//]: # (VPC -. network telemetry .-> FlowLogs)
[//]: # (```)

The diagram illustrates the intended network paths. The Terraform configuration creates the VPC and network components
shown, but it **does not deploy the ALB, application, or database**. The ALB, application, and database security groups
are prepared as security boundaries for workloads deployed separately.

### Default subnet layout

With `vpc_cidr = "10.0.0.0/16"` and `az_count = 3`, the configuration calculates subnet CIDRs from the available
Availability Zones. The examples below assume the default `/16` network and the current subnet calculation logic.

| Tier    |  Subnet size | Example CIDRs                                  | Routing intent                                                                                           |
|---------|-------------:|------------------------------------------------|----------------------------------------------------------------------------------------------------------|
| Public  | `/24` per AZ | `10.0.0.0/24`, `10.0.1.0/24`, `10.0.2.0/24`    | Default route to Internet Gateway; used for NAT Gateways and public-facing resources deployed separately |
| Private | `/20` per AZ | `10.0.16.0/20`, `10.0.32.0/20`, `10.0.48.0/20` | Default route through NAT Gateway; private connectivity to configured interface endpoints                |
| Data    | `/24` per AZ | `10.0.10.0/24`, `10.0.11.0/24`, `10.0.12.0/24` | No default internet route; intended for data-tier resources                                              |

Subnet CIDRs depend on `vpc_cidr`, `az_count`, and the AZ ordering returned by AWS. Check the plan before applying
changes to a network that already has resources attached.

## Key capabilities

- **Multi-AZ VPC:** Uses 2–3 available Availability Zones; the default is three.
- **Three-tier subnet layout:** Separates public, private application, and data subnet tiers.
- **Controlled routing:** Separate route tables for public, private, and data tiers. Data subnets do not receive a
  default internet route.
- **NAT egress:** One NAT Gateway per AZ by default, with an optional single-NAT mode for lower-cost non-production
  environments.
- **VPC endpoints:** S3 and DynamoDB gateway endpoints, plus interface endpoints for ECR API, ECR Docker, CloudWatch
  Logs, STS, Secrets Manager, SSM, SSM Messages, and EC2 Messages.
- **Layered network controls:** Dedicated security groups for ALB, application, database, and interface endpoints;
  custom network ACLs for each subnet tier.
- **VPC Flow Logs:** Captures all VPC traffic to CloudWatch Logs with a 90-day log-group retention setting.
- **Consistent tagging:** Applies project, environment, and managed-by tags through provider-level default tags.
- **Terraform-managed infrastructure:** Resource definitions are split by responsibility across `.tf` files and expose
  useful outputs for downstream stacks.

## Repository layout

```text
.
├── backend.tf                  # S3 remote state configuration
├── providers.tf                # Terraform/provider constraints and AWS provider
├── variables.tf                # Input variables and validation
├── locals.tf                   # AZ and subnet CIDR calculations
├── vpc.tf                      # VPC, subnet tiers, Internet Gateway
├── nat.tf                      # NAT Gateways, routes, route tables, associations
├── endpoints.tf                # Gateway and interface VPC endpoints
├── security-groups.tf          # Tiered security groups and rules
├── nacls.tf                    # Tiered network ACLs and rules
├── flow-logs.tf                # CloudWatch log group, IAM role/policy, Flow Logs
├── outputs.tf                  # VPC, subnet, NAT IP and security-group outputs
├── terraform.tfvars.example    # Example variable values
└── .gitignore                  # Excludes local state, plans, and variable files
```

## Prerequisites

- An AWS account and permissions to manage the required VPC, EC2 networking, VPC endpoints, CloudWatch Logs, and IAM
  resources.
- AWS CLI configured using an approved profile, IAM Identity Center (SSO), or assumed role. Avoid long-lived access keys
  in source code.
- Terraform CLI **1.10 or later**. The S3 backend uses native state locking through `use_lockfile = true`; align the
  `required_version` constraint in `providers.tf` with this minimum before publishing/deploying broadly.
- An S3 bucket in the chosen backend region, created before `terraform init`.

Confirm the AWS identity before running Terraform:

```bash
aws sts get-caller-identity
```

## Backend and state

Terraform state is configured in `backend.tf` to use **Amazon S3**, with encryption enabled and native S3 state locking
(`use_lockfile = true`). The bucket must already exist; Terraform cannot bootstrap its own backend bucket.

**Before using or publishing this repository, update `backend.tf` so the bucket is one you own and the key is unique to
this project/state.** The checked-in configuration currently contains a concrete bucket name. Do not reuse another
project's state key or point multiple independent deployments at the same state file.

Recommended backend-bucket safeguards:

- Enable S3 bucket versioning so previous state versions can be recovered.
- Block public access and restrict access through least-privilege IAM.
- Use encryption at rest and TLS for requests.
- Keep the state bucket outside the infrastructure lifecycle managed by this repository.
- Back up or migrate existing state deliberately; do not delete state as a shortcut for repairing an apply.

Example one-time bucket bootstrap for Singapore (`ap-southeast-1`); replace the bucket name with a globally unique name:

```bash
aws s3api create-bucket \
  --bucket YOUR_UNIQUE_STATE_BUCKET_NAME \
  --region ap-southeast-1 \
  --create-bucket-configuration LocationConstraint=ap-southeast-1

aws s3api put-bucket-versioning \
  --bucket YOUR_UNIQUE_STATE_BUCKET_NAME \
  --versioning-configuration Status=Enabled

aws s3api put-public-access-block \
  --bucket YOUR_UNIQUE_STATE_BUCKET_NAME \
  --public-access-block-configuration \
  'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'
```

After editing `backend.tf`, initialize the backend:

```bash
terraform init
```

If you already have infrastructure tracked in local state and are intentionally migrating it to S3, back up the local
state and use `terraform init -migrate-state`, reviewing Terraform's migration prompts. For a new, empty deployment,
ordinary `terraform init` is appropriate.

## Configuration

Create a private variable file from the example:

```bash
cp terraform.tfvars.example terraform.tfvars
```

On PowerShell:

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` to match the intended account, region, and environment. The current example file includes
`aws_account_id`, which is not declared or consumed by the current Terraform configuration; remove that line unless you
also add a corresponding variable and validation logic. Choose a non-overlapping CIDR if this VPC may connect to
existing networks.

Example values for the variables currently declared in `variables.tf`:

```hcl
region             = "ap-southeast-1"
name               = "vpc-project"
environment        = "production"
vpc_cidr           = "10.0.0.0/16"
az_count           = 3
single_nat_gateway = false
app_port           = 8080
db_port            = 5432
```

| Variable             | Default          | Description                                                                  |
|----------------------|------------------|------------------------------------------------------------------------------|
| `region`             | `ap-southeast-1` | AWS region for the deployment                                                |
| `name`               | `vpc-project`    | Prefix used in resource names and tags                                       |
| `environment`        | `production`     | Environment tag                                                              |
| `vpc_cidr`           | `10.0.0.0/16`    | VPC IPv4 CIDR; subnet calculations assume a `/16`                            |
| `az_count`           | `3`              | Number of Availability Zones; validation allows 2 or 3                       |
| `single_nat_gateway` | `false`          | Use one shared NAT Gateway instead of one per AZ; cheaper but less resilient |
| `app_port`           | `8080`           | Application port allowed between ALB and app security groups                 |
| `db_port`            | `5432`           | Database port allowed from the app tier to the database tier                 |

`terraform.tfvars` and other real variable files are excluded from Git by `.gitignore`. Do not add credentials, private
keys, or secrets to Terraform variable files. Supply sensitive values through a dedicated secrets mechanism if a future
workload requires them.

## Deploy

Run commands from the repository root.

### 1. Initialize and validate

```bash
terraform init
terraform fmt -check -recursive
terraform validate
```

If formatting checks report changes, run `terraform fmt -recursive`, inspect the diff, and commit the formatted files.

### 2. Create and review a plan

```bash
terraform plan -var-file="terraform.tfvars" -out="tfplan"
terraform show tfplan
```

Review the full plan, especially the number of NAT Gateways, interface endpoints, open ingress rules, CIDR ranges, and
resources that will be replaced or destroyed.

### 3. Apply the reviewed plan

```bash
terraform apply tfplan
```

Use the saved plan you reviewed. If configuration or input values change, discard the old plan and generate a new one.

### 4. Inspect outputs and state

```bash
terraform output
terraform state list
terraform state show aws_vpc.this
```

Outputs include the VPC ID, public/private/data subnet IDs, NAT public IP addresses, and security-group IDs for use by
downstream infrastructure.

### Workspace and environment guidance

Terraform workspaces separate state instances; they do **not** choose the correct `.tfvars` file automatically. If using
workspaces, explicitly select one and pass its matching variable file on every plan/apply. For production-grade
separation, consider separate environment directories and backend keys, or separate AWS accounts for stronger
permissions and blast-radius boundaries. Never assume that creating a workspace creates a new AWS environment until you
apply its plan.

## Operate and troubleshoot

| Task                                      | Command                                                     |
|-------------------------------------------|-------------------------------------------------------------|
| Show current workspace                    | `terraform workspace show`                                  |
| List workspaces                           | `terraform workspace list`                                  |
| List resources in the selected state      | `terraform state list`                                      |
| Inspect a resource in state               | `terraform state show aws_vpc.this`                         |
| Refresh-only plan                         | `terraform plan -refresh-only -var-file="terraform.tfvars"` |
| See plan details                          | `terraform show tfplan`                                     |
| Reinitialize after backend/module changes | `terraform init`                                            |

### Common issues

- **Backend bucket not found:** Create the S3 bucket first and verify the backend region and bucket name in
  `backend.tf`.
- **AccessDenied on IAM operations:** The deployment identity may need narrowly scoped permissions to create/manage the
  Flow Logs role and pass that role to `vpc-flow-logs.amazonaws.com`. Permissions boundaries and organization policies
  can also restrict actions.
- **Unexpected resources in plan:** Check the active workspace, variable file, backend key, AWS account, and region
  before applying.
- **Deletion blocked:** Check for dependent resources such as ENIs or other resources still attached to the VPC; address
  dependencies and generate a fresh plan.

## Cost considerations

This is a network foundation, not a free resource bundle. Costs depend on region, uptime, and traffic.

- **NAT Gateways:** Billed hourly and for data processing. With the default `single_nat_gateway = false` and three AZs,
  three NAT Gateways and three Elastic IP allocations are planned.
- **Interface VPC endpoints:** Billed per endpoint per AZ and for data processing. The configuration defines eight
  interface endpoints and places them in each private subnet/AZ.
- **Gateway endpoints:** S3 and DynamoDB gateway endpoints have no hourly endpoint charge, though the services and any
  other data transfer remain subject to their own pricing.
- **CloudWatch Logs:** VPC Flow Logs can incur log ingestion and storage charges; this configuration retains the log
  group for 90 days.
- **Data transfer:** NAT, endpoint, and internet data transfer can add variable costs.

For lower-cost development or test environments, `single_nat_gateway = true` reduces the number of NAT Gateways but
creates a single point of egress failure and can introduce cross-AZ traffic. Use the mode that matches your availability
and cost requirements. Check the AWS Pricing Calculator and the plan before deployment.

## Security notes

- Keep state in a private, versioned S3 bucket and use least-privilege IAM.
- Use short-lived AWS credentials where possible; never commit credentials or real `*.tfvars` files.
- Review the public security-group ingress rules (HTTP/HTTPS from the internet) and ensure those groups are attached
  only to intended public-facing resources.
- The application security group accepts traffic from the ALB security group; the database security group accepts the
  configured DB port from the application security group.
- Network ACLs are stateless; review both ingress and egress rules alongside security groups before changing them.
- The current data subnets intentionally have no default route to the internet. Validate required AWS service
  connectivity before placing workloads there.
- The repository is a networking baseline. Perform environment-specific threat modelling, compliance review, and
  security testing before using it for a real production workload.

## Teardown

Destroying this configuration removes the AWS resources managed by the selected state and can interrupt any workloads
attached to the VPC. Confirm the account, region, workspace, backend key, and dependencies before proceeding.

```bash
terraform workspace show
aws sts get-caller-identity
terraform plan -destroy -var-file="terraform.tfvars" -out="destroy.tfplan"
terraform show destroy.tfplan
terraform apply destroy.tfplan
```

Do not destroy the remote state bucket as part of routine teardown. Afterward, verify that the VPC and billable
resources (especially NAT Gateways, interface endpoints, and Elastic IP allocations) are removed in the AWS Console.
CloudWatch log groups and IAM roles should also be checked because separate resources may persist if they were not
tracked by the selected state.

## Limitations and next steps

Potential improvements for a portfolio-ready evolution of this repository:

- Align the Terraform `required_version` constraint with the minimum version needed by the S3 backend's native lock-file
  setting.
- Parameterize or partially configure the S3 backend so a fork does not use a bucket name tied to another deployment.
- Add CI checks for `terraform fmt -check`, `terraform validate`, and a safe plan review workflow.
- Add automated policy checks (for example, Checkov or TFLint) and a documented threat model.
- Add reusable modules and per-environment state/permissions if the project grows beyond a single networking stack.
- Add an explicit `LICENSE` file before presenting the repository as open source.

## License

No license is included in the supplied repository. Until a license is added, reuse and redistribution rights are not
explicitly granted. Add a license that matches your intent before publishing this project as open source.
