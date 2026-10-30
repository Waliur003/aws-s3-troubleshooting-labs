# Lab 12 — Amazon S3 SSE-KMS Encryption AccessDenied

## Overview

This hands-on lab demonstrates how to troubleshoot an Amazon S3 object download failure caused by missing AWS Key Management Service (KMS) permissions.

In the simulated production incident, an application IAM role has permission to read a specific S3 object using `s3:GetObject`. However, the object is encrypted with a customer-managed KMS key, and the role does not have `kms:Decrypt`.

As a result, the application receives `AccessDenied` even though its S3 read permission is correctly configured.

The lab demonstrates how to investigate both authorization layers and implement a least-privilege remediation.

**Troubleshooting workflow:**

Establish Baseline → Reproduce Failure → Investigate S3 and KMS → Identify Root Cause → Remediate → Verify → Cleanup

## Lab Information

| Item | Details |
|---|---|
| AWS Service | Amazon S3 + AWS KMS |
| Incident ID | INC-S3-012 |
| Difficulty | Intermediate–Advanced |
| Error | `AccessDenied` |
| Failed API | `GetObject` |
| Encryption | SSE-KMS |
| KMS Key | Customer-managed symmetric key |
| Test Role | `Lab12S3KMSReaderRole` |
| Environment | Ubuntu Linux (WSL2) |
| Tools | AWS CLI v2, Bash, Python 3 |
| Root Cause | Missing `kms:Decrypt` |
| Remediation | Least-privilege KMS decrypt permission |
| Verification | Successful download and file comparison |

---

## 1. Production Incident Scenario

### Incident Description

An application stores reports inside an Amazon S3 bucket using server-side encryption with AWS KMS.

A new application IAM role is deployed with permission to retrieve the reports.

However, when the application attempts to download an encrypted object, it receives an authorization error.

### Reported Error

```text
An error occurred (AccessDenied) when calling
the GetObject operation: Access Denied
```

### Expected Behavior

The application should download:

```text
s3://LAB_BUCKET/reports/encrypted-report.txt
```

### Actual Behavior

The application role can be authorized for `s3:GetObject` but cannot use the KMS key required for decryption.

### Potential Business Impact

- Applications cannot retrieve encrypted data.
- Backup recovery processes may fail.
- Data-processing pipelines may stop.
- Business reports may become temporarily inaccessible.
- Incorrect permission changes could weaken security.

### Investigation Objective

Determine whether the failure is caused by S3 permissions, AWS KMS permissions, or both.

---

## 2. Architecture

### Broken Configuration

```text
Application
     |
     v
IAM Role: Lab12S3KMSReaderRole
     |
     | s3:GetObject = Allowed
     v
Amazon S3
     |
     v
reports/encrypted-report.txt
     |
     | Encryption: SSE-KMS
     v
Customer-Managed KMS Key
     |
     | kms:Decrypt = Missing
     v
AccessDenied
```

### Corrected Configuration

```text
Application
     |
     v
IAM Role
     |
     +-- s3:GetObject
     |
     +-- kms:Decrypt
     |      |
     |      +-- Specific KMS Key
     |      +-- Via Amazon S3
     |      +-- Intended AWS Account
     |
     v
Amazon S3 + AWS KMS
     |
     v
Decryption Authorized
     |
     v
Successful Download
```

---

## 3. Understanding SSE-KMS

Server-Side Encryption with AWS KMS keys (SSE-KMS) allows S3 to encrypt stored objects using data keys protected by AWS KMS.

When an authorized client uploads an SSE-KMS object, Amazon S3 uses KMS to obtain the data key required for encryption.

When an authorized client downloads the object, Amazon S3 uses KMS to decrypt the protected data key.

### Required Permissions

| Operation | Permissions |
|---|---|
| Upload encrypted object | `s3:PutObject`, `kms:GenerateDataKey` |
| Download encrypted object | `s3:GetObject`, `kms:Decrypt` |
| Multipart upload with SSE-KMS | `s3:PutObject`, `kms:GenerateDataKey`, `kms:Decrypt` |
| Inspect object metadata | `s3:GetObject` for `HeadObject` |
| Inspect key policy | `kms:GetKeyPolicy` |

### Why IAM Permission Alone May Not Be Enough

AWS KMS evaluates key policies, IAM policies, grants, and applicable restrictive policies.

An IAM policy granting `kms:Decrypt` is effective only when the KMS key's authorization configuration permits that access, such as through appropriate IAM policy delegation in the key policy.

This lab uses the default customer-managed key policy and verifies that delegation is available.

---

## 4. Prerequisites

- AWS account with an isolated sandbox environment
- AWS CLI v2
- Ubuntu Linux / WSL2
- Bash
- Python 3
- Permission to create an S3 bucket
- Permission to create a customer-managed KMS key
- Permission to manage an isolated IAM role
- Permission to assume the test role
- Git and GitHub

### Cost Warning

Customer-managed KMS keys and KMS API requests may incur charges.

Key deletion is not immediate. AWS KMS requires a waiting period of 7–30 days, and a key scheduled for deletion becomes unavailable for cryptographic operations.

Never schedule deletion of a key used by production resources.

### Verify AWS CLI

```bash
aws --version
```

### Verify Identity

```bash
aws sts get-caller-identity
```

### Configure Environment Variables

```bash
export AWS_REGION="us-east-1"

export ACCOUNT_ID=$(aws sts get-caller-identity \
  --query Account --output text)

export BUCKET="cloud-lab12-${ACCOUNT_ID}"

export OBJECT_KEY="reports/encrypted-report.txt"

export ROLE_NAME="Lab12S3KMSReaderRole"
```

Verify:

```bash
echo "$AWS_REGION"
echo "$BUCKET"
echo "$OBJECT_KEY"
echo "$ROLE_NAME"
```

---

## 5. Create the Private S3 Bucket

### Step 1 — Check the Bucket Name

```bash
aws s3api head-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

If the bucket already exists, investigate ownership and contents instead of overwriting it.

### Step 2 — Create the Bucket

```bash
aws s3api create-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

### Step 3 — Enable Block Public Access

```bash
aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
  --region "$AWS_REGION"
```

### Step 4 — Verify

```bash
aws s3api get-public-access-block \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

All four values should be `true`.

---

## 6. Create the Customer-Managed KMS Key

### Step 1 — Create the Key

```bash
export KEY_ID=$(aws kms create-key \
  --description "Lab12 S3 SSE-KMS troubleshooting key" \
  --query 'KeyMetadata.KeyId' \
  --output text \
  --region "$AWS_REGION")
```

### Step 2 — Verify

```bash
aws kms describe-key \
  --key-id "$KEY_ID" \
  --region "$AWS_REGION"
```

Expected:

```text
KeyState: Enabled
KeyUsage: ENCRYPT_DECRYPT
```

### Step 3 — Get the Key ARN

```bash
export KEY_ARN=$(aws kms describe-key \
  --key-id "$KEY_ID" \
  --query 'KeyMetadata.Arn' \
  --output text \
  --region "$AWS_REGION")
```

Check:

```bash
echo "$KEY_ARN"
```

### Step 4 — Inspect the Key Policy

```bash
aws kms get-key-policy \
  --key-id "$KEY_ID" \
  --policy-name default \
  --output text \
  --region "$AWS_REGION" | python3 -m json.tool
```

Verify the default policy enables the owning account to delegate key access through IAM policies.

Do not remove administrative access to the KMS key.

---

## 7. Upload an SSE-KMS-Encrypted Object

### Step 1 — Create the Test Report

Create `encrypted-report.txt`:

```bash
cat > encrypted-report.txt <<'EOF'
Cloud Engineering Lab 12

Application: Backup Reporting
Data Classification: Lab Test Data
Encryption: SSE-KMS
Status: Ready for Troubleshooting
EOF
```

### Step 2 — Upload with SSE-KMS

```bash
aws s3api put-object \
  --bucket "$BUCKET" \
  --key "$OBJECT_KEY" \
  --body encrypted-report.txt \
  --server-side-encryption aws:kms \
  --ssekms-key-id "$KEY_ARN" \
  --region "$AWS_REGION"
```

### Step 3 — Verify Encryption Metadata

```bash
aws s3api head-object \
  --bucket "$BUCKET" \
  --key "$OBJECT_KEY" \
  --query '{Encryption:ServerSideEncryption,KMSKey:SSEKMSKeyId,Size:ContentLength}' \
  --region "$AWS_REGION"
```

Expected:

```text
Encryption: aws:kms
KMSKey: Customer-managed KMS key ARN
```

### Step 4 — Verify Working Baseline

```bash
aws s3api get-object \
  --bucket "$BUCKET" \
  --key "$OBJECT_KEY" \
  baseline-report.txt \
  --region "$AWS_REGION"
```

Compare:

```bash
diff encrypted-report.txt baseline-report.txt
```

No output means the content matches.

---

## 8. Create the Application IAM Role

We use an isolated role to avoid testing with administrator permissions.

### Step 1 — Identify the Caller

```bash
export CALLER_ARN=$(aws sts get-caller-identity \
  --query Arn --output text)

echo "$CALLER_ARN"
```

For an IAM user:

```bash
export TRUSTED_ARN="$CALLER_ARN"
```

For an assumed role, retrieve the underlying IAM role ARN using `aws iam get-role`.

Confirm that `TRUSTED_ARN` refers to the actual caller you intend to trust.

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

### Step 3 — Create Role

```bash
aws iam create-role \
  --role-name "$ROLE_NAME" \
  --assume-role-policy-document file://trust-policy.json
```

### Step 4 — Get Role ARN

```bash
export ROLE_ARN=$(aws iam get-role \
  --role-name "$ROLE_NAME" \
  --query Role.Arn \
  --output text)
```

The caller also needs permission to assume the role. If role assumption fails, diagnose the trust and caller permissions instead of granting unnecessary administrative access.

---

## 9. Configure the Broken IAM Policy

### Step 1 — Create S3-Only Policy

Create `s3-only-policy.json`:

```bash
cat > s3-only-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadEncryptedReport",
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::$BUCKET/$OBJECT_KEY"
    }
  ]
}
EOF
```

### Step 2 — Attach Policy

```bash
aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name Lab12ReadPolicy \
  --policy-document file://s3-only-policy.json
```

### Intentional Misconfiguration

The role has:

```text
s3:GetObject = Allowed
```

But does not have:

```text
kms:Decrypt
```

This is the deliberate failure.

---

## 10. Create a Role Testing Script

Create `assume-test-role.sh`:

```bash
cat > assume-test-role.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "Usage: ./assume-test-role.sh aws COMMAND..."
  exit 1
fi

unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

CREDS=$(aws sts assume-role \
  --role-arn "$ROLE_ARN" \
  --role-session-name Lab12KMSReader \
  --query Credentials \
  --output json)

export AWS_ACCESS_KEY_ID=$(python3 -c \
  'import sys,json; print(json.load(sys.stdin)["AccessKeyId"])' <<< "$CREDS")

export AWS_SECRET_ACCESS_KEY=$(python3 -c \
  'import sys,json; print(json.load(sys.stdin)["SecretAccessKey"])' <<< "$CREDS")

export AWS_SESSION_TOKEN=$(python3 -c \
  'import sys,json; print(json.load(sys.stdin)["SessionToken"])' <<< "$CREDS")

exec "$@"
EOF
```

Make it executable:

```bash
chmod 700 assume-test-role.sh
```

The helper obtains temporary role credentials for individual commands without changing the calling shell's AWS credential variables.

**Security:** The generated script relies on your current AWS credential source. Review it before using it in another environment, especially if your shell already contains temporary credentials.

---

## 11. Reproduce AccessDenied

### Step 1 — Verify Test Identity

```bash
./assume-test-role.sh aws sts get-caller-identity
```

Expected role:

```text
Lab12S3KMSReaderRole
```

### Step 2 — Attempt Encrypted Download

```bash
./assume-test-role.sh aws s3api get-object \
  --bucket "$BUCKET" \
  --key "$OBJECT_KEY" \
  failed-download.txt \
  --region "$AWS_REGION"
```

### Expected Error

```text
An error occurred (AccessDenied) when calling
the GetObject operation: Access Denied
```

### Failure Explanation

The application role can be authorized to retrieve the S3 object, but Amazon S3 cannot complete the KMS decryption operation on behalf of that role.

The role lacks the applicable `kms:Decrypt` permission.

---

## 12. Troubleshooting Investigation

### Check 1 — Verify the Application Identity

```bash
./assume-test-role.sh aws sts get-caller-identity
```

### Check 2 — Inspect the Object's Encryption

```bash
aws s3api head-object \
  --bucket "$BUCKET" \
  --key "$OBJECT_KEY" \
  --query '{Encryption:ServerSideEncryption,KMSKey:SSEKMSKeyId}' \
  --region "$AWS_REGION"
```

### Check 3 — Inspect IAM Policy

```bash
aws iam get-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name Lab12ReadPolicy
```

Look for `s3:GetObject`.

Notice that `kms:Decrypt` is missing.

### Check 4 — Inspect the KMS Key

```bash
aws kms describe-key \
  --key-id "$KEY_ID" \
  --region "$AWS_REGION"
```

Verify that the key exists, is enabled, and is located in the same Region as the S3 bucket.

### Check 5 — Inspect the Key Policy

```bash
aws kms get-key-policy \
  --key-id "$KEY_ID" \
  --policy-name default \
  --output text \
  --region "$AWS_REGION" | python3 -m json.tool
```

Confirm IAM delegation is enabled.

### Investigation Summary

| Check | Finding |
|---|---|
| S3 object | Exists |
| Encryption | SSE-KMS |
| KMS key | Customer-managed |
| Key state | Enabled |
| Application role | Lab12S3KMSReaderRole |
| `s3:GetObject` | Allowed |
| `kms:Decrypt` | Missing |
| Download | AccessDenied |
| Root cause | Missing KMS decryption permission |

---

## 13. Root Cause Analysis

### Root Cause

The application IAM role lacks `kms:Decrypt` permission for the customer-managed KMS key used to encrypt the S3 object.

### Technical Explanation

SSE-KMS requires authorization at two separate layers:

1. Amazon S3 evaluates the requester's permission to retrieve the object.
2. AWS KMS authorization determines whether the encrypted data key can be decrypted for that request.

Allowing `s3:GetObject` alone does not satisfy the KMS authorization requirement.

### Root Cause Flow

```text
Application Role
       |
       v
GetObject Request
       |
       v
S3 Authorization
s3:GetObject = Allow
       |
       v
SSE-KMS Decryption Required
       |
       v
KMS Authorization
kms:Decrypt = Missing
       |
       v
AccessDenied
```

### Five Whys

1. **Why did the download fail?** The application received AccessDenied.
2. **Why was access denied?** The encrypted object required KMS decryption.
3. **Why was decryption unavailable?** The role lacked `kms:Decrypt`.
4. **Why did S3 permission not solve the issue?** S3 and KMS evaluate separate permissions.
5. **How can this be prevented?** Validate both S3 and KMS authorization before deploying encrypted-storage integrations.

---

## 14. Least-Privilege Remediation

### Step 1 — Create Corrected IAM Policy

Create `fixed-s3-kms-policy.json`:

```bash
cat > fixed-s3-kms-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadEncryptedReport",
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::$BUCKET/$OBJECT_KEY"
    },
    {
      "Sid": "DecryptReportViaS3",
      "Effect": "Allow",
      "Action": "kms:Decrypt",
      "Resource": "$KEY_ARN",
      "Condition": {
        "StringEquals": {
          "kms:ViaService": "s3.${AWS_REGION}.amazonaws.com",
          "kms:CallerAccount": "$ACCOUNT_ID"
        }
      }
    }
  ]
}
EOF
```

### Step 2 — Understand the Conditions

| Setting | Purpose |
|---|---|
| `kms:Decrypt` | Permits key decryption |
| Specific KMS key ARN | Prevents using unrelated keys |
| `kms:ViaService` | Requires use through Amazon S3 |
| `kms:CallerAccount` | Restricts requests to the intended account |

For stronger production isolation, consider an appropriate KMS encryption-context condition that identifies the intended S3 object or bucket, taking S3 Bucket Keys and encryption-context behavior into account.

### Step 3 — Apply Corrected Policy

```bash
aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name Lab12ReadPolicy \
  --policy-document file://fixed-s3-kms-policy.json
```

### Step 4 — Verify Policy

```bash
aws iam get-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name Lab12ReadPolicy
```

The role now has the intended S3 and KMS permissions.

This remediation assumes the KMS key policy permits IAM delegation. If it does not, an appropriate key-policy or grant change is also required.

---

## 15. Verify Successful Recovery

### Step 1 — Retry the Download

```bash
./assume-test-role.sh aws s3api get-object \
  --bucket "$BUCKET" \
  --key "$OBJECT_KEY" \
  recovered-report.txt \
  --region "$AWS_REGION"
```

Expected result: successful object download.

### Step 2 — Verify Contents

```bash
cat recovered-report.txt
```

Expected:

```text
Cloud Engineering Lab 12

Application: Backup Reporting
Data Classification: Lab Test Data
Encryption: SSE-KMS
Status: Ready for Troubleshooting
```

### Step 3 — Compare File Integrity

```bash
diff encrypted-report.txt recovered-report.txt
```

No output means the files match.

### Step 4 — Verify S3 Public Access Protection

```bash
aws s3api get-public-access-block \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

Confirm all four settings remain enabled.

### Verification Summary

| Test | Before Fix | After Fix |
|---|---|---|
| S3 object exists | Yes | Yes |
| SSE-KMS encryption | Enabled | Enabled |
| `s3:GetObject` | Allowed | Allowed |
| `kms:Decrypt` | Missing | Allowed |
| Download | AccessDenied | Success |
| Data integrity | Not verified | Matches original |
| Public access | Blocked | Blocked |

The incident is resolved when the application role can retrieve the encrypted object without introducing unnecessarily broad permissions.

---

## 16. Production Engineering Considerations

### Incident Triage

Investigate:

- Which AWS identity is failing?
- Does the S3 object exist?
- Does the object use SSE-KMS?
- Which KMS key encrypted the object?
- Does the role have `s3:GetObject`?
- Does the role have `kms:Decrypt`?
- Does the key policy permit the requested operation?
- Are permission boundaries or SCPs involved?
- Is the KMS key enabled?
- Are the S3 bucket and KMS key in the same Region?

### Evidence Collection

Useful tools include:

- AWS CLI
- AWS STS
- S3 object metadata
- IAM policy inspection
- KMS key policy inspection
- CloudTrail events, when recorded
- IAM Access Analyzer
- Application logs
- Deployment history

### Production Remediation Workflow

1. Confirm the application identity.
2. Reproduce the failing download.
3. Inspect the object's encryption settings.
4. Identify the KMS key ARN.
5. Review the role's permissions.
6. Review the key policy and applicable grants.
7. Identify the missing or restrictive permission.
8. Apply a narrowly scoped correction.
9. Verify the application's download.
10. Confirm public access remains blocked.
11. Document the incident.

---

## 17. Security Best Practices

- Use dedicated application IAM roles.
- Apply least privilege.
- Avoid wildcard KMS permissions.
- Limit access to specific KMS keys.
- Use `kms:ViaService` where appropriate.
- Restrict permissions by account and encryption context when practical.
- Maintain KMS key administration access.
- Keep S3 Block Public Access enabled.
- Monitor KMS and S3 failures.
- Review IAM and key-policy changes through pull requests.
- Do not publish credentials or sensitive key-policy details.

### Important KMS Security Principle

Customer-managed KMS keys provide greater control over encryption authorization, but they also introduce operational responsibility.

Accidental key disabling, policy changes, or key deletion can make encrypted data unavailable.

---

## 18. Related S3 and KMS Errors

| Error | Possible Cause |
|---|---|
| S3 GetObject AccessDenied | Missing S3 or KMS permission |
| KMS AccessDeniedException | Missing KMS authorization |
| KMS DisabledException | KMS key disabled |
| KMS NotFoundException | Incorrect or missing key |
| IncorrectKeyException | Encryption key mismatch |
| KMS InvalidKeyUsageException | Key incompatible with requested operation |
| S3 PutObject AccessDenied | Missing `s3:PutObject` or `kms:GenerateDataKey` |
| Encrypted multipart upload failure | Missing relevant KMS permissions |

---

## 19. Interview Questions and Answers

### Q1. What is SSE-KMS?

SSE-KMS is Amazon S3 server-side encryption using data keys protected by AWS Key Management Service.

### Q2. Why can GetObject fail even when s3:GetObject is allowed?

If the object uses SSE-KMS, the requester also needs permission to use the KMS key for decryption.

### Q3. Which KMS permission is needed to download an SSE-KMS object?

`kms:Decrypt`.

### Q4. Which KMS permission is needed to upload an SSE-KMS object?

Typically, `kms:GenerateDataKey`. Multipart uploads also require `kms:Decrypt`.

### Q5. Is an IAM policy allowing kms:Decrypt always sufficient?

No. The KMS key policy must also permit access, directly or through IAM policy delegation, and other restrictions must not block the operation.

### Q6. What is kms:ViaService?

It is a KMS condition key that can restrict key use to requests made through an integrated AWS service, such as Amazon S3.

### Q7. How do you identify an S3 object's KMS key?

Inspect the `SSEKMSKeyId` field returned by `HeadObject`.

### Q8. Should you give an application kms:* to fix decryption?

No. Grant only the specific operations and key access required by the application.

### Q9. What happens if a KMS key is scheduled for deletion?

The key enters `PendingDeletion` and becomes unavailable for cryptographic operations during the waiting period. Permanent deletion can make encrypted data unrecoverable.

### Q10. How would you explain this incident in an interview?

> An application received AccessDenied while downloading an SSE-KMS-encrypted S3 object. I verified the application role, the S3 object, and its encryption metadata. The role already had s3:GetObject but lacked kms:Decrypt for the customer-managed KMS key. I inspected the key policy, applied a narrowly scoped IAM permission limited to the key and S3 service, and verified that the application could download the object successfully without changing public access settings.

---

## 20. Cleanup

### Step 1 — Verify Resources

```bash
aws sts get-caller-identity

echo "$BUCKET"
echo "$OBJECT_KEY"
echo "$ROLE_NAME"
echo "$KEY_ARN"
```

Confirm that you are operating in the intended sandbox account.

### Step 2 — Remove the Application Role Policy

```bash
aws iam delete-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name Lab12ReadPolicy
```

### Step 3 — Delete the Application Role

```bash
aws iam delete-role \
  --role-name "$ROLE_NAME"
```

This assumes no additional policies or dependencies exist.

### Step 4 — Inspect the S3 Bucket

```bash
aws s3 ls "s3://$BUCKET/" \
  --recursive \
  --region "$AWS_REGION"
```

Confirm it contains only the Lab 12 test object.

### Step 5 — Delete the Object

```bash
aws s3api delete-object \
  --bucket "$BUCKET" \
  --key "$OBJECT_KEY" \
  --region "$AWS_REGION"
```

### Step 6 — Delete the Bucket

```bash
aws s3api delete-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

These operations assume bucket versioning was not enabled and no unrelated data was added.

### Step 7 — Schedule KMS Key Deletion

**Warning:** This is a destructive operation. Verify that the key was created exclusively for Lab 12 and is not protecting other data.

```bash
aws kms schedule-key-deletion \
  --key-id "$KEY_ID" \
  --pending-window-in-days 7 \
  --region "$AWS_REGION"
```

### Step 8 — Verify Pending Deletion

```bash
aws kms describe-key \
  --key-id "$KEY_ID" \
  --region "$AWS_REGION" \
  --query 'KeyMetadata.{State:KeyState,DeletionDate:DeletionDate}'
```

Expected:

```text
PendingDeletion
```

Do not schedule key deletion until the encrypted lab object has been removed and any possible dependencies have been reviewed.

### Step 9 — Remove Temporary Files

```bash
rm -f baseline-report.txt \
  recovered-report.txt \
  failed-download.txt
```

Keep the lab source files for GitHub.

---

## 21. Repository Structure

```text
12-s3-kms-encryption/
│
├── README.md
├── encrypted-report.txt
├── trust-policy.json
├── s3-only-policy.json
├── fixed-s3-kms-policy.json
└── assume-test-role.sh
```

### GitHub Security Notes

- Do not commit credentials or temporary session tokens.
- Review generated policy files for account-specific information.
- Replace real ARNs and identifiers with placeholders in public examples.
- Do not include real production encryption keys or sensitive customer data.
- The `assume-test-role.sh` helper must be reviewed before reuse in other AWS environments.

---

## 22. Lessons Learned

This lab demonstrates that S3 authorization and KMS authorization are separate.

An application role may have permission to retrieve an S3 object but still receive AccessDenied if it cannot use the customer-managed KMS key protecting that object.

The investigation involved verifying the application role, inspecting S3 encryption metadata, examining IAM and KMS policies, identifying the missing permission, and implementing a least-privilege correction.

The main lesson is to troubleshoot both S3 and KMS when working with encrypted cloud storage.

---

## 23. Skills Demonstrated

- Amazon S3 troubleshooting
- AWS KMS
- SSE-KMS encryption
- IAM role troubleshooting
- AWS STS AssumeRole
- KMS key policy analysis
- IAM permissions
- `kms:Decrypt`
- `kms:GenerateDataKey`
- `kms:ViaService` conditions
- Linux Bash
- AWS CLI v2
- Root cause analysis
- Secure remediation
- File integrity verification
- Incident documentation

## Final Outcome

| Item | Expected Result |
|---|---|
| Incident | INC-S3-012 |
| AWS Services | S3 + KMS |
| Error | GetObject AccessDenied |
| Root Cause | Missing kms:Decrypt |
| S3 Permissions | Correct |
| KMS Permissions | Corrected |
| Remediation | Least-privilege key access |
| Functional Verification | Successful encrypted object download |
| Security Verification | Block Public Access preserved |
| KMS Cleanup | Deletion scheduled for dedicated lab key |
| Expected Status | Resolved |

**Key Takeaway:** When an SSE-KMS-encrypted S3 object returns AccessDenied, inspect both S3 permissions and KMS key authorization. Fix the specific missing permission instead of granting broad administrator or wildcard access.
