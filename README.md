# itsatest

A repository for testing DevSecOps tools and AWS Infrastructure as Code (IaC) with Terraform.

## Overview

This repository is set up to test and demonstrate various DevSecOps tools and practices:

- **Terraform**: Infrastructure as Code for AWS
- **GitHub Actions**: CI/CD automation
- **Checkov**: Infrastructure security scanning
- **SonarQube**: Code quality and security analysis
- **GitGuardian**: Secret detection and prevention

## Repository Structure

```
.
├── .github/
│   └── workflows/          # GitHub Actions workflows
│       ├── terraform.yml   # Terraform validation and Checkov scanning
│       ├── sonarqube.yml   # SonarQube code analysis
│       └── gitguardian.yml # GitGuardian secret scanning
├── terraform/              # Terraform AWS infrastructure code
│   ├── provider.tf        # Provider configuration
│   ├── variables.tf       # Variable definitions
│   ├── main.tf           # Main infrastructure resources
│   ├── outputs.tf        # Output values
│   └── terraform.tfvars.example  # Example variables file
├── .checkov.yaml          # Checkov configuration
├── sonar-project.properties  # SonarQube configuration
└── .gitignore            # Git ignore rules
```

## Getting Started

### Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) configured with credentials
- GitHub repository with Actions enabled
- (Optional) SonarQube instance or SonarCloud account
- (Optional) GitGuardian API key

### Local Setup

1. **Clone the repository**
   ```bash
   git clone https://github.com/dominiclau2002/itsatest.git
   cd itsatest
   ```

2. **Configure Terraform variables**
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your desired values
   ```

3. **Initialize Terraform**
   ```bash
   terraform init
   ```

4. **Validate Terraform configuration**
   ```bash
   terraform validate
   terraform fmt -check -recursive
   ```

5. **Plan infrastructure changes**
   ```bash
   terraform plan
   ```

6. **Apply infrastructure (when ready)**
   ```bash
   terraform apply
   ```

## DevSecOps Tools Setup

### GitHub Actions

The repository includes three main workflows:

1. **Terraform CI/CD** (`.github/workflows/terraform.yml`)
   - Validates Terraform code formatting
   - Initializes and validates Terraform configuration
   - Runs Checkov security scans
   - Comments results on pull requests
   - Uploads security findings to GitHub Security tab

2. **SonarQube Analysis** (`.github/workflows/sonarqube.yml`)
   - Performs code quality and security analysis
   - Checks quality gates
   - Requires `SONAR_TOKEN` and `SONAR_HOST_URL` secrets

3. **GitGuardian Secret Scan** (`.github/workflows/gitguardian.yml`)
   - Scans for hardcoded secrets and credentials
   - Requires `GITGUARDIAN_API_KEY` secret

### Required GitHub Secrets

To enable all workflows, add these secrets to your GitHub repository:

1. **SonarQube Integration**:
   - `SONAR_TOKEN`: Your SonarQube/SonarCloud authentication token
   - `SONAR_HOST_URL`: Your SonarQube server URL (or https://sonarcloud.io)

2. **GitGuardian Integration**:
   - `GITGUARDIAN_API_KEY`: Your GitGuardian API key

3. **AWS Credentials** (if deploying infrastructure):
   - `AWS_ACCESS_KEY_ID`: AWS access key
   - `AWS_SECRET_ACCESS_KEY`: AWS secret key

### Checkov

Checkov is integrated into the Terraform workflow and scans infrastructure code for security issues.

Configuration is in `.checkov.yaml`. To run locally:

```bash
# Install Checkov
pip install checkov

# Run Checkov on Terraform code
checkov -d terraform/
```

### SonarQube

SonarQube configuration is in `sonar-project.properties`. To run locally:

```bash
# Install SonarScanner
# https://docs.sonarqube.org/latest/analysis/scan/sonarscanner/

# Run analysis
sonar-scanner
```

### GitGuardian

GitGuardian scans for secrets in your code. To run locally:

```bash
# Install ggshield
pip install ggshield

# Scan repository
ggshield secret scan repo .
```

## Infrastructure Components

The Terraform code includes example AWS resources with security best practices:

- **VPC**: Virtual Private Cloud with DNS support
- **S3 Bucket**: With versioning, encryption, and blocked public access
- **Security Group**: With restrictive ingress rules

All resources are tagged with environment and management information.

## Best Practices Implemented

1. **Security**:
   - S3 bucket encryption enabled
   - S3 public access blocked
   - Versioning enabled on S3
   - Security group with minimal permissions
   - Secrets excluded from version control

2. **Code Quality**:
   - Terraform formatting validation
   - Infrastructure security scanning with Checkov
   - Code analysis with SonarQube
   - Secret scanning with GitGuardian

3. **CI/CD**:
   - Automated validation on pull requests
   - Security findings in GitHub Security tab
   - PR comments with scan results
   - Manual workflow dispatch option

## Running Security Scans

### Terraform Security Scan
```bash
cd terraform
checkov -d .
```

### Secret Scanning
```bash
ggshield secret scan repo .
```

### Code Quality Analysis
```bash
sonar-scanner
```

## Contributing

When contributing to this repository:

1. Create a feature branch
2. Make your changes
3. Ensure all security scans pass
4. Create a pull request
5. Review automated scan results

## Cleanup

To destroy the infrastructure created by Terraform:

```bash
cd terraform
terraform destroy
```

## Resources

- [Terraform Documentation](https://www.terraform.io/docs)
- [Checkov Documentation](https://www.checkov.io/)
- [SonarQube Documentation](https://docs.sonarqube.org/)
- [GitGuardian Documentation](https://docs.gitguardian.com/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)

## License

This is a test repository for educational and testing purposes.
