# DevSecOps Tools Setup Guide

This guide walks you through setting up all the DevSecOps tools for this repository.

## Table of Contents

1. [GitHub Secrets Configuration](#github-secrets-configuration)
2. [SonarQube Setup](#sonarqube-setup)
3. [GitGuardian Setup](#gitguardian-setup)
4. [Checkov Setup](#checkov-setup)
5. [AWS Setup](#aws-setup)
6. [Testing the Setup](#testing-the-setup)

## GitHub Secrets Configuration

To enable all workflows, you need to configure the following secrets in your GitHub repository:

### Navigate to Secrets Settings

1. Go to your repository on GitHub
2. Click on `Settings` → `Secrets and variables` → `Actions`
3. Click `New repository secret` for each secret below

### Required Secrets

#### For SonarQube Integration

**SONAR_TOKEN**
- Get this from your SonarQube/SonarCloud account
- SonarCloud: Account → Security → Generate Tokens
- SonarQube: Administration → Security → Users → Tokens

**SONAR_HOST_URL**
- For SonarCloud: `https://sonarcloud.io`
- For self-hosted SonarQube: Your SonarQube server URL (e.g., `https://sonar.yourcompany.com`)

#### For GitGuardian Integration

**GITGUARDIAN_API_KEY**
- Sign up at [GitGuardian](https://www.gitguardian.com/)
- Go to API → Personal Access Tokens
- Generate a new token with repository scanning permissions

#### For AWS Deployment (Optional)

**AWS_ACCESS_KEY_ID**
- Your AWS IAM access key ID

**AWS_SECRET_ACCESS_KEY**
- Your AWS IAM secret access key

> ⚠️ **Security Note**: Only add AWS credentials if you plan to actually deploy infrastructure. For testing tools only, these are not required.

## SonarQube Setup

### Using SonarCloud (Recommended for Public Repos)

1. Go to [SonarCloud](https://sonarcloud.io/)
2. Sign in with your GitHub account
3. Click the `+` icon → `Analyze new project`
4. Import your repository
5. Follow the setup wizard
6. Update `sonar-project.properties` with your organization key if different

### Using Self-Hosted SonarQube

1. Install SonarQube server (Docker recommended):
   ```bash
   docker run -d --name sonarqube -p 9000:9000 sonarqube:latest
   ```
2. Access SonarQube at `http://localhost:9000`
3. Create a new project manually
4. Generate an authentication token
5. Add token and URL to GitHub secrets

## GitGuardian Setup

1. Sign up at [GitGuardian](https://dashboard.gitguardian.com/auth/signup)
2. Choose the free tier for public repositories
3. Go to `API` → `Personal access tokens`
4. Create a new token:
   - Name: `GitHub Actions`
   - Scopes: `scan`
5. Copy the token and add it to GitHub secrets as `GITGUARDIAN_API_KEY`

### Testing GitGuardian Locally

```bash
# Install ggshield
pip install ggshield

# Configure API key
export GITGUARDIAN_API_KEY="your-api-key"

# Scan repository
ggshield secret scan repo .
```

## Checkov Setup

Checkov runs automatically in the GitHub Actions workflow. No cloud service or API key required!

### Testing Checkov Locally

```bash
# Install Checkov
pip install checkov

# Scan Terraform code
checkov -d terraform/

# Scan with config file
checkov --config-file .checkov.yaml
```

### Common Checkov Checks

The current Terraform configuration should pass most checks because it implements:
- S3 bucket encryption
- S3 versioning
- S3 public access blocking
- Security group restrictions

## AWS Setup

### Prerequisites

1. Install AWS CLI:
   ```bash
   # macOS
   brew install awscli
   
   # Linux
   pip install awscli
   ```

2. Configure AWS credentials:
   ```bash
   aws configure
   ```

### IAM Permissions Required

For the Terraform code in this repository, you'll need permissions for:
- VPC management
- S3 bucket management
- Security Group management

Example IAM policy (least privilege):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*Vpc*",
        "ec2:*SecurityGroup*",
        "s3:*"
      ],
      "Resource": "*"
    }
  ]
}
```

> ⚠️ **Note**: Adjust permissions based on your security requirements.

## Testing the Setup

### 1. Test Terraform Locally

```bash
cd terraform
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan
```

### 2. Test Security Scanning Locally

```bash
# Checkov
checkov -d terraform/

# GitGuardian (if configured)
ggshield secret scan repo .
```

### 3. Trigger GitHub Actions

**Option 1: Push to branch**
```bash
git checkout -b test-workflows
git commit --allow-empty -m "Test workflows"
git push origin test-workflows
```

**Option 2: Manual workflow dispatch**
1. Go to `Actions` tab in GitHub
2. Select a workflow
3. Click `Run workflow`
4. Choose branch and click `Run workflow`

### 4. Verify Workflow Results

1. Go to the `Actions` tab in your repository
2. Click on the latest workflow run
3. Check each job:
   - ✅ Green checkmark = passed
   - ❌ Red X = failed
4. Click on a job to see detailed logs

### 5. Check Security Findings

1. Go to the `Security` tab
2. Click on `Code scanning alerts`
3. You should see Checkov findings (if any)

## Troubleshooting

### Workflow Fails with "Secret not found"

- Verify secrets are added in repository settings
- Check secret names match exactly (case-sensitive)
- Ensure you have write permissions to the repository

### SonarQube Analysis Fails

- Verify `SONAR_TOKEN` is valid and not expired
- Check `SONAR_HOST_URL` is correct
- Ensure project exists in SonarQube/SonarCloud

### GitGuardian Scan Fails

- Verify API key is valid
- Check you haven't exceeded rate limits
- Ensure repository is not too large

### Checkov Finds Many Issues

This is normal! Checkov is comprehensive. You can:
- Fix the issues (recommended)
- Skip specific checks in `.checkov.yaml`
- Set `soft-fail: true` in config to not fail builds

### Terraform Validation Fails

- Check syntax with `terraform validate`
- Verify provider versions are compatible
- Ensure all required variables are defined

## Next Steps

After setup:

1. ✅ Push code and verify workflows run
2. ✅ Review security findings
3. ✅ Fix any critical issues
4. ✅ Configure branch protection rules
5. ✅ Set up required checks for PRs
6. ✅ Document any custom configurations

## Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [SonarQube Documentation](https://docs.sonarqube.org/)
- [GitGuardian Documentation](https://docs.gitguardian.com/)
- [Checkov Documentation](https://www.checkov.io/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## Support

For issues with:
- **This repository**: Open an issue
- **GitHub Actions**: Check GitHub Status or GitHub Community
- **SonarQube**: SonarQube Community Forum
- **GitGuardian**: GitGuardian Support
- **Checkov**: Checkov GitHub Issues
