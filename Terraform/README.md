# 03 — Terraform

> Infrastructure as Code means your entire cloud setup lives in version-controlled files. No more clicking through consoles, no more "works on my account" problems. Terraform is the industry standard for this — learn it properly once and it pays off forever.

---

## 🎯 What You'll Learn

- Write HCL to provision real AWS resources
- Understand state files and why they matter
- Set up remote backends with S3 + DynamoDB locking
- Use variables, outputs, locals, and data sources correctly
- Build reusable modules
- Manage multiple environments (dev/staging/prod) without duplicating code
- Debug the most common Terraform errors

---

## ✅ Prerequisites

[02 — AWS](../02-aws/) — You need to understand the resources you are provisioning. Terraform is just automation — if you do not understand what a VPC is, you cannot write Terraform for one.

---

## 📚 Notes

| Topic | File |
|-------|------|
| HCL Basics & Core Concepts | [notes/01-hcl-basics.md](./notes/01-hcl-basics.md) |
| State & Remote Backends | [notes/02-state.md](./notes/02-state.md) |
| Variables, Outputs & Locals | [notes/03-variables.md](./notes/03-variables.md) |
| Data Sources & Providers | [notes/04-data-sources.md](./notes/04-data-sources.md) |
| Modules | [notes/05-modules.md](./notes/05-modules.md) |
| Workspaces & Multi-env Patterns | [notes/06-environments.md](./notes/06-environments.md) |
| Common Errors & Debugging | [notes/07-debugging.md](./notes/07-debugging.md) |

---

## 🧪 Labs

| Lab | Description |
|-----|-------------|
| [Lab 01](./labs/lab-01-first-resource.md) | Install Terraform, write your first resource, run plan/apply/destroy |
| [Lab 02](./labs/lab-02-variables.md) | Refactor hardcoded values into variables and outputs |
| [Lab 03](./labs/lab-03-remote-state.md) | Move local state to S3 backend with DynamoDB locking |
| [Lab 04](./labs/lab-04-modules.md) | Extract a VPC into a reusable module |
| [Lab 05](./labs/lab-05-vpc-ec2.md) | Provision a full VPC + EC2 setup using only Terraform |

---

## 🔧 Module Project

**Provision the same infrastructure you built manually in Module 02 — but entirely in Terraform.**

By the end you will have:
- Remote state in S3 with DynamoDB locking
- A reusable VPC module (public + private subnets, IGW, NAT)
- EC2 instances with IAM roles via instance profiles
- Security groups with least-privilege rules
- An ALB with target groups and health checks
- Everything parameterised for dev and prod environments

This is the baseline you will extend in every subsequent module.

Solution in [solutions/vpc-ec2-alb/](./solutions/vpc-ec2-alb/)

---

## ➡️ Next Module

[04 — Docker →](../04-docker/)
