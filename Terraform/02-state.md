# State & Remote Backends

Terraform state is how Terraform knows what it has already created. It maps your HCL configuration to real cloud resources. Mismanaging state is the most common cause of serious Terraform problems.

---

## What State Is

When you run `terraform apply`, Terraform creates a `terraform.tfstate` file. This JSON file contains the mapping between your HCL and the real infrastructure:

```json
{
  "resources": [
    {
      "type": "aws_instance",
      "name": "web",
      "instances": [{
        "attributes": {
          "id": "i-1234567890abcdef0",
          "instance_type": "t3.micro",
          "public_ip": "54.123.45.67",
          ...
        }
      }]
    }
  ]
}
```

Terraform uses state to:
- Know what exists so it can calculate diffs for the next plan
- Store attribute values that are only known after creation (instance IDs, IPs, etc.)
- Map your local resource names to real cloud resource IDs

---

## The Problem With Local State

By default, state is stored in `terraform.tfstate` in your working directory. This works fine for solo local experiments. It is unusable for teams because:

- Two people running `apply` simultaneously will corrupt the state file
- State gets lost if your laptop dies
- Teammates cannot see what infrastructure exists
- You cannot run Terraform in CI/CD

**Never commit `terraform.tfstate` to git.** It contains sensitive values (passwords, private keys). Add it to `.gitignore` immediately.

---

## Remote Backend: S3 with Native Locking

As of Terraform 1.10 and AWS provider 5.x, S3 supports **native state locking** using S3's built-in conditional writes. No DynamoDB table needed anymore — one less resource to manage, one less thing to break.

```hcl
# versions.tf
terraform {
  required_version = ">= 1.10.0"

  backend "s3" {
    bucket = "my-terraform-state-prod"
    key    = "infra/vpc/terraform.tfstate"
    region = "ap-south-1"

    encrypt = true

    # Native S3 locking — no DynamoDB required
    use_lockfile = true
  }
}
```

How it works: Terraform writes a `.tflock` file alongside the state file using S3's conditional write API (`If-None-Match`). If two applies run simultaneously, the second one fails to write the lock file and aborts. Clean, built-in, free.

**Set up the backend bucket** (bootstrapping — create this once per account via CLI):

```bash
# Create state bucket
aws s3api create-bucket \
  --bucket my-terraform-state-prod \
  --region ap-south-1 \
  --create-bucket-configuration LocationConstraint=ap-south-1

# Enable versioning (critical — lets you recover from bad state)
aws s3api put-bucket-versioning \
  --bucket my-terraform-state-prod \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket my-terraform-state-prod \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }'

# Block all public access
aws s3api put-public-access-block \
  --bucket my-terraform-state-prod \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

That is it — no DynamoDB. After creating the bucket, run `terraform init` and Terraform will migrate your local state to S3 automatically.

> **Note on older setups:** If you are working on a codebase that still uses `dynamodb_table`, it still works fine — DynamoDB locking is not deprecated. Native S3 locking is just the simpler default for new projects.

---

## State Key Strategy

The `key` in your backend config is the path within the S3 bucket. Structure it to avoid collisions:

```
# Flat project
key = "myapp/terraform.tfstate"

# Multi-environment
key = "myapp/prod/terraform.tfstate"
key = "myapp/staging/terraform.tfstate"

# Multi-component (split state by concern)
key = "myapp/prod/vpc/terraform.tfstate"
key = "myapp/prod/eks/terraform.tfstate"
key = "myapp/prod/rds/terraform.tfstate"
```

Splitting state by component is a good idea for large systems — it limits blast radius if something goes wrong and speeds up plan/apply since Terraform only has to evaluate one component at a time.

---

## Essential State Commands

```bash
# See everything Terraform is tracking
terraform state list

# Inspect a specific resource in state
terraform state show aws_instance.web

# Remove a resource from state WITHOUT destroying it
# (use when you want Terraform to "forget" something it manages)
terraform state rm aws_instance.web

# Import an existing resource into state
# (use when something was created manually and you want Terraform to manage it)
terraform import aws_instance.web i-1234567890abcdef0

# Move a resource in state (useful after renaming or refactoring)
terraform state mv aws_instance.web aws_instance.app_server

# Pull current remote state and print it
terraform state pull

# Push a local state file to remote (use with extreme caution)
terraform state push terraform.tfstate

# Manually unlock state if a previous run left a lock
terraform force-unlock LOCK_ID
```

---

## Refreshing State

Terraform's state can get out of sync with reality if someone makes changes outside Terraform (manually in the console, via CLI, etc.).

```bash
# Refresh state to match actual infrastructure
terraform refresh

# Better: plan with refresh
terraform plan -refresh=true   # this is the default

# Skip refresh (faster, but state may be stale)
terraform plan -refresh=false
```

---

## Handling Sensitive Values in State

State files contain sensitive values in plaintext (database passwords, private keys, etc.) even though the file itself may be encrypted at rest. This means:

1. Encrypt your S3 bucket (done above)
2. Restrict access to the state bucket via IAM
3. Enable S3 access logging
4. Use Secrets Manager or SSM Parameter Store for secrets where possible, and only reference the secret ARN in state (not the secret value)

```hcl
# Better: store only the ARN, not the value
resource "aws_db_instance" "main" {
  manage_master_user_password = true   # AWS manages rotation via Secrets Manager
  ...
}
```

---

## The Bootstrapping Script

Put this in `scripts/bootstrap-state.sh` and run it once per AWS account before anything else:

```bash
#!/bin/bash
set -euo pipefail

REGION="${1:-ap-south-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="terraform-state-${ACCOUNT_ID}-${REGION}"

echo "Creating state bucket: $BUCKET"
aws s3api create-bucket \
  --bucket "$BUCKET" \
  --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION" 2>/dev/null || true

aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

echo "Done. State bucket: s3://$BUCKET"
echo "Use this in your backend config:"
echo ""
echo '  backend "s3" {'
echo "    bucket       = \"$BUCKET\""
echo '    key          = "your-project/terraform.tfstate"'
echo "    region       = \"$REGION\""
echo '    encrypt      = true'
echo '    use_lockfile = true'
echo '  }'
```

---

## Key Insight for DevOps

Native S3 locking (`use_lockfile = true`) works by writing a `.tflock` file using a conditional S3 put — if the file already exists, the write is rejected, which is how concurrent applies get blocked. It requires Terraform >= 1.10 and AWS provider >= 5.x.

If Terraform crashes mid-apply, it may leave a stale `.tflock` file in S3. Check with `terraform state list` — if it hangs, the lock is stuck. Run `terraform force-unlock LOCK_ID` to clear it. Never do this while another apply is genuinely in progress.