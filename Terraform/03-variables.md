# Variables, Outputs & Locals

These three constructs are what turn a hardcoded Terraform file into something reusable and maintainable. Master them and your code will be clean. Skip them and you will end up copy-pasting the same values in twenty places.

---

## Input Variables

Variables are the parameters of your Terraform configuration. Declare them in `variables.tf`, set values in `terraform.tfvars` or via CLI flags.

```hcl
# variables.tf

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "instance_count" {
  description = "Number of instances to create"
  type        = number
  default     = 2
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection on RDS"
  type        = bool
  default     = true
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the ALB"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "db_config" {
  description = "RDS configuration"
  type = object({
    instance_class    = string
    allocated_storage = number
    engine_version    = string
  })
  default = {
    instance_class    = "db.t3.medium"
    allocated_storage = 100
    engine_version    = "15.4"
  }
}
```

---

## Setting Variable Values

Priority order (highest wins):
1. CLI flags: `-var="environment=prod"`
2. `.tfvars` file passed explicitly: `-var-file="prod.tfvars"`
3. `terraform.tfvars` or `terraform.tfvars.json` in working directory (auto-loaded)
4. `*.auto.tfvars` files (auto-loaded)
5. Environment variables: `TF_VAR_environment=prod`
6. Default value in declaration

```hcl
# terraform.tfvars  (for dev — do not commit if it has secrets)
aws_region    = "ap-south-1"
environment   = "dev"
instance_type = "t3.micro"

# prod.tfvars  (use with: terraform apply -var-file="prod.tfvars")
aws_region    = "ap-south-1"
environment   = "prod"
instance_type = "t3.large"
enable_deletion_protection = true
```

Sensitive variables (passwords, keys) should come from environment variables or a secrets manager, not `.tfvars` files committed to git.

```bash
# Pass secrets via env vars
export TF_VAR_db_password="mysecretpassword"
terraform apply
```

---

## Using Variables

```hcl
# main.tf
resource "aws_instance" "web" {
  instance_type = var.instance_type
  count         = var.instance_count

  tags = merge(var.tags, {
    Name        = "web-${var.environment}-${count.index}"
    Environment = var.environment
  })
}

resource "aws_db_instance" "main" {
  instance_class    = var.db_config.instance_class
  allocated_storage = var.db_config.allocated_storage
  engine_version    = var.db_config.engine_version
  deletion_protection = var.enable_deletion_protection
}
```

---

## Output Values

Outputs expose values from your Terraform configuration — useful for referencing between stacks, displaying important info after apply, or passing values to scripts.

```hcl
# outputs.tf

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = values(aws_subnet.private)[*].id
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "db_endpoint" {
  description = "RDS endpoint"
  value       = aws_db_instance.main.endpoint
  sensitive   = true   # won't show in plan/apply output, but stored in state
}

output "instance_public_ips" {
  description = "Public IPs of web instances"
  value       = aws_instance.web[*].public_ip
}
```

```bash
# View outputs after apply
terraform output
terraform output vpc_id
terraform output -json   # machine-readable

# Use in a script
VPC_ID=$(terraform output -raw vpc_id)
echo "VPC: $VPC_ID"
```

---

## Locals

Locals are computed values within your configuration. Think of them as variables you define once and reuse — but they are calculated from other values rather than set externally.

```hcl
# locals.tf

locals {
  # Computed name prefix used across many resources
  name_prefix = "${var.project}-${var.environment}"

  # Common tags merged with environment-specific ones
  common_tags = merge(var.tags, {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  })

  # AZ list from data source
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # Subnet CIDRs computed from VPC CIDR
  public_subnet_cidrs  = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnet_cidrs = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 8, i + 10)]

  # Conditional value
  instance_type = var.environment == "prod" ? "t3.large" : "t3.micro"
}
```

```hcl
# Using locals
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags       = merge(local.common_tags, { Name = "${local.name_prefix}-vpc" })
}

resource "aws_subnet" "public" {
  count             = length(local.azs)
  availability_zone = local.azs[count.index]
  cidr_block        = local.public_subnet_cidrs[count.index]
  tags              = merge(local.common_tags, { Name = "${local.name_prefix}-public-${count.index}" })
}
```

---

## Expressions & Functions

HCL has a rich set of built-in functions:

```hcl
# String functions
local.name_prefix = lower("${var.project}-${var.environment}")
local.bucket_name = replace(var.name, "_", "-")

# Collection functions
local.all_subnet_ids = concat(
  aws_subnet.public[*].id,
  values(aws_subnet.private)[*].id
)
local.unique_azs = toset(var.availability_zones)

# Numeric
local.half_count = ceil(var.instance_count / 2)

# CIDR
local.subnet_cidr = cidrsubnet("10.0.0.0/16", 8, 1)   # "10.0.1.0/24"
local.host_ip     = cidrhost("10.0.1.0/24", 10)        # "10.0.1.10"

# Conditional (ternary)
local.instance_type = var.environment == "prod" ? "t3.large" : "t3.micro"

# For expressions
local.instance_ids = [for i in aws_instance.web : i.id]
local.instance_map = {for i in aws_instance.web : i.tags["Name"] => i.id}

# Null coalescing
local.actual_name = coalesce(var.custom_name, "${local.name_prefix}-default")
```

---

## Key Insight for DevOps

Use `locals` for anything you reference more than twice. If you find yourself repeating `"${var.project}-${var.environment}"` in ten resources, put it in a local as `name_prefix` and reference `local.name_prefix`. When your project name changes, you change one line instead of ten.

Mark outputs as `sensitive = true` when they contain credentials or internal network details. They will still be stored in state (which is why state must be encrypted), but they will not appear in terminal output.
