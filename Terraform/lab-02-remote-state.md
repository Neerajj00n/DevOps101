# Lab 03 — Remote State with S3 Native Locking

**Goal:** Move your Terraform state from local to a remote S3 backend with native S3 locking (no DynamoDB needed — requires Terraform >= 1.10).

**Time:** ~30 minutes  
**Prerequisites:** Lab 01 and 02 completed. S3 permissions in your IAM user.

---

## Part 1 — Bootstrap the Backend Bucket

This needs to exist before Terraform can use it as a backend. Create it with the AWS CLI (not Terraform — this is the bootstrapping chicken-and-egg problem):

```bash
REGION="ap-south-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="terraform-state-${ACCOUNT_ID}-${REGION}"

echo "Creating state bucket: $BUCKET"

# Create bucket
aws s3api create-bucket \
  --bucket "$BUCKET" \
  --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION"

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# Block public access
aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

echo "Backend ready. Bucket: $BUCKET"
```

---

## Part 2 — Add the Backend to Your Config

Take your config from Lab 02 and add a backend block to the `terraform` block:

```hcl
terraform {
  required_version = ">= 1.6.0"

  backend "s3" {
    bucket       = "terraform-state-YOUR_ACCOUNT_ID-ap-south-1"
    key          = "labs/lab-03/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true   # native S3 locking — no DynamoDB needed
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

---

## Part 3 — Migrate State

```bash
# Re-init with the new backend
# Terraform will detect the backend change and ask to migrate
terraform init

# It will prompt:
# "Do you want to copy existing state to the new backend?"
# Type: yes

# Verify state is now remote
terraform state list

# The local terraform.tfstate file is now just a backup — you can delete it
# The real state is in S3
```

---

## Part 4 — Verify the Lock

Open two terminals. In terminal 1:

```bash
# Start a long-running apply (add sleep to user_data or use a slow resource)
terraform apply
```

In terminal 2, while terminal 1 is running:

```bash
terraform plan
# You should see:
# Error: Error acquiring the state lock
```

Check the lock file directly in S3 — native locking writes a `.tflock` file alongside the state:

```bash
aws s3 ls s3://terraform-state-YOUR_ACCOUNT_ID-ap-south-1/labs/lab-03/
# You will see both:
#   terraform.tfstate
#   terraform.tfstate.tflock   ← this is the active lock
```

Let terminal 1 finish. The `.tflock` file disappears and terminal 2 can proceed.

---

## Part 5 — Explore the State in S3

```bash
# List state files in your bucket
aws s3 ls s3://terraform-state-YOUR_ACCOUNT_ID-ap-south-1/ --recursive

# Download and inspect the state file
aws s3 cp s3://terraform-state-YOUR_ACCOUNT_ID-ap-south-1/labs/lab-03/terraform.tfstate /tmp/state.json
cat /tmp/state.json | jq .

# Look at state file versions (versioning is on)
aws s3api list-object-versions \
  --bucket terraform-state-YOUR_ACCOUNT_ID-ap-south-1 \
  --prefix labs/lab-03/terraform.tfstate
```

Notice: the state file contains plaintext values including resource IDs. This is why encryption and restricted access matter.

---

## Cleanup

```bash
terraform destroy
```

Keep the state bucket and DynamoDB table — you will reuse them in future labs.

---

## What You Should Now Understand

- Why local state is not suitable for teams or CI/CD
- How to bootstrap a remote backend
- How state migration works
- How DynamoDB locking prevents concurrent applies
- Why state file security matters

---

