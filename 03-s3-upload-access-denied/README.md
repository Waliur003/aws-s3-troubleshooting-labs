# Lab 03 — S3 Upload Access Denied (`403 Forbidden`)

## Overview

This lab demonstrates how to investigate and resolve an Amazon S3 `AccessDenied` error when an application attempts to upload an object.

The scenario simulates a production issue where an S3 bucket policy contains an explicit `Deny` statement that blocks uploads to a specific object prefix.

The purpose is to understand how resource-based permissions work, identify the actual policy responsible for the failure, apply a safe remediation, and verify that upload functionality is restored.

**Troubleshooting workflow:**

Reproduce → Observe → Investigate → Identify Root Cause → Remediate → Verify → Document

## Lab Information

| Item | Details |
|---|---|
| AWS Service | Amazon S3 |
| Difficulty | Beginner–Intermediate |
| Incident ID | INC-S3-003 |
| Error | `AccessDenied` / HTTP 403 |
| AWS API | `PutObject` |
| Environment | Ubuntu Linux (WSL2) |
| Tools | AWS CLI v2, Bash |
| Root Cause | Explicit deny in S3 bucket policy |
| Remediation | Remove the lab-specific deny |
| Security Principle | Explicit Deny overrides Allow |

---

## 1. Production Incident Scenario

An application uploads reports to an Amazon S3 bucket.

The development team reports that uploads to a particular destination are failing, even though other uploads are successful.

### Reported Error

```text
An error occurred (AccessDenied) when calling the PutObject operation:
Access Denied
```

### Expected Behavior

The application should upload its file to:

```text
s3://LAB_BUCKET/blocked/upload-test.txt
```

### Actual Behavior

The upload fails with `AccessDenied`.

### Business Impact

The application cannot upload files to the affected destination.

This could interrupt report generation, file processing, backups, or other application workflows.

In production, the actual severity would depend on the number of affected users and business processes.

---

## 2. Architecture

### Working Configuration

```text
Application / AWS CLI
         |
         | s3:PutObject
         v
    Amazon S3
         |
         v
    S3 Bucket
         |
         v
baseline/upload-test.txt
         |
         v
    Upload Success
```

### Broken Configuration

```text
Application / AWS CLI
         |
         | s3:PutObject
         v
    S3 Bucket Policy
         |
         v
   Explicit Deny
         |
         v
blocked/upload-test.txt
         |
         X
   403 AccessDenied
```

### Permission Evaluation

```text
IAM Permission Allows Upload
             |
             v
S3 Bucket Policy Evaluation
             |
             v
      Explicit Deny
             |
             v
        ACCESS DENIED
```

An applicable explicit deny overrides an allow.

---

## 3. Prerequisites

- AWS account with permissions to manage a dedicated test bucket
- AWS CLI v2
- Ubuntu Linux / WSL2
- Bash terminal
- Permissions to read and modify the lab bucket policy
- Permissions to upload, download, list, and delete test objects

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

export BUCKET="cloud-lab03-${ACCOUNT_ID}"
```

Verify:

```bash
echo "Region: $AWS_REGION"
echo "Bucket: $BUCKET"
```

These variables must be recreated if a new Bash session is opened.

---

## 4. Create the Working Environment

### Step 1 — Create the Bucket

Check whether the bucket already exists:

```bash
aws s3api head-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

If it does not exist and the name is available:

```bash
aws s3api create-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

This example uses `us-east-1`.

Keep the default S3 Block Public Access protections enabled.

### Step 2 — Create the Test File

```bash
echo "Cloud Engineering S3 Lab 03 - Upload Test" > upload-test.txt
```

Verify:

```bash
cat upload-test.txt
```

### Step 3 — Establish a Working Baseline

```bash
aws s3 cp upload-test.txt \
  "s3://$BUCKET/baseline/upload-test.txt" \
  --region "$AWS_REGION"
```

Verify the object:

```bash
aws s3api head-object \
  --bucket "$BUCKET" \
  --key "baseline/upload-test.txt" \
  --region "$AWS_REGION"
```

A successful response confirms that the object is accessible.

This working baseline helps distinguish the later policy failure from an unrelated configuration problem.

---

## 5. Introduce the Failure

We will deliberately configure the lab bucket to reject uploads under the `blocked/` prefix.

### Step 1 — Check for Existing Bucket Policy

```bash
aws s3api get-bucket-policy \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

For a new lab bucket, `NoSuchBucketPolicy` is expected.

Do not overwrite an existing production or shared bucket policy.

### Step 2 — Create a Restrictive Policy

Create `deny-upload-policy.json`:

```bash
cat > deny-upload-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Lab03DenyUploadsToBlockedPrefix",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::$BUCKET/blocked/*"
    }
  ]
}
EOF
```

Inspect:

```bash
cat deny-upload-policy.json
```

The critical configuration is:

```json
{
  "Effect": "Deny",
  "Action": "s3:PutObject"
}
```

The resource ARN restricts the deny to the `blocked/` prefix.

**Security note:** `Principal: "*"` makes the deny applicable to any principal performing the specified action on the matching objects. This is appropriate only for this controlled sandbox exercise.

### Step 3 — Apply the Bucket Policy

```bash
aws s3api put-bucket-policy \
  --bucket "$BUCKET" \
  --policy file://deny-upload-policy.json \
  --region "$AWS_REGION"
```

Verify:

```bash
aws s3api get-bucket-policy \
  --bucket "$BUCKET" \
  --region "$AWS_REGION" \
  --query Policy \
  --output text | python3 -m json.tool
```

Confirm the deny statement is present.

---

## 6. Reproduce the Incident

Attempt to upload the file to the restricted prefix:

```bash
aws s3api put-object \
  --bucket "$BUCKET" \
  --key "blocked/upload-test.txt" \
  --body upload-test.txt \
  --region "$AWS_REGION"
```

### Expected Error

```text
An error occurred (AccessDenied) when calling the PutObject operation:
Access Denied
```

Depending on the request context, AWS may provide additional information identifying an explicit deny in a resource-based policy.

The simulated incident has now been reproduced.

---

## 7. Troubleshooting Investigation

### Check 1 — Verify the AWS Identity

```bash
aws sts get-caller-identity
```

**Purpose:** Verify that the request uses the intended AWS account and principal.

### Check 2 — Verify the Existing Baseline Object

```bash
aws s3api head-object \
  --bucket "$BUCKET" \
  --key "baseline/upload-test.txt" \
  --region "$AWS_REGION"
```

The existing object should remain accessible.

### Check 3 — Inspect the Bucket Policy

```bash
aws s3api get-bucket-policy \
  --bucket "$BUCKET" \
  --region "$AWS_REGION" \
  --query Policy \
  --output text | python3 -m json.tool
```

Look for:

```text
Effect: Deny
Action: s3:PutObject
Resource: arn:aws:s3:::BUCKET/blocked/*
```

### Check 4 — Test an Unrestricted Prefix

```bash
aws s3api put-object \
  --bucket "$BUCKET" \
  --key "baseline/second-test.txt" \
  --body upload-test.txt \
  --region "$AWS_REGION"
```

This should succeed if the caller has the necessary permissions and no other controls deny the request.

### Check 5 — Compare Results

| Test | Expected Result |
|---|---|
| Upload to `baseline/` | Successful |
| Upload to `blocked/` | AccessDenied |
| Read existing baseline object | Successful |
| Inspect bucket policy | Explicit deny found |

### Investigation Finding

The issue is limited to uploads targeting the `blocked/` prefix.

The bucket policy contains a statement explicitly denying `s3:PutObject` for those objects.

---

## 8. Root Cause Analysis

### Root Cause

The S3 bucket policy contains an explicit `Deny` statement that blocks `s3:PutObject` operations under the `blocked/` prefix.

### Technical Explanation

The denied object resource matches:

```text
arn:aws:s3:::BUCKET_NAME/blocked/*
```

Although the caller may have permission to upload objects through an IAM identity policy, the matching explicit deny prevents the operation.

### Root Cause Flow

```text
PutObject Request
        |
        v
Object Key: blocked/upload-test.txt
        |
        v
Bucket Policy Matches Resource
        |
        v
Explicit Deny Applies
        |
        v
403 AccessDenied
```

### Five Whys

1. **Why did the upload fail?** S3 returned `AccessDenied`.
2. **Why was access denied?** A bucket policy explicitly denied the operation.
3. **Why did the policy apply?** The upload targeted the `blocked/` prefix.
4. **Why was the deny present?** The lab deliberately added it to simulate an incident.
5. **How could this be prevented in production?** Use policy review, infrastructure change controls, automated testing, and monitoring.

---

## 9. Remediation

In the isolated lab, the restrictive policy can be safely removed after confirming it was created solely for this exercise.

### Step 1 — Remove the Lab Bucket Policy

```bash
aws s3api delete-bucket-policy \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

**Production consideration:** In a real environment, do not remove an entire bucket policy if it contains other security controls. Modify only the incorrect statement using an approved change process.

### Step 2 — Retry the Failed Upload

```bash
aws s3api put-object \
  --bucket "$BUCKET" \
  --key "blocked/upload-test.txt" \
  --body upload-test.txt \
  --region "$AWS_REGION"
```

A successful response should contain object metadata such as an ETag.

### Step 3 — Verify the Object

```bash
aws s3api head-object \
  --bucket "$BUCKET" \
  --key "blocked/upload-test.txt" \
  --region "$AWS_REGION"
```

The object should now exist.

---

## 10. Verification

Download the uploaded file:

```bash
aws s3api get-object \
  --bucket "$BUCKET" \
  --key "blocked/upload-test.txt" \
  verified-upload.txt \
  --region "$AWS_REGION"
```

Read it:

```bash
cat verified-upload.txt
```

Expected:

```text
Cloud Engineering S3 Lab 03 - Upload Test
```

Compare it with the original:

```bash
diff upload-test.txt verified-upload.txt
```

No output means the file contents match.

### Final Verification Summary

| Check | Expected Result |
|---|---|
| Restricted upload before fix | AccessDenied |
| Bucket policy inspected | Explicit deny identified |
| Upload outside restricted prefix | Successful |
| Restrictive policy removed | Successful |
| Original failed upload retried | Successful |
| Object downloaded | Successful |
| File integrity checked | Files identical |

These are expected outcomes; the actual lab results should be verified from AWS CLI output.

---

## 11. Production Engineering Considerations

### Incident Triage

Before applying any fix, determine:

- Which application is affected?
- Which uploads are failing?
- When did the issue begin?
- Was there a recent bucket policy change?
- Are other services using the same bucket?

### Evidence Collection

Useful investigation sources include:

- AWS CLI error responses
- S3 bucket policy
- IAM identity policies
- CloudTrail S3 data events, if enabled
- Application logs
- Deployment and infrastructure change history

### Safe Remediation

A Cloud Engineer should:

1. Confirm which policy caused the failure.
2. Review the security purpose of the restriction.
3. Verify the requested upload is authorized.
4. Obtain necessary approvals.
5. Apply a minimal, reversible change.
6. Test the original failing operation.
7. Monitor the application after recovery.

### Prevention

- Manage bucket policies through Infrastructure as Code where appropriate.
- Require policy reviews before deployment.
- Use automated tests for critical application permissions.
- Monitor repeated S3 access failures.
- Document access requirements for applications.
- Avoid broad or unnecessary permissions.

---

## 12. Related AWS Permission Errors

| Error | Investigation |
|---|---|
| `AccessDenied` | IAM, bucket policies, SCPs, encryption, endpoint policies |
| `NoSuchBucket` | Bucket name and existence |
| `NoSuchKey` | Exact object key and existence |
| `InvalidAccessKeyId` | AWS credentials |
| `SignatureDoesNotMatch` | Request signing and credential configuration |
| KMS access failure | KMS key permissions and encryption configuration |

S3 `AccessDenied` is not always caused by an IAM identity policy. The complete authorization context matters.

---

## 13. Interview Questions and Answers

### Q1. Why can an S3 upload fail even when an IAM role has `s3:PutObject` permission?

An applicable explicit deny in a bucket policy or another authorization control can override the IAM allow.

### Q2. How would you troubleshoot an S3 `403 AccessDenied` upload failure?

First, confirm the AWS identity, bucket, object key, and failed API operation. Then inspect relevant identity policies, bucket policies, and applicable security controls. Identify the specific deny, apply an approved minimal fix, and verify the upload works.

### Q3. What is the difference between IAM policies and S3 bucket policies?

IAM identity policies attach permissions to identities such as users and roles.

S3 bucket policies are resource-based policies attached to buckets. They can grant or deny access to specified principals for matching S3 actions and resources.

Both contribute to the authorization decision.

### Q4. Does an explicit deny override an allow?

Yes. An applicable explicit deny overrides an otherwise applicable allow in AWS policy evaluation.

### Q5. Why did uploading to `baseline/` work but uploading to `blocked/` fail?

The bucket policy's resource ARN matched objects under `blocked/` but not objects under `baseline/`.

### Q6. Should you delete the bucket policy immediately when troubleshooting AccessDenied?

No.

First inspect the complete policy and understand its security purpose. In production, removing an entire bucket policy could unintentionally weaken access controls.

### Q7. How would you prevent this type of incident?

I would manage policies through reviewed infrastructure changes, validate application access requirements, automate permission tests, and monitor failed uploads.

---

## 14. Cleanup

After verification, confirm the bucket:

```bash
echo "$BUCKET"
```

Inspect its contents:

```bash
aws s3 ls "s3://$BUCKET/" \
  --recursive \
  --region "$AWS_REGION"
```

If this is the dedicated lab bucket containing only test objects, delete its objects:

```bash
aws s3 rm "s3://$BUCKET/" \
  --recursive \
  --region "$AWS_REGION"
```

Delete the empty bucket:

```bash
aws s3api delete-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

These commands assume versioning was not enabled and no unrelated objects were added.

Remove temporary local output:

```bash
rm -f verified-upload.txt
```

Keep the following local files as documentation artifacts:

```text
upload-test.txt
deny-upload-policy.json
README.md
```

---

## 15. Repository Structure

```text
03-s3-upload-access-denied/
│
├── README.md
├── upload-test.txt
└── deny-upload-policy.json
```

The policy JSON is included only as an educational example. Do not apply it to production buckets without reviewing the consequences.

---

## 16. Lessons Learned

This lab demonstrates that an application may fail to upload objects to Amazon S3 even when its AWS identity has upload permissions.

The failure occurred because the S3 bucket policy contained an explicit deny targeting a specific object prefix.

The investigation used AWS CLI commands to verify identity, inspect the bucket policy, compare successful and unsuccessful uploads, and confirm the root cause.

After removing the lab-specific restriction, the original upload request succeeded.

The key lesson is to investigate the actual policy evaluation result instead of adding broad permissions or disabling security controls.

---

## 17. Skills Demonstrated

- Amazon S3 troubleshooting
- AWS CLI on Linux
- Bash commands
- Resource-based policies
- Explicit deny evaluation
- S3 PutObject investigation
- Root cause analysis
- Access remediation
- File integrity verification
- Production incident documentation
- Least-privilege security awareness

## Final Outcome

| Item | Result |
|---|---|
| Incident | INC-S3-003 |
| Problem | S3 upload returned AccessDenied |
| Cause | Explicit deny in bucket policy |
| Affected Resource | `blocked/` object prefix |
| Remediation | Removed lab-specific deny |
| Verification | Successful upload and file comparison |
| Expected Status | Resolved |

**Key Takeaway:** When an S3 upload returns `AccessDenied`, investigate identity permissions, resource policies, and other applicable authorization controls before changing access settings.
