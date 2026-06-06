# 02 — AWS Core Services

> Cloud infrastructure runs on AWS for a huge percentage of production systems. This module covers the services you will actually use — not a certification dump, but what matters day-to-day in DevOps.

---

## 🎯 What You'll Learn

- Navigate the AWS console and use the CLI like a pro
- Launch and connect to EC2 instances securely
- Design VPCs with public and private subnets
- Manage IAM users, roles, and policies (least privilege)
- Store and serve files with S3
- Set up RDS databases with proper security
- Configure Application Load Balancers (ALB)
- Manage DNS with Route53

---

## ✅ Prerequisites

[01 — Linux](../01-linux/) — You need to be comfortable on the command line. You will SSH into EC2 instances and run CLI commands throughout this module.

---

## 📚 Notes

| Topic | File |
|-------|------|
| AWS CLI & Console Basics | [notes/01-cli-basics.md](./notes/01-cli-basics.md) |
| EC2 — Elastic Compute Cloud | [notes/02-ec2.md](./notes/02-ec2.md) |
| VPC — Networking | [notes/03-vpc.md](./notes/03-vpc.md) |
| IAM — Identity & Access Management | [notes/04-iam.md](./notes/04-iam.md) |
| S3 — Object Storage | [notes/05-s3.md](./notes/05-s3.md) |
| RDS — Managed Databases | [notes/06-rds.md](./notes/06-rds.md) |
| ALB — Application Load Balancer | [notes/07-alb.md](./notes/07-alb.md) |

---

## 🧪 Labs

| Lab | Description |
|-----|-------------|
| [Lab 01](./labs/lab-01-cli-setup.md) | Set up AWS CLI, configure profiles, run first commands |
| [Lab 02](./labs/lab-02-ec2.md) | Launch an EC2 instance, SSH in, install a web server |
| [Lab 03](./labs/lab-03-vpc.md) | Build a VPC from scratch with public and private subnets |
| [Lab 04](./labs/lab-04-iam.md) | Create IAM users, roles, and a least-privilege policy |
| [Lab 05](./labs/lab-05-s3.md) | Create a bucket, upload files, host a static website |
| [Lab 06](./labs/lab-06-alb.md) | Put an ALB in front of two EC2 instances |

---

## 🔧 Module Project

**Deploy a simple web app on AWS — manually, so you understand every piece.**

By the end you will have:
- A custom VPC with public/private subnets
- Two EC2 instances running a web app in private subnets
- An ALB in the public subnet routing traffic to both instances
- An S3 bucket storing static assets
- IAM roles granting EC2 instances only the permissions they need
- Security groups locked down to only necessary traffic

No Terraform yet — everything done via CLI. The goal is to understand what Terraform will later automate.

Solution in [solutions/project/](./solutions/project/)

---

## ➡️ Next Module

[03 — Terraform →](../03-terraform/)
