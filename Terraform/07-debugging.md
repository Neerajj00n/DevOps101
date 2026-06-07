# Common Errors & Debugging

Terraform errors fall into a small number of categories. Once you have seen each one a few times, you will recognise the pattern immediately. Here are the ones you will hit most often.

---

## Error Reading the Plan Output

Before debugging anything, read the plan carefully. Terraform tells you exactly what went wrong:

```
│ Error: creating EC2 Instance: InvalidParameterValue: ...
│
│   with aws_instance.web,
│   on main.tf line 12, in resource "aws_instance" "web":
│   12: resource "aws_instance" "web" {
```

The `with` line tells you which resource. The `on` line tells you where in your code. Start there.

---

## Provider / Authentication Errors

```
│ Error: No valid credential sources found
```

Terraform cannot find AWS credentials. Fix:

```bash
# Check what credentials are configured
aws sts get-caller-identity

# If that works but Terraform does not, check provider config
# Make sure your provider block matches your CLI profile

# Pass profile explicitly
provider "aws" {
  region  = "ap-south-1"
  profile = "prod"
}

# Or via environment variable
export AWS_PROFILE=prod
terraform plan
```

---

## State Lock Errors

```
│ Error: Error acquiring the state lock
│ Lock Info:
│   ID:   xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
│   Who:  joon@laptop
│   Created: 2024-06-01 10:00:00
```

Someone else (or a crashed previous run) holds the lock. Check if another apply is actually running first. If not:

```bash
terraform force-unlock xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

Never force-unlock while another apply is genuinely in progress.

---

## Resource Already Exists

```
│ Error: creating VPC: VpcLimitExceeded: The maximum number of VPCs has been reached
│ Error: creating Security Group: InvalidGroup.Duplicate: The security group 'web-sg' already exists
```

Two causes:

1. **AWS quota** — Request a limit increase in Service Quotas.
2. **Resource exists but is not in state** — Someone created it manually. Import it:

```bash
# Find the resource ID in AWS console or CLI
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=my-vpc" \
  --query 'Vpcs[0].VpcId' --output text

# Import it into state
terraform import aws_vpc.main vpc-0xxxxxxxxxxxxxxxx

# Now plan again — Terraform will show diffs and manage it going forward
terraform plan
```

---

## Dependency / Ordering Errors

```
│ Error: creating NAT Gateway: InvalidSubnetID.NotFound: The subnet ID 'subnet-xxx' does not exist
```

Terraform tried to create the NAT Gateway before the subnet was ready. Usually this means a missing reference (Terraform infers ordering from references):

```hcl
# Wrong — Terraform does not know nat_gateway depends on subnet
resource "aws_nat_gateway" "this" {
  subnet_id     = "subnet-hardcoded"   # hardcoded, no reference
  allocation_id = aws_eip.nat.id
}

# Right — Terraform sees the reference and waits for subnet to exist
resource "aws_nat_gateway" "this" {
  subnet_id     = aws_subnet.public[0].id   # reference creates implicit dependency
  allocation_id = aws_eip.nat.id
}

# If you genuinely need an explicit dependency
resource "aws_nat_gateway" "this" {
  depends_on = [aws_internet_gateway.this]
  ...
}
```

---

## Type Errors

```
│ Error: Incorrect attribute value type
│ Inappropriate value for attribute "cidr_block": string required
```

```hcl
# Wrong — passing a list where a string is expected
variable "vpc_cidr" {
  type = list(string)
  default = ["10.0.0.0/16"]
}
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr        # this is a list, not a string
}

# Right
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr[0]     # index into list
}
# Or fix the variable type
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}
```

---

## Cycle / Circular Dependency

```
│ Error: Cycle: aws_security_group.app, aws_security_group.db
```

Two resources reference each other creating a loop. Common with security groups that reference each other:

```hcl
# Broken — circular reference
resource "aws_security_group" "app" {
  ingress {
    security_groups = [aws_security_group.db.id]  # references db
  }
}
resource "aws_security_group" "db" {
  ingress {
    security_groups = [aws_security_group.app.id]  # references app — CYCLE
  }
}

# Fixed — use separate rules resources
resource "aws_security_group" "app" { ... }
resource "aws_security_group" "db"  { ... }

resource "aws_security_group_rule" "db_from_app" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.app.id
  security_group_id        = aws_security_group.db.id
}
```

---

## Plan Shows Unexpected Destroy/Recreate

```
  # aws_instance.web must be replaced
-/+ resource "aws_instance" "web" {
      ~ ami = "ami-old" -> "ami-new"  # forces replacement
```

`forces replacement` means changing this attribute requires destroying and recreating the resource. This causes downtime.

Options:
1. Accept it — schedule a maintenance window
2. Use `create_before_destroy` lifecycle to minimise downtime
3. Use `ignore_changes` to stop tracking that attribute

```hcl
resource "aws_instance" "web" {
  lifecycle {
    create_before_destroy = true
    ignore_changes = [ami]   # don't recreate when AMI changes
  }
}
```

---

## Debugging Commands

```bash
# Verbose logging — see every API call Terraform makes
export TF_LOG=DEBUG
terraform plan 2>&1 | tee /tmp/tf-debug.log

# Less verbose
export TF_LOG=INFO

# Log to file
export TF_LOG_PATH=/tmp/terraform.log

# Validate syntax without connecting to AWS
terraform validate

# Format all .tf files consistently
terraform fmt -recursive

# Check if state matches real infrastructure
terraform plan -refresh=true

# Targeted apply — only one resource (use carefully)
terraform apply -target=aws_vpc.main

# Show current state of a resource
terraform state show aws_instance.web
```

---

## The Debugging Checklist

When something goes wrong:

1. **Read the error message fully** — Terraform error messages are usually precise. The resource name and line number are in the output.
2. **Run `terraform validate`** — catches syntax and type errors before connecting to AWS.
3. **Run `terraform plan`** — see exactly what Terraform is trying to do.
4. **Check state** — `terraform state list` and `terraform state show` tell you what Terraform thinks exists.
5. **Check AWS** — does the resource actually exist in the console? If it was created manually, you need to import it.
6. **Enable debug logging** — `TF_LOG=DEBUG` shows every API call and response, which isolates exactly where things fail.

---

## Key Insight for DevOps

`terraform plan -target=resource_type.name` lets you plan or apply a single resource. This is useful for debugging but dangerous as a habit — it can leave your infrastructure in a partially-applied state where some resources are updated and others are not. Use it for debugging, not for regular workflow.
