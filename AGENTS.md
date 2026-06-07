# AGENTS.md - DevOps101

## Repository Overview
This is an educational repository for DevOps fundamentals with three main sections:
- `/Linux`: Guides and labs for essential Linux skills
- `/AWS`: AWS service tutorials and labs for core infrastructure
- `/Terraform`: Infrastructure as Code tutorials and labs

## Environment Requirements

### Python Scripts
The AI scripts that interface with Amazon Bedrock API are located in the parent directory (`../ai-scripts/`):
- `ai.py`: Tests connectivity to various Claude AI models
- `ai-avilable.py`: Lists available Anthropic models

To run these scripts:
- `ai-avilable.py` requires `AWS_BEARER_TOKEN_BEDROCK` environment variable
- Execute with: `python3 ../ai-scripts/ai.py` or `python3 ../ai-scripts/ai-avilable.py`

## Repository Structure
- `/Linux`: Contains markdown tutorials on Linux fundamentals (filesystem, permissions, processes, networking)
- `/AWS`: Contains AWS service tutorials and hands-on labs
  - `/AWS/notes`: Service-specific documentation
  - `/AWS/labs`: Practical step-by-step exercises
  - `/AWS/solutions`: Complete example implementations
- `/Terraform`: Contains Infrastructure as Code tutorials and labs
  - `/Terraform/notes`: Terraform concepts and best practices
  - `/Terraform/labs`: Hands-on Terraform exercises
  - `/Terraform/solutions`: Example Terraform projects

## Content Organization
Each topic is organized as:
1. Explanatory markdown files with concepts and commands
2. Practical labs with step-by-step instructions
3. Solutions where applicable

## Git Workflow
Standard git workflow applies with no special requirements or hooks.