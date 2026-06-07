# Modules

Modules are how you package and reuse Terraform code. A module is just a directory of `.tf` files. When you find yourself copying the same VPC or EKS cluster config across projects, that code should be a module.

---

## Why Modules

Without modules:
- You copy-paste the same 200 lines of VPC code for every project
- A bug fix means updating it in 5 places
- No consistency between environments

With modules:
- VPC logic lives in one place
- All projects import it and pass their own variables
- Fix once, benefit everywhere

---

## Module Structure

```
modules/
└── vpc/
    ├── main.tf        → resources
    ├── variables.tf   → inputs (what the caller must/can pass)
    ├── outputs.tf     → outputs (what the caller can use)
    └── README.md      → how to use this module

    (no provider blocks — the caller provides the provider)
    (no backend config — the caller manages state)
```

---

## Writing a VPC Module

```hcl
# modules/vpc/variables.tf
variable "name" {
  description = "Name prefix for all resources"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of AZs to deploy subnets into"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "Whether to create a NAT Gateway"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
```

```hcl
# modules/vpc/main.tf
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, { Name = "${var.name}-vpc" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-igw" })
}

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.name}-public-${var.availability_zones[count.index]}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.tags, {
    Name = "${var.name}-private-${var.availability_zones[count.index]}"
    Tier = "private"
  })
}

resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.name}-nat-eip" })
}

resource "aws_nat_gateway" "this" {
  count = var.enable_nat_gateway ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(var.tags, { Name = "${var.name}-nat" })
  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(var.tags, { Name = "${var.name}-public-rt" })
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.this[0].id
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-private-rt" })
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
```

```hcl
# modules/vpc/outputs.tf
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "nat_gateway_ip" {
  description = "Elastic IP of the NAT Gateway"
  value       = var.enable_nat_gateway ? aws_eip.nat[0].public_ip : null
}
```

---

## Calling a Module

```hcl
# main.tf (in your root config)

module "vpc" {
  source = "./modules/vpc"      # local path

  name                 = "myapp-prod"
  vpc_cidr             = "10.0.0.0/16"
  availability_zones   = ["ap-south-1a", "ap-south-1b"]
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.3.0/24", "10.0.4.0/24"]
  enable_nat_gateway   = true

  tags = {
    Environment = "prod"
    Project     = "myapp"
    ManagedBy   = "terraform"
  }
}

# Use module outputs elsewhere
resource "aws_instance" "app" {
  subnet_id = module.vpc.private_subnet_ids[0]
  ...
}

output "vpc_id" {
  value = module.vpc.vpc_id
}
```

---

## Module Sources

```hcl
# Local path
source = "./modules/vpc"
source = "../shared-modules/vpc"

# Terraform Registry (public modules)
source  = "terraform-aws-modules/vpc/aws"
version = "~> 5.0"

# Git repository
source = "git::https://github.com/myorg/terraform-modules.git//vpc"
source = "git::https://github.com/myorg/terraform-modules.git//vpc?ref=v1.2.0"

# S3 bucket
source = "s3::https://s3.amazonaws.com/my-modules/vpc.zip"
```

After adding or changing a module source, always run `terraform init` again.

---

## Module Versioning

When using Git-based or registry modules, always pin versions:

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"   # exact version — safest
  # version = "~> 5.1"  # >= 5.1.0, < 6.0.0
}
```

Unpinned modules break when the upstream module adds a breaking change. This has caused production outages.

---

## Key Insight for DevOps

The best modules have narrow scope and clear interfaces. A `vpc` module should create a VPC and nothing else — not EC2 instances, not RDS. Keep modules focused, document every variable and output, and treat the module interface as a contract.

When you find a public module on the Terraform Registry (like `terraform-aws-modules/vpc/aws`), read its source before using it in production. Understanding what it creates — and what it does not — is your responsibility.
