# Lab 08 — Amazon S3 Block Public Access Troubleshooting

## Overview

This hands-on lab demonstrates how Amazon S3 Block Public Access can prevent a deployment from applying a public bucket policy.

The scenario simulates a DevOps deployment pipeline attempting to configure public-read access on an S3 bucket. The request fails because `BlockPublicPolicy` is enabled.

Instead of disabling the security protection, we investigate the failure and replace the proposed public policy with a more restrictive, account-scoped policy.

**Troubleshooting workflow:**

Establish Baseline → Reproduce Failure → Collect Evidence → Identify Root Cause → Secure Remediation → Verify → Cleanup

## Lab Information

| Item | Details |
|---|---|
| AWS Service | Amazon S3 |
| Incident ID | INC-S3-008 |
| Difficulty | Intermediate |
| Failed API | `PutBucketPolicy` |
| Error | `AccessDenied` |
| Environment | Ubuntu Linux (WSL2) |
| Tools | AWS CLI v2, Bash, curl |
| Root Cause | Public policy rejected by `BlockPublicPolicy` |
| Remediation | Replace public policy with restricted policy |
| Security Principle | Preserve Block Public Access |

---

## 1. Production Incident Scenario

### Incident Description

The DevOps team reports that an infrastructure deployment failed while configuring an Amazon S3 bucket.

The deployment attempts to attach a public-read bucket policy, but AWS rejects the operation.

### Reported Error

```text
An error occurred (AccessDenied) when calling
the PutBucketPolicy operation: Access Denied
```

### Expected Behavior

The deployment should configure the required application access without exposing private resources.

### Actual Behavior

The public bucket policy cannot be attached.

### Potential Business Impact

- Infrastructure deployments may fail.
- Application releases may be delayed.
- Teams may be unable to deploy intended storage-access configurations.
- Security controls may be at risk if engineers attempt unsafe workarounds.

A production engineer must determine whether the failure reflects incorrect permissions or a security control working as intended.

---

## 2. Architecture

### Failed Deployment

```text
DevOps Pipeline / AWS CLI
           |
           | PutBucketPolicy
           v
       Amazon S3
           |
           v
   Public Bucket Policy
   Principal: "*"
           |
           v
  S3 Block Public Access
  BlockPublicPolicy = true
           |
           X
      AccessDenied
```

### Secure Remediation

```text
DevOps Pipeline / AWS CLI
           |
           v
  Restricted Bucket Policy
           |
           v
    AWS Account Principal
           |
           v
       Amazon S3
           |
           v
    Authorized Access

Block Public Access remains enabled
```

---

## 3. Understand S3 Block Public Access

Amazon S3 provides four Block Public Access settings.

| Setting | Purpose |
|---|---|
| `BlockPublicAcls` | Rejects requests that set public ACLs |
| `IgnorePublicAcls` | Ignores public permissions granted by ACLs |
| `BlockPublicPolicy` | Rejects new bucket policies that grant public access |
| `RestrictPublicBuckets` | Restricts public and certain cross-account access when a bucket has a public policy |

AWS applies the most restrictive combination of applicable public-access settings.

### Important Distinction

`BlockPublicPolicy` does not simply deny every `GetObject` request.

It prevents new public bucket policies from being successfully configured.

This lab deliberately attempts that prohibited configuration.

---

## 4. Prerequisites

- AWS account with access to a dedicated lab bucket
- AWS CLI v2
- Ubuntu Linux / WSL2
- Bash
- curl
- Permissions to manage S3 bucket policies
- Permissions to inspect Block Public Access settings

Use only a disposable test bucket.

Do not change account-wide or organization-wide security settings.

### Verify AWS CLI

```bash
aws --version
```

### Verify AWS Identity

```bash
aws sts get-caller-identity
```

### Configure Environment Variables

```bash
export AWS_REGION="us-east-1"

export ACCOUNT_ID=$(aws sts get-caller-identity \
  --query Account --output text)

export BUCKET="cloud-lab08-${ACCOUNT_ID}"
```

Verify:

```bash
echo "Region: $AWS_REGION"
echo "Bucket: $BUCKET"
```

---

## 5. Create the Working Environment

### Step 1 — Create the S3 Bucket

First check whether the name already exists:

```bash
aws s3api head-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

If the name is available and is not used by another resource:

```bash
aws s3api create-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

### Step 2 — Verify the Bucket

```bash
aws s3api head-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

A successful request normally produces no output.

### Step 3 — Enable Block Public Access

```bash
aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
  --region "$AWS_REGION"
```

### Step 4 — Verify the Settings

```bash
aws s3api get-public-access-block \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

Expected configuration:

```json
{
  "PublicAccessBlockConfiguration": {
    "BlockPublicAcls": true,
    "IgnorePublicAcls": true,
    "BlockPublicPolicy": true,
    "RestrictPublicBuckets": true
  }
}
```

### Step 5 — Inspect Account-Level Settings

```bash
aws s3control get-public-access-block \
  --account-id "$ACCOUNT_ID" \
  --region "$AWS_REGION"
```

This is read-only. Do not modify account-level protections.

---

## 6. Establish a Working Baseline

### Step 1 — Create a Test File

```bash
echo "S3 Lab 08 - Security Configuration Test" > test.txt
```

### Step 2 — Upload the File

```bash
aws s3 cp test.txt \
  "s3://$BUCKET/test.txt" \
  --region "$AWS_REGION"
```

### Step 3 — Verify the Object

```bash
aws s3api head-object \
  --bucket "$BUCKET" \
  --key "test.txt" \
  --region "$AWS_REGION"
```

A successful response confirms that authorized object access works before introducing the deployment failure.

---

## 7. Introduce the Failure

### Step 1 — Inspect Existing Bucket Policy

```bash
aws s3api get-bucket-policy \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

A newly created bucket may return:

```text
NoSuchBucketPolicy
```

Only proceed if no existing policy needs to be preserved.

### Step 2 — Create a Public Bucket Policy

Create `public-policy.json`:

```bash
cat > public-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowPublicReadLab08",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::$BUCKET/*"
    }
  ]
}
EOF
```

### Step 3 — Inspect the Policy

```bash
cat public-policy.json
```

The key fields are:

```json
{
  "Effect": "Allow",
  "Principal": "*",
  "Action": "s3:GetObject"
}
```

This statement attempts to grant anonymous read access to all objects in the bucket.

### Step 4 — Apply the Public Policy

```bash
aws s3api put-bucket-policy \
  --bucket "$BUCKET" \
  --policy file://public-policy.json \
  --region "$AWS_REGION"
```

### Expected Error

```text
An error occurred (AccessDenied) when calling
the PutBucketPolicy operation: Access Denied
```

The request is rejected because the proposed bucket policy grants public access while `BlockPublicPolicy` is enabled.

Other permission restrictions can also cause `AccessDenied`, so the surrounding configuration must be checked before assigning the root cause.

---

## 8. Troubleshooting Investigation

### Check 1 — Identify the AWS Principal

```bash
aws sts get-caller-identity
```

Verify the correct AWS identity is used.

### Check 2 — Inspect Bucket-Level Protection

```bash
aws s3api get-public-access-block \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

Look for:

```text
BlockPublicPolicy: true
```

### Check 3 — Review the Proposed Policy

```bash
cat public-policy.json
```

Identify the public principal and unrestricted object-read resource:

```text
Principal: *
Action: s3:GetObject
Resource: bucket/*
```

### Check 4 — Check the Current Bucket Policy

```bash
aws s3api get-bucket-policy \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

Expected for this lab:

```text
NoSuchBucketPolicy
```

This demonstrates that the rejected public policy was not attached.

### Investigation Summary

| Investigation | Finding |
|---|---|
| AWS identity | Intended lab principal |
| Bucket exists | Yes |
| Object upload | Successful |
| BlockPublicPolicy | Enabled |
| Proposed policy | Public read |
| PutBucketPolicy | Rejected |
| Root cause | Public policy conflicts with security control |

---

## 9. Root Cause Analysis

### Root Cause

The deployment attempts to attach an S3 bucket policy that grants public access.

The bucket has `BlockPublicPolicy=true`, so Amazon S3 rejects the policy.

### Technical Explanation

The proposed policy contains:

```json
"Principal": "*"
```

combined with unrestricted object-read permission.

S3 considers this policy public, and the enabled Block Public Access setting prevents it from being attached.

### Root Cause Flow

```text
PutBucketPolicy Request
          |
          v
Public Read Policy
          |
          v
BlockPublicPolicy = true
          |
          v
Public Access Configuration Rejected
          |
          v
AccessDenied
```

### Five Whys

1. **Why did deployment fail?** `PutBucketPolicy` returned AccessDenied.
2. **Why was the policy rejected?** It attempted to grant public read access.
3. **Why is public read blocked?** `BlockPublicPolicy` is enabled.
4. **Why did the deployment attempt public access?** The lab deliberately supplied a public policy.
5. **How can this be prevented?** Validate policies before deployment and use private access designs.

---

## 10. Secure Remediation

The correct approach is not to disable Block Public Access.

Instead, we will use a non-public policy.

### Step 1 — Create Restricted Policy

Create `private-policy.json`:

```bash
cat > private-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowLabAccountRead",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::$ACCOUNT_ID:root"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::$BUCKET/test.txt"
    }
  ]
}
EOF
```

The account-root ARN here identifies the AWS account principal. It does not mean the application should authenticate using root credentials.

For a real application, a narrowly scoped IAM role principal is usually more appropriate.

### Step 2 — Apply the Policy

```bash
aws s3api put-bucket-policy \
  --bucket "$BUCKET" \
  --policy file://private-policy.json \
  --region "$AWS_REGION"
```

This should succeed when the caller has the required permissions and no other authorization controls interfere.

### Step 3 — Verify the Policy

```bash
aws s3api get-bucket-policy \
  --bucket "$BUCKET" \
  --region "$AWS_REGION" \
  --query Policy \
  --output text | python3 -m json.tool
```

Confirm the policy does not grant anonymous public access.

---

## 11. Verification

### Verify Block Public Access

```bash
aws s3api get-public-access-block \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

All four settings should remain `true`.

### Verify Authorized Download

```bash
aws s3api get-object \
  --bucket "$BUCKET" \
  --key "test.txt" \
  verified-test.txt \
  --region "$AWS_REGION"
```

Compare:

```bash
diff test.txt verified-test.txt
```

No output indicates that the files match.

This verifies that the current AWS identity can download the object. If it already had permission through an identity policy, this test alone does not prove the new bucket policy supplied that permission.

### Verify Anonymous Access Is Blocked

```bash
curl -sS -o /dev/null \
  -w "HTTP Status: %{http_code}\n" \
  "https://${BUCKET}.s3.${AWS_REGION}.amazonaws.com/test.txt"
```

Expected:

```text
HTTP Status: 403
```

This confirms that the object is not anonymously downloadable through the tested endpoint.

### Final Verification Summary

| Test | Expected Result |
|---|---|
| Public bucket policy | Rejected |
| Private bucket policy | Accepted |
| Block Public Access | Remains enabled |
| Authorized download | Successful |
| Anonymous download | Denied |
| Test file integrity | Verified |

---

## 12. Production Engineering Considerations

### Incident Triage

Before changing permissions, identify:

- Which deployment failed?
- Which AWS principal submitted the request?
- Was the failure caused by a security protection?
- Did the proposed policy grant public access?
- Were account-level or organization-level controls involved?
- Does the application actually require public S3 access?

### Evidence Collection

Useful tools include:

- AWS CLI
- S3 bucket policy inspection
- Block Public Access configuration
- CloudTrail management events
- IAM Access Analyzer
- CI/CD deployment logs
- Terraform plan output

### Safe Remediation

In production:

1. Inspect the failed API operation.
2. Review the proposed policy.
3. Identify the security control responsible.
4. Confirm the application's actual access requirements.
5. Choose a private design where possible.
6. Make changes through an approved deployment process.
7. Verify authorized access.
8. Confirm anonymous access remains restricted.
9. Document the incident.

### Recommended Production Architecture

For static websites or content distribution:

```text
Internet Users
      |
      | HTTPS
      v
Amazon CloudFront
      |
      | Origin Access Control
      v
Private S3 Bucket
      |
      v
Application Objects
```

CloudFront Origin Access Control allows users to access approved content without requiring the S3 bucket itself to be public.

---

## 13. Prevention Strategies

- Keep S3 Block Public Access enabled by default.
- Use private S3 buckets.
- Prefer CloudFront OAC for content delivery.
- Use IAM Access Analyzer to validate policies.
- Review Terraform and CloudFormation changes.
- Add security checks to CI/CD pipelines.
- Follow least-privilege principles.
- Avoid anonymous public access unless explicitly required and approved.
- Monitor unauthorized access attempts and unexpected configuration changes.

---

## 14. Related S3 Access Problems

| Problem | Investigation |
|---|---|
| `PutBucketPolicy` AccessDenied | Permissions and BlockPublicPolicy |
| Anonymous GetObject 403 | Public access controls and object policy |
| Public ACL rejected | BlockPublicAcls |
| Public ACL ignored | IgnorePublicAcls |
| Cross-account access unexpectedly blocked | RestrictPublicBuckets and other controls |
| GetObject denied with KMS | KMS permissions |
| Public policy exists but public access fails | Effective Block Public Access settings |

---

## 15. Interview Questions and Answers

### Q1. What is S3 Block Public Access?

It is a set of security controls designed to prevent unintended public access to S3 buckets and objects.

### Q2. What are the four S3 Block Public Access settings?

`BlockPublicAcls`, `IgnorePublicAcls`, `BlockPublicPolicy`, and `RestrictPublicBuckets`.

### Q3. What does BlockPublicPolicy do?

It prevents new bucket policies that grant public access from being successfully configured.

### Q4. Why did PutBucketPolicy return AccessDenied in this lab?

The proposed policy granted public object-read access while BlockPublicPolicy was enabled.

### Q5. Should you disable Block Public Access to fix the deployment?

Not automatically.

First determine whether public access is required. Prefer a restricted policy or private architecture when possible.

### Q6. What is the difference between BlockPublicPolicy and RestrictPublicBuckets?

BlockPublicPolicy rejects attempts to apply new public bucket policies.

RestrictPublicBuckets limits access when an existing bucket policy is considered public, including restrictions on certain cross-account permissions.

### Q7. Can an authorized application download objects while Block Public Access is enabled?

Yes. Block Public Access is designed to prevent public access, not all authorized private access.

### Q8. Can Block Public Access override a public bucket policy?

Yes. Applicable Block Public Access protections can prevent or restrict access that a public policy would otherwise permit.

### Q9. How would you troubleshoot a failed S3 policy deployment?

I would verify the deployment identity, inspect the proposed policy, review bucket and account Block Public Access settings, identify the conflicting permission, and implement a secure alternative.

### Q10. How would you explain this incident in an interview?

> A deployment failed while applying an S3 bucket policy. I reviewed the PutBucketPolicy error and inspected the bucket's Block Public Access configuration. I identified that BlockPublicPolicy was enabled and the proposed policy granted anonymous read access. Instead of weakening the security control, I replaced the public policy with restricted access and verified that authorized downloads worked while anonymous requests remained blocked.

---

## 16. Cleanup

### Step 1 — Confirm Bucket Name

```bash
echo "$BUCKET"
```

### Step 2 — Remove Lab Bucket Policy

```bash
aws s3api delete-bucket-policy \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

Only do this because the entire policy was created for this isolated lab.

### Step 3 — Inspect Objects

```bash
aws s3 ls "s3://$BUCKET/" \
  --recursive \
  --region "$AWS_REGION"
```

### Step 4 — Delete Test Object

```bash
aws s3 rm "s3://$BUCKET/test.txt" \
  --region "$AWS_REGION"
```

### Step 5 — Delete Bucket

```bash
aws s3api delete-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

These commands assume the bucket contains only lab data and versioning has not been enabled.

### Step 6 — Remove Temporary Local File

```bash
rm -f verified-test.txt
```

Keep the policy examples and sample test file for your GitHub documentation.

---

## 17. Repository Structure

```text
08-s3-block-public-access/
│
├── README.md
├── test.txt
├── public-policy.json
└── private-policy.json
```

The JSON policy files are educational examples.

Before publishing, replace actual account IDs and bucket names with placeholders if you want the policies to be reusable.

Never commit AWS credentials or tokens.

---

## 18. Lessons Learned

This lab demonstrates that an AWS deployment can fail because security protections are working as intended.

The public-read bucket policy was rejected because S3 Block Public Access prevented the configuration.

Instead of disabling the protection, the troubleshooting process identified the root cause and applied a more restricted policy.

The important lesson is that production troubleshooting is not always about making a failed operation succeed exactly as originally requested.

Sometimes the correct engineering solution is to change the requested configuration while preserving security.

---

## 19. Skills Demonstrated

- Amazon S3 troubleshooting
- Linux Bash
- AWS CLI v2
- S3 bucket policy analysis
- Block Public Access configuration
- PutBucketPolicy troubleshooting
- Public vs private access
- Secure remediation
- Root cause analysis
- Least-privilege access design
- Production incident documentation

## Final Outcome

| Item | Expected Result |
|---|---|
| Incident | INC-S3-008 |
| Failed API | PutBucketPolicy |
| Root Cause | BlockPublicPolicy rejected public-read policy |
| Remediation | Applied restricted bucket policy |
| Security Verification | Block Public Access remained enabled |
| Functional Verification | Authorized download succeeded |
| Anonymous Access | Denied |
| Lab Status | Resolved after successful verification |

**Key Takeaway:** When AWS rejects a public-access configuration, investigate the security controls and preserve them wherever possible. A successful cloud engineering fix should restore required functionality without introducing unnecessary exposure.
