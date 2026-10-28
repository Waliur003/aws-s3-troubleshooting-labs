# Lab 07 — Amazon S3 Bucket Policy Misconfiguration

## Overview

This hands-on lab demonstrates how to troubleshoot an Amazon S3 `AccessDenied` error caused by an incorrect resource ARN in a bucket policy.

In this scenario, a simulated backup application uses an IAM role to list objects inside an S3 bucket.

The bucket policy appears to allow `s3:ListBucket`, but the policy incorrectly references an **object ARN instead of a bucket ARN**.

As a result, the intended permission does not apply, and the application cannot list its backup files.

The objective is to reproduce the authorization failure, investigate the policy configuration, identify the root cause, correct the resource ARN, and verify successful access.

**Troubleshooting workflow:**

Establish Baseline → Reproduce Failure → Investigate → Identify Root Cause → Remediate → Verify → Cleanup

## Lab Information

| Item | Details |
|---|---|
| AWS Service | Amazon S3 |
| Incident ID | INC-S3-007 |
| Difficulty | Intermediate |
| Error | `AccessDenied` |
| Failed API | `ListObjectsV2` |
| Required Permission | `s3:ListBucket` |
| Environment | Ubuntu Linux (WSL2) |
| Tools | AWS CLI v2, Bash, AWS STS |
| Test Identity | `Lab07S3BackupRole` |
| Root Cause | Incorrect resource ARN |
| Remediation | Replace object ARN with bucket ARN |
| Security Principle | Least privilege and implicit deny |

---

## 1. Production Incident Scenario

### Incident Description

A backup application stores files inside an Amazon S3 bucket.

The application needs to list objects under the `backups/` prefix to locate backup files for processing.

The support team reports that the application cannot list the objects even though the bucket policy appears to grant the required permission.

### Reported Error

```text
An error occurred (AccessDenied)
when calling the ListObjectsV2 operation:
Access Denied
```

### Expected Behavior

The backup application should list objects under:

```text
s3://LAB_BUCKET/backups/
```

### Actual Behavior

The application role receives `AccessDenied` when attempting to list backup objects.

### Potential Business Impact

- Backup applications cannot discover stored backup objects.
- Automated processing workflows may fail.
- Recovery procedures may be delayed.
- Scheduled jobs may repeatedly fail.

The severity depends on the application's operational importance.

---

## 2. Architecture

### Broken Architecture

```text
Backup Application
        |
        v
AWS STS AssumeRole
        |
        v
Lab07S3BackupRole
        |
        | ListObjectsV2
        v
Amazon S3 Bucket
        |
        v
Bucket Policy
        |
        | s3:ListBucket
        |
        v
Wrong Resource ARN
arn:aws:s3:::BUCKET/*
        |
        v
No Applicable Allow
        |
        v
AccessDenied
```

### Fixed Architecture

```text
Backup Application
        |
        v
Lab07S3BackupRole
        |
        | s3:ListBucket
        v
S3 Bucket Policy
        |
        v
Correct Bucket ARN
arn:aws:s3:::BUCKET
        |
        v
Prefix: backups/
        |
        v
Authorized Listing
        |
        v
backups/backup.txt
```

### Bucket ARN vs Object ARN

| IAM Action | Correct Resource |
|---|---|
| `s3:ListBucket` | `arn:aws:s3:::bucket-name` |
| `s3:GetObject` | `arn:aws:s3:::bucket-name/*` |
| `s3:PutObject` | `arn:aws:s3:::bucket-name/*` |
| `s3:DeleteObject` | `arn:aws:s3:::bucket-name/*` |

**Important:** Bucket-level operations require bucket ARNs, while object-level operations require object ARNs.

---

## 3. Prerequisites

Required:

- AWS account with permission to manage lab resources
- AWS CLI v2
- Ubuntu Linux / WSL2
- Bash
- IAM role creation permissions
- `sts:AssumeRole` capability
- S3 bucket policy permissions
- Git and GitHub

Use only an isolated test bucket.

Do not run the policy modifications against production infrastructure.

### Verify AWS CLI

```bash
aws --version
```

### Verify AWS Identity

```bash
aws sts get-caller-identity
```

### Configure Variables

```bash
export AWS_REGION="us-east-1"

export ACCOUNT_ID=$(aws sts get-caller-identity \
  --query Account --output text)

export BUCKET="cloud-lab07-${ACCOUNT_ID}"

export ROLE_NAME="Lab07S3BackupRole"
```

Verify:

```bash
echo "Region: $AWS_REGION"
echo "Bucket: $BUCKET"
echo "Role: $ROLE_NAME"
```

---

## 4. Create the Working Environment

### Step 1 — Create S3 Bucket

Check for an existing bucket first:

```bash
aws s3api head-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

Only create the bucket if the name is available and it is not already used by another resource.

```bash
aws s3api create-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

### Step 2 — Verify Bucket

```bash
aws s3api head-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

### Step 3 — Create Test Object

```bash
echo "S3 Lab 07 - Backup Application Test" > backup.txt
```

### Step 4 — Upload Test Object

```bash
aws s3 cp backup.txt \
  "s3://$BUCKET/backups/backup.txt" \
  --region "$AWS_REGION"
```

### Step 5 — Verify Upload

```bash
aws s3 ls "s3://$BUCKET/backups/" \
  --region "$AWS_REGION"
```

Expected object:

```text
backups/backup.txt
```

The bucket and object are now available.

---

## 5. Create the Application IAM Role

A production application should not be tested exclusively with administrator credentials.

For this exercise, we create a dedicated IAM role that has no identity-based S3 permissions.

The bucket policy will supply the intended listing permission.

### Step 1 — Identify the Current Principal

```bash
export CALLER_ARN=$(aws sts get-caller-identity \
  --query Arn --output text)

echo "$CALLER_ARN"
```

If the caller is an IAM user:

```bash
export TRUSTED_ARN="$CALLER_ARN"
```

If the caller is an assumed role, determine its underlying IAM role ARN using `aws iam get-role`.

The trust configuration must correspond to the actual authorized caller.

### Step 2 — Create Trust Policy

Create `trust-policy.json`:

```bash
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "$TRUSTED_ARN"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
```

Inspect:

```bash
cat trust-policy.json
```

### Step 3 — Create Role

```bash
aws iam create-role \
  --role-name "$ROLE_NAME" \
  --assume-role-policy-document file://trust-policy.json
```

### Step 4 — Verify Role

```bash
aws iam get-role \
  --role-name "$ROLE_NAME"
```

For the lab, do not attach a policy granting `s3:ListBucket` to this role.

**Why?** We want the bucket policy to determine whether the test role receives S3 listing permission.

---

## 6. Assume the Application Role

### Step 1 — Set Role ARN

```bash
export ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
```

### Step 2 — Assume Role

```bash
aws sts assume-role \
  --role-arn "$ROLE_ARN" \
  --role-session-name Lab07TestSession \
  --query Credentials \
  --output json > /tmp/lab07-credentials.json
```

Restrict access to the temporary credential file:

```bash
chmod 600 /tmp/lab07-credentials.json
```

### Step 3 — Export Temporary Credentials

```bash
export AWS_ACCESS_KEY_ID=$(python3 -c "import json; print(json.load(open('/tmp/lab07-credentials.json'))['AccessKeyId'])")

export AWS_SECRET_ACCESS_KEY=$(python3 -c "import json; print(json.load(open('/tmp/lab07-credentials.json'))['SecretAccessKey'])")

export AWS_SESSION_TOKEN=$(python3 -c "import json; print(json.load(open('/tmp/lab07-credentials.json'))['SessionToken'])")
```

### Step 4 — Verify Assumed Identity

```bash
aws sts get-caller-identity
```

Expected ARN pattern:

```text
arn:aws:sts::ACCOUNT_ID:assumed-role/Lab07S3BackupRole/Lab07TestSession
```

**Security:** Never commit temporary credentials, tokens, or the credential JSON to GitHub.

---

## 7. Reproduce Initial AccessDenied

Attempt to list the backup objects:

```bash
aws s3api list-objects-v2 \
  --bucket "$BUCKET" \
  --prefix "backups/" \
  --region "$AWS_REGION"
```

### Expected Error

```text
AccessDenied
```

At this stage, the test role has no applicable permission allowing `s3:ListBucket`.

Return to the original AWS identity before modifying the bucket policy:

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

Verify:

```bash
aws sts get-caller-identity
```

---

## 8. Introduce the Broken Bucket Policy

### Step 1 — Check Existing Policy

```bash
aws s3api get-bucket-policy \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

For a new bucket, `NoSuchBucketPolicy` is expected.

Do not overwrite an existing policy containing unrelated security controls.

### Step 2 — Create Broken Policy

Create `broken-bucket-policy.json`:

```bash
cat > broken-bucket-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowBackupListing",
      "Effect": "Allow",
      "Principal": {
        "AWS": "$ROLE_ARN"
      },
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::$BUCKET/*"
    }
  ]
}
EOF
```

### Step 3 — Identify the Mistake

The action is:

```json
"Action": "s3:ListBucket"
```

But the resource is:

```text
arn:aws:s3:::BUCKET/*
```

That describes objects inside the bucket, not the bucket itself.

### Step 4 — Apply Broken Policy

```bash
aws s3api put-bucket-policy \
  --bucket "$BUCKET" \
  --policy file://broken-bucket-policy.json \
  --region "$AWS_REGION"
```

**Important:** AWS may reject an invalid action/resource combination during policy validation. If that happens, record the validation error rather than claiming the broken policy was successfully attached.

If AWS accepts the policy, continue testing the role's access.

---

## 9. Reproduce the Policy Failure

Obtain fresh temporary role credentials using the same `sts assume-role` procedure.

Then attempt:

```bash
aws s3api list-objects-v2 \
  --bucket "$BUCKET" \
  --prefix "backups/" \
  --region "$AWS_REGION"
```

### Expected Result

```text
AccessDenied
```

The policy contains an `Allow`, but its resource does not match the resource type required for `s3:ListBucket`.

### Investigation Summary

| Check | Finding |
|---|---|
| AWS principal | Lab07S3BackupRole |
| Failed API | ListObjectsV2 |
| Required action | s3:ListBucket |
| Policy effect | Allow |
| Policy resource | Incorrect object ARN |
| Applicable permission | Missing |
| Result | Implicit deny |

**Important:** An ineffective bucket-policy Allow does not necessarily block a same-account identity that already has an applicable Allow elsewhere. In this lab, the test role deliberately has no identity-based S3 listing permission.

---

## 10. Root Cause Analysis

### Root Cause

The bucket policy references an object ARN for a bucket-level action.

### Technical Explanation

The `ListObjectsV2` API requires:

```text
s3:ListBucket
```

That action must reference:

```text
arn:aws:s3:::BUCKET_NAME
```

The broken policy uses:

```text
arn:aws:s3:::BUCKET_NAME/*
```

Because the resource does not match, the intended permission is ineffective.

### Root Cause Flow

```text
Application Role
       |
       v
ListObjectsV2
       |
       v
Requires s3:ListBucket
       |
       v
Policy Uses Object ARN
       |
       v
Allow Does Not Apply
       |
       v
Implicit Deny
       |
       v
AccessDenied
```

### Five Whys

1. **Why did the request fail?** The application received AccessDenied.
2. **Why was permission unavailable?** No applicable Allow authorized ListBucket.
3. **Why did the bucket policy fail to allow access?** The resource ARN did not match the required resource type.
4. **Why was the wrong ARN used?** The lab deliberately configured an object ARN for a bucket action.
5. **How can this be prevented?** Validate policies, review IAM action/resource mappings, and test effective permissions before deployment.

---

## 11. Remediation

Return to the original AWS identity:

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

### Step 1 — Create Fixed Policy

Create `fixed-bucket-policy.json`:

```bash
cat > fixed-bucket-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowBackupListing",
      "Effect": "Allow",
      "Principal": {
        "AWS": "$ROLE_ARN"
      },
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::$BUCKET",
      "Condition": {
        "StringLike": {
          "s3:prefix": [
            "backups/",
            "backups/*"
          ]
        }
      }
    }
  ]
}
EOF
```

### Step 2 — Understand the Fix

The resource is now:

```text
arn:aws:s3:::BUCKET_NAME
```

The condition restricts the allowed listing requests to:

```text
backups/
backups/*
```

This follows least-privilege principles.

### Step 3 — Apply Fixed Policy

```bash
aws s3api put-bucket-policy \
  --bucket "$BUCKET" \
  --policy file://fixed-bucket-policy.json \
  --region "$AWS_REGION"
```

### Step 4 — Inspect the Policy

```bash
aws s3api get-bucket-policy \
  --bucket "$BUCKET" \
  --region "$AWS_REGION" \
  --query Policy \
  --output text | python3 -m json.tool
```

Verify the correct bucket ARN and prefix condition.

---

## 12. Verify Remediation

Assume `Lab07S3BackupRole` again using fresh temporary credentials.

### Test 1 — Authorized Prefix

```bash
aws s3api list-objects-v2 \
  --bucket "$BUCKET" \
  --prefix "backups/" \
  --region "$AWS_REGION"
```

Expected result includes:

```text
backups/backup.txt
```

### Test 2 — Unauthorized Prefix

```bash
aws s3api list-objects-v2 \
  --bucket "$BUCKET" \
  --prefix "private/" \
  --region "$AWS_REGION"
```

Expected:

```text
AccessDenied
```

This verifies that the policy authorizes the intended prefix without granting unrestricted listing.

### Verification Summary

| Test | Expected Result |
|---|---|
| Application role identity | Verified |
| Listing before corrected policy | AccessDenied |
| Correct bucket ARN applied | Pass |
| Listing `backups/` | Success |
| Listing `private/` | AccessDenied |
| Least-privilege behavior | Verified |

The incident is resolved when the backup role can list the intended prefix and remains restricted from unrelated prefixes.

**Note:** This lab authorizes object listing only. Downloading `backup.txt` requires separate `s3:GetObject` permission.

---

## 13. Production Engineering Considerations

### Incident Triage

Investigate:

- Which AWS identity is failing?
- Which API action is denied?
- Which bucket and object prefix are involved?
- Was the bucket policy recently updated?
- Does the action require a bucket or object ARN?
- Are permission boundaries or SCPs involved?
- Is the application running in the expected AWS account?

### Evidence Collection

Useful tools include:

- AWS CLI
- AWS STS
- S3 bucket-policy inspection
- IAM Policy Simulator where applicable
- IAM Access Analyzer
- CloudTrail
- Infrastructure deployment history

### Production Remediation

A Cloud Engineer should:

1. Confirm the failing identity.
2. Identify the exact denied API action.
3. Inspect policy actions, resources, principals, and conditions.
4. Find the incorrect resource ARN.
5. Validate the corrected policy.
6. Review and approve the change.
7. Apply the minimal correction.
8. Verify intended access.
9. Test that unrelated access remains restricted.
10. Document the root cause and preventive actions.

### Prevention

- Use Infrastructure as Code.
- Validate policy syntax and resource types.
- Review policy changes through pull requests.
- Use IAM Access Analyzer policy validation.
- Test applications using their actual roles.
- Avoid administrator credentials for application testing.
- Implement least-privilege access.
- Monitor unexpected authorization failures.

---

## 14. Related S3 Policy Misconfigurations

| Misconfiguration | Potential Result |
|---|---|
| Incorrect bucket ARN | ListBucket not authorized |
| Incorrect object ARN | GetObject / PutObject failure |
| Wrong Principal ARN | Intended application not granted access |
| Incorrect prefix condition | Authorized request does not match |
| Explicit Deny | Overrides applicable Allow |
| Missing identity or resource Allow | Implicit deny |
| Incorrect account | Cross-account permission failure |
| Permission boundary or SCP | Access can remain restricted |

---

## 15. Interview Questions and Answers

### Q1. Why can an S3 bucket policy contain Allow but the application still receive AccessDenied?

The policy statement might not apply because of an incorrect principal, action, resource ARN, or condition.

Another policy or security control may also restrict access.

### Q2. What ARN is required for `s3:ListBucket`?

The bucket ARN:

```text
arn:aws:s3:::bucket-name
```

### Q3. What ARN is required for `s3:GetObject`?

An object ARN, such as:

```text
arn:aws:s3:::bucket-name/*
```

### Q4. What is an implicit deny?

An implicit deny occurs when no applicable Allow authorizes the requested action.

### Q5. What is the difference between implicit and explicit deny?

An implicit deny results from the absence of an applicable permission.

An explicit deny is a policy statement that directly rejects matching requests and overrides applicable allows.

### Q6. Why test with an assumed IAM role instead of an administrator?

Because administrator credentials may have broader permissions than the application.

Testing with the actual application role more accurately reflects its effective authorization.

### Q7. What does `s3:prefix` do?

It is a condition key used to restrict listing requests according to the requested object prefix.

It does not independently grant permission to download objects.

### Q8. Does a missing bucket-policy Allow always block access for a same-account role?

No.

A same-account role may already have permission through an applicable identity policy, subject to other authorization controls.

### Q9. How would you prevent this type of issue?

I would validate policies, review resource ARNs, use automated permission tests, and enforce infrastructure change reviews.

### Q10. How would you explain this incident in an interview?

> A backup application received AccessDenied when attempting to list S3 objects. I verified the application role and the ListObjectsV2 operation, then inspected the bucket policy. I identified that the policy used an object ARN for the bucket-level ListBucket action. I corrected the ARN, restricted the permission to the required prefix, and verified both successful authorized access and denial of unrelated prefix requests.

---

## 16. Cleanup

Return to your original AWS identity:

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

Verify:

```bash
aws sts get-caller-identity
```

### Delete Lab Bucket Policy

```bash
aws s3api delete-bucket-policy \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

### Delete IAM Role

```bash
aws iam delete-role \
  --role-name "$ROLE_NAME"
```

This assumes the role has no attached or inline policies.

### Delete Test Object

```bash
aws s3 rm "s3://$BUCKET/backups/backup.txt" \
  --region "$AWS_REGION"
```

### Delete Empty Bucket

```bash
aws s3api delete-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

Do not delete shared resources or buckets containing unrelated data.

### Delete Temporary Credentials

```bash
rm -f /tmp/lab07-credentials.json
```

Temporary credentials also expire automatically, but local credential files should still be removed.

---

## 17. Repository Structure

```text
07-s3-bucket-policy/
│
├── README.md
├── backup.txt
├── trust-policy.json
├── broken-bucket-policy.json
└── fixed-bucket-policy.json
```

**Important:** `trust-policy.json` may contain your actual principal ARN, and the policy examples may contain your AWS account ID.

Review the files before publishing. For a reusable public repository, replace account-specific principal and bucket values with placeholders such as `YOUR_ACCOUNT_ID`, `YOUR_BUCKET_NAME`, and `YOUR_ROLE_ARN`, and explain how to substitute them during lab execution.

Do not commit credentials, tokens, or temporary session files.

---

## 18. Lessons Learned

This lab demonstrates that an S3 bucket policy may contain an Allow statement without actually authorizing the intended API operation.

The failure was caused by using an object ARN for the bucket-level `s3:ListBucket` action.

The troubleshooting process involved confirming the application identity, identifying the failed API action, inspecting the policy, correcting the resource ARN, and testing effective permissions using temporary role credentials.

The main lesson is to verify that policy actions, resource types, principals, and conditions match the intended request.

---

## 19. Skills Demonstrated

- Amazon S3 troubleshooting
- Linux Bash
- AWS CLI v2
- AWS STS AssumeRole
- IAM role-based application access
- S3 bucket policy analysis
- Bucket ARN vs object ARN
- Implicit deny troubleshooting
- Least-privilege policy conditions
- Root cause analysis
- Production incident investigation
- Security-conscious remediation

## Final Outcome

| Item | Result |
|---|---|
| Incident | INC-S3-007 |
| Service | Amazon S3 |
| Error | AccessDenied |
| Failed Action | s3:ListBucket |
| Root Cause | Object ARN used for bucket-level action |
| Remediation | Corrected bucket ARN and added prefix restriction |
| Verification | Authorized prefix listing succeeds |
| Security Verification | Unrelated prefix listing denied |
| Expected Lab Status | Resolved |

**Key Takeaway:** When an S3 bucket policy appears to grant permission but a request still fails, verify the exact action, principal, resource ARN, and conditions. An Allow statement only works when it applies to the requested operation and resource.
