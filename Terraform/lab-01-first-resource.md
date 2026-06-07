# Lab 01 — Your First Terraform Resource

**Goal:** Install Terraform, write your first resource, and understand the plan → apply → destroy cycle.

**Time:** ~30 minutes  
**Prerequisites:** AWS CLI configured with a working profile. An IAM user with EC2 and VPC permissions.

---

## Part 1 — Install Terraform

```bash
# Linux (Ubuntu/Debian)
sudo apt-get update && sudo apt-get install -y gnupg software-properties-common
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt-get install terraform

# macOS
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# Verify
terraform version
```

---

## Part 2 — Your First Configuration

Create a new directory and write your first `.tf` file:

```bash
mkdir ~/terraform-lab-01 && cd ~/terraform-lab-01
```

Create `main.tf`:

```hcl
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

resource "aws_s3_bucket" "lab" {
  bucket = "terraform-lab-YOUR_NAME-${random_id.suffix.hex}"

  tags = {
    Name      = "terraform-lab"
    ManagedBy = "terraform"
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}
```

Add the `random` provider to your required_providers block:
```hcl
random = {
  source  = "hashicorp/random"
  version = "~> 3.0"
}
```

---

## Part 3 — The Workflow

```bash
# 1. Initialise — downloads providers
terraform init

# 2. Plan — shows what will be created (read this carefully)
terraform plan

# 3. Apply — creates the resources
terraform apply
# Type 'yes' when prompted

# 4. Verify it was created
aws s3 ls | grep terraform-lab

# 5. See the state file that was created
cat terraform.tfstate

# 6. Destroy — tears it all down
terraform destroy
# Type 'yes' when prompted

# 7. Verify it is gone
aws s3 ls | grep terraform-lab
```

---

## Part 4 — Observe State Changes

1. Apply the config to create the bucket.
2. Manually add a tag to the bucket in the AWS console.
3. Run `terraform plan` — what does it show? Why?
4. Run `terraform apply` — what happens to the tag you added?

This demonstrates why **all changes should go through Terraform** once a resource is managed by it.

---

## Part 5 — Explore Plan Output

Modify your bucket configuration to add versioning:

```hcl
resource "aws_s3_bucket_versioning" "lab" {
  bucket = aws_s3_bucket.lab.id

  versioning_configuration {
    status = "Enabled"
  }
}
```

Run `terraform plan`. Identify:
- Which resources will be created (`+`)
- Which will be modified (`~`)
- Which will be destroyed (`-`)
- Which will be replaced (`-/+`)

Apply and verify in the console.

---

## Cleanup

```bash
terraform destroy
```

Always destroy lab resources when done. S3 buckets are cheap but it is good discipline.

---

## What You Should Now Understand

- The `init → plan → apply → destroy` cycle
- What a state file is and why it exists
- Why manual changes conflict with Terraform
- How to read plan output
- The difference between creating and modifying a resource

---

## Next Lab

[Lab 02 — Variables and Outputs →](./lab-02-variables.md)
