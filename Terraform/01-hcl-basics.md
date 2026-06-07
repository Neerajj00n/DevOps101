# HCL Basics & Core Concepts

Terraform uses HCL (HashiCorp Configuration Language) — a declarative language where you describe *what* you want, not *how* to get there. Terraform figures out the how.

---

## The Basic Workflow

```
Write HCL → terraform init → terraform plan → terraform apply → terraform destroy
```

- **init** — downloads providers and sets up the backend. Run once per project, and again when you add a new provider.
- **plan** — shows what Terraform *will* do. Always read it before applying.
- **apply** — makes the changes. Prompts for confirmation unless you pass `-auto-approve`.
- **destroy** — tears everything down. Dangerous in production — always plan first.

---

## Project Structure

```
my-infra/
├── main.tf           → resources
├── variables.tf      → input variable declarations
├── outputs.tf        → output value declarations
├── providers.tf      → provider configuration
├── versions.tf       → Terraform and provider version constraints
├── locals.tf         → local computed values
└── terraform.tfvars  → actual variable values (gitignore this if it has secrets)
```

For larger projects, split `main.tf` into logical files: `vpc.tf`, `ec2.tf`, `iam.tf`, etc. Terraform reads all `.tf` files in a directory together.

---

## Providers

Providers are plugins that know how to talk to a specific API (AWS, GCP, Kubernetes, GitHub, etc.)

```hcl
# versions.tf
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"   # >= 5.0.0, < 6.0.0
    }
  }
}

# providers.tf
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "devops-course"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
```

`default_tags` on the provider applies tags to every resource automatically — a good habit.

---

## Resources

A resource is any infrastructure object Terraform manages.

```hcl
# Syntax: resource "PROVIDER_TYPE" "LOCAL_NAME" { ... }
resource "aws_instance" "web" {
  ami           = "ami-0xxxxxxxxxxxxxxxx"
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.public.id   # reference another resource

  tags = {
    Name = "web-server"
  }
}
```

The `LOCAL_NAME` (here `web`) is how you reference this resource elsewhere in your code. It has no effect on AWS.

To reference an attribute of another resource: `RESOURCE_TYPE.LOCAL_NAME.ATTRIBUTE`
```hcl
aws_instance.web.id
aws_subnet.public.id
aws_vpc.main.cidr_block
```

---

## Core Resource Examples

```hcl
# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "main-vpc" }
}

# Subnet
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true

  tags = { Name = "public-subnet-a" }
}

# Security Group
resource "aws_security_group" "web" {
  name   = "web-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"         # all traffic
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 Instance
resource "aws_instance" "web" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.web.name

  user_data = <<-EOT
    #!/bin/bash
    apt-get update -y
    apt-get install -y nginx
    systemctl enable nginx && systemctl start nginx
  EOT

  tags = { Name = "web-01" }
}
```

---

## Meta-Arguments

These work on any resource:

```hcl
# count — create multiple copies
resource "aws_instance" "web" {
  count         = 3
  instance_type = "t3.micro"
  ami           = data.aws_ami.ubuntu.id

  tags = { Name = "web-${count.index}" }   # web-0, web-1, web-2
}

# Reference: aws_instance.web[0].id, aws_instance.web[*].id

# for_each — create from a map or set (more flexible than count)
resource "aws_subnet" "private" {
  for_each = {
    "ap-south-1a" = "10.0.3.0/24"
    "ap-south-1b" = "10.0.4.0/24"
  }

  vpc_id            = aws_vpc.main.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = { Name = "private-${each.key}" }
}

# Reference: aws_subnet.private["ap-south-1a"].id

# depends_on — explicit dependency (usually Terraform figures this out automatically)
resource "aws_instance" "app" {
  depends_on = [aws_nat_gateway.main]
  ...
}

# lifecycle — control create/destroy behaviour
resource "aws_instance" "web" {
  lifecycle {
    create_before_destroy = true   # create new before destroying old (useful for ALB targets)
    prevent_destroy       = true   # block terraform destroy (use in prod)
    ignore_changes        = [ami]  # don't update if AMI changes (manage via ASG instead)
  }
}
```

---

## The Dependency Graph

Terraform builds a graph of all your resources and their dependencies, then applies them in parallel where possible. You never need to specify order — Terraform infers it from resource references.

```
aws_vpc.main
    ↓
aws_subnet.public_a          aws_security_group.web
    ↓                              ↓
aws_nat_gateway.main      aws_instance.web
```

If you create a reference (`subnet_id = aws_subnet.public_a.id`), Terraform knows the subnet must exist before the instance.

---

## Key Insight for DevOps

Always run `terraform plan` before `terraform apply` — every single time. Read the entire plan output. A `+` means create, `-` means destroy, `~` means modify. A `+/-` means destroy-then-recreate, which means downtime if it is a critical resource.

Terraform shows you exactly what it will do before it does it. The engineers who cause outages are the ones who skip the plan.
