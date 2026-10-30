# Lab 15 — Amazon S3 Cross-Region Replication Failure

## Overview

This hands-on lab demonstrates how to troubleshoot an Amazon S3 Cross-Region Replication (CRR) failure caused by missing IAM permissions.

The simulated production incident involves two private S3 buckets located in different AWS Regions:

- **Source bucket:** `us-east-1` (Northern Virginia)
- **Destination bucket:** `us-east-2` (Ohio)

An application uploads files to the source bucket, but the disaster recovery bucket does not receive the expected replicas.

The replication IAM role can read source object versions but lacks `s3:ReplicateObject` permission for the destination bucket.

The goal is to reproduce the failure, investigate the replication configuration and IAM permissions, apply least-privilege remediation, verify successful replication, and safely clean up both versioned buckets.

**Troubleshooting workflow:**

Baseline → Introduce Failure → Investigate → Root Cause Analysis → Remediate → Verify → Cleanup

---

## Lab Information

| Item | Details |
|---|---|
| AWS Services | Amazon S3 + AWS IAM |
| Incident ID | INC-S3-015 |
| Difficulty | Advanced |
| Feature | S3 Cross-Region Replication |
| Source Region | `us-east-1` |
| Destination Region | `us-east-2` |
| Replication Rule | `Lab15ReplicateReports` |
| IAM Role | `Lab15S3ReplicationRole` |
| Expected Failure | ReplicationStatus: FAILED |
| Root Cause | Missing `s3:ReplicateObject` |
| Remediation | Grant destination replication permission |
| Environment | Ubuntu Linux / WSL2 |
| Tools | AWS CLI v2, Bash, Python 3 |
| Verification | `COMPLETED`, `REPLICA`, file integrity |

---

## 1. Production Incident Scenario

### Incident Description

A company stores important application reports in an Amazon S3 bucket located in Northern Virginia.

To support disaster recovery, the Cloud Engineering team configures S3 Cross-Region Replication to automatically copy new object versions to a destination bucket in Ohio.

Both buckets have versioning enabled, and the replication rule is configured.

However, newly uploaded reports are not being replicated.

### Reported Symptoms

```text
Source Bucket: us-east-1
Destination Bucket: us-east-2

Object Upload: SUCCESS
Replication Rule: ENABLED
Destination Object: MISSING
Replication Status: FAILED
```

The status may initially show `PENDING` while S3 processes the replication attempt.

### Expected Behavior

New object versions uploaded under `reports/` should automatically replicate from the source bucket to the destination bucket.

### Actual Behavior

The replication role lacks permission to write replicas to the destination.

Consequently, replication cannot complete.

### Potential Business Impact

- Disaster recovery data is incomplete.
- Applications may lack backup copies in another Region.
- Business continuity requirements may be affected.
- Recovery point objectives may not be met.
- Replication failures may remain unnoticed without monitoring.

### Investigation Objective

Identify the failed authorization step and restore replication without granting broad access to unrelated buckets.

---

## 2. Architecture

### Broken Architecture

```text
              Application
                   |
                   | PutObject
                   v
       Amazon S3 Source Bucket
                us-east-1
                   |
                   | Versioning Enabled
                   v
       reports/replication-report.txt
                   |
                   v
          Replication Rule
                   |
                   v
          Replication IAM Role
                   |
                   +-- Source Read: Allowed
                   |
                   +-- Destination Write: Missing
                   |
                   v
             Replication FAILED
                   |
                   X
       Amazon S3 Destination Bucket
                 us-east-2
```

### Corrected Architecture

```text
              Application
                   |
                   v
        Source S3 — us-east-1
                   |
                   v
            Object Version
                   |
                   v
          S3 Replication Rule
                   |
                   v
          Replication IAM Role
                   |
                   +-- GetReplicationConfiguration
                   +-- GetObjectVersionForReplication
                   +-- GetObjectVersionAcl
                   +-- GetObjectVersionTagging
                   +-- ReplicateObject
                   +-- ReplicateTags
                   |
                   v
        Destination S3 — us-east-2
                   |
                   v
            Replica Created
                   |
                   v
          Replication COMPLETED
```

---

## 3. Understanding S3 Cross-Region Replication

Amazon S3 Cross-Region Replication automatically copies eligible object versions from a source bucket to a destination bucket in another AWS Region.

CRR is commonly used for:

- Disaster recovery
- Business continuity
- Data residency requirements
- Regional backup copies
- Geographic data distribution

### Important Requirements

| Requirement | Explanation |
|---|---|
| Source versioning | Must be enabled |
| Destination versioning | Must be enabled |
| Replication rule | Must be configured |
| IAM role | Must be assumable by Amazon S3 |
| Source permissions | Allow reading eligible object versions |
| Destination permissions | Allow writing replicated objects |
| Region | Destination is in a different Region for CRR |
| Object scope | Must match the replication rule filter |

### Replication Status Values

| Status | Meaning |
|---|---|
| `PENDING` | Replication processing has not completed |
| `COMPLETED` | Source object version replicated successfully |
| `FAILED` | Replication attempt failed |
| `REPLICA` | Object version is a replica in the destination |

### Important Limitation

Correcting an IAM policy does not automatically recover every object version that previously reached `FAILED`.

For the remediation test, this lab uploads a new version.

In production, S3 Batch Replication can be used to replicate existing objects and eligible previously failed versions.

---

## 4. Prerequisites

Required:

- AWS account
- AWS CLI v2
- Ubuntu Linux / WSL2
- Bash
- Python 3
- S3 bucket-management permissions
- IAM role-management permissions
- `iam:PassRole` permission for configuring replication
- Git and GitHub

### Cost Warning

This lab uses two buckets in different Regions.

Potential costs include:

- S3 object storage
- Cross-Region data transfer
- Replication requests
- Object versions retained in both buckets

Use small sample objects and delete all test resources after finishing.

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
export SOURCE_REGION="us-east-1"
export DEST_REGION="us-east-2"

export ACCOUNT_ID=$(aws sts get-caller-identity \
  --query Account --output text)

export SOURCE_BUCKET="cloud-lab15-source-${ACCOUNT_ID}"
export DEST_BUCKET="cloud-lab15-dest-${ACCOUNT_ID}"

export ROLE_NAME="Lab15S3ReplicationRole"
export OBJECT_KEY="reports/replication-report.txt"
```

Verify:

```bash
echo "$SOURCE_BUCKET"
echo "$DEST_BUCKET"
echo "$SOURCE_REGION"
echo "$DEST_REGION"
echo "$ROLE_NAME"
```

---

## 5. Create the S3 Buckets

### Step 1 — Check Bucket Availability

```bash
aws s3api head-bucket \
  --bucket "$SOURCE_BUCKET" \
  --region "$SOURCE_REGION"
```

```bash
aws s3api head-bucket \
  --bucket "$DEST_BUCKET" \
  --region "$DEST_REGION"
```

Only create buckets if the names are available.

Never overwrite or reuse buckets containing unrelated data.

### Step 2 — Create Source Bucket

```bash
aws s3api create-bucket \
  --bucket "$SOURCE_BUCKET" \
  --region "$SOURCE_REGION"
```

### Step 3 — Create Destination Bucket

```bash
aws s3api create-bucket \
  --bucket "$DEST_BUCKET" \
  --create-bucket-configuration LocationConstraint=us-east-2 \
  --region "$DEST_REGION"
```

### Step 4 — Verify Source Region

```bash
aws s3api get-bucket-location \
  --bucket "$SOURCE_BUCKET" \
  --region "$SOURCE_REGION"
```

For `us-east-1`, the location constraint typically returns `null`.

### Step 5 — Verify Destination Region

```bash
aws s3api get-bucket-location \
  --bucket "$DEST_BUCKET" \
  --region "$DEST_REGION"
```

Expected:

```text
us-east-2
```

### Step 6 — Configure Block Public Access

```bash
aws s3api put-public-access-block \
  --bucket "$SOURCE_BUCKET" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
  --region "$SOURCE_REGION"
```

```bash
aws s3api put-public-access-block \
  --bucket "$DEST_BUCKET" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
  --region "$DEST_REGION"
```

Verify both bucket settings with `get-public-access-block`.

---

## 6. Enable S3 Versioning

Both buckets must have versioning enabled.

### Step 1 — Enable Source Versioning

```bash
aws s3api put-bucket-versioning \
  --bucket "$SOURCE_BUCKET" \
  --versioning-configuration Status=Enabled \
  --region "$SOURCE_REGION"
```

### Step 2 — Enable Destination Versioning

```bash
aws s3api put-bucket-versioning \
  --bucket "$DEST_BUCKET" \
  --versioning-configuration Status=Enabled \
  --region "$DEST_REGION"
```

### Step 3 — Verify Source

```bash
aws s3api get-bucket-versioning \
  --bucket "$SOURCE_BUCKET" \
  --region "$SOURCE_REGION"
```

### Step 4 — Verify Destination

```bash
aws s3api get-bucket-versioning \
  --bucket "$DEST_BUCKET" \
  --region "$DEST_REGION"
```

Both should return:

```json
{
  "Status": "Enabled"
}
```

**Note:** AWS recommends allowing propagation time after initially enabling versioning, potentially up to 15 minutes.

---

## 7. Create the Replication IAM Role

### Step 1 — Create Trust Policy

Create `replication-trust-policy.json`:

```bash
cat > replication-trust-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
```

### Step 2 — Create IAM Role

```bash
aws iam create-role \
  --role-name "$ROLE_NAME" \
  --assume-role-policy-document file://replication-trust-policy.json
```

### Step 3 — Get Role ARN

```bash
export ROLE_ARN=$(aws iam get-role \
  --role-name "$ROLE_NAME" \
  --query Role.Arn \
  --output text)
```

Verify:

```bash
echo "$ROLE_ARN"
```

The S3 service can use this role only when appropriate permissions are also attached.

---

## 8. Introduce the Broken IAM Policy

### Step 1 — Create Broken Policy

Create `broken-replication-policy.json`:

```bash
cat > broken-replication-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadReplicationConfiguration",
      "Effect": "Allow",
      "Action": [
        "s3:GetReplicationConfiguration",
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::$SOURCE_BUCKET"
    },
    {
      "Sid": "ReadSourceObjectVersions",
      "Effect": "Allow",
      "Action": [
        "s3:GetObjectVersionForReplication",
        "s3:GetObjectVersionAcl",
        "s3:GetObjectVersionTagging"
      ],
      "Resource": "arn:aws:s3:::$SOURCE_BUCKET/*"
    }
  ]
}
EOF
```

### Step 2 — Identify the Error

The policy allows the replication role to read source objects and configuration.

However, it does not include:

```text
s3:ReplicateObject
```

Consequently, the role is missing a required destination-write permission.

### Step 3 — Attach Broken Policy

```bash
aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name Lab15ReplicationPolicy \
  --policy-document file://broken-replication-policy.json
```

### Step 4 — Verify Policy

```bash
aws iam get-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name Lab15ReplicationPolicy
```

---

## 9. Configure Cross-Region Replication

### Step 1 — Create Replication Configuration

Create `replication-config.json`:

```bash
cat > replication-config.json <<EOF
{
  "Role": "$ROLE_ARN",
  "Rules": [
    {
      "ID": "Lab15ReplicateReports",
      "Priority": 1,
      "Status": "Enabled",
      "Filter": {
        "Prefix": "reports/"
      },
      "DeleteMarkerReplication": {
        "Status": "Disabled"
      },
      "Destination": {
        "Bucket": "arn:aws:s3:::$DEST_BUCKET"
      }
    }
  ]
}
EOF
```

### Step 2 — Apply the Replication Rule

```bash
aws s3api put-bucket-replication \
  --bucket "$SOURCE_BUCKET" \
  --replication-configuration file://replication-config.json \
  --region "$SOURCE_REGION"
```

### Step 3 — Verify Configuration

```bash
aws s3api get-bucket-replication \
  --bucket "$SOURCE_BUCKET" \
  --region "$SOURCE_REGION"
```

Expected configuration:

```text
Rule: Lab15ReplicateReports
Status: Enabled
Prefix: reports/
Source: us-east-1
Destination: us-east-2
```

### Important Detail

The replication rule is valid, but the IAM role cannot perform the destination replication operation.

This reproduces a production-style permissions failure.

---

## 10. Reproduce the Replication Failure

### Step 1 — Create Sample Report

Create `replication-report.txt`:

```bash
cat > replication-report.txt <<'EOF'
Cloud Engineering Lab 15

Application: Disaster Recovery
Replication: Cross-Region
Status: Original Version
EOF
```

### Step 2 — Upload to Source

```bash
aws s3api put-object \
  --bucket "$SOURCE_BUCKET" \
  --key "$OBJECT_KEY" \
  --body replication-report.txt \
  --region "$SOURCE_REGION"
```

### Step 3 — Verify Source Object

```bash
aws s3api head-object \
  --bucket "$SOURCE_BUCKET" \
  --key "$OBJECT_KEY" \
  --region "$SOURCE_REGION"
```

### Step 4 — Inspect Replication Status

```bash
aws s3api head-object \
  --bucket "$SOURCE_BUCKET" \
  --key "$OBJECT_KEY" \
  --query '{ReplicationStatus:ReplicationStatus,VersionId:VersionId}' \
  --region "$SOURCE_REGION"
```

Possible initial state:

```text
ReplicationStatus: PENDING
```

Expected state after the unsuccessful attempt has been processed:

```text
ReplicationStatus: FAILED
```

### Step 5 — Check Destination

```bash
aws s3api list-objects-v2 \
  --bucket "$DEST_BUCKET" \
  --prefix "reports/" \
  --query 'Contents[].Key' \
  --output json \
  --region "$DEST_REGION"
```

Expected during the simulated failure:

```json
null
```

**Important:** Replication happens asynchronously. A missing replica immediately after upload is not enough to establish permanent failure.

Use the source object's replication status and policy evidence to diagnose the issue.

---

## 11. Troubleshooting Investigation

### Check 1 — Verify Both Buckets

```bash
aws s3api head-bucket \
  --bucket "$SOURCE_BUCKET" \
  --region "$SOURCE_REGION"
```

```bash
aws s3api head-bucket \
  --bucket "$DEST_BUCKET" \
  --region "$DEST_REGION"
```

### Check 2 — Verify Versioning

```bash
aws s3api get-bucket-versioning \
  --bucket "$SOURCE_BUCKET" \
  --region "$SOURCE_REGION"
```

```bash
aws s3api get-bucket-versioning \
  --bucket "$DEST_BUCKET" \
  --region "$DEST_REGION"
```

Both should be enabled.

### Check 3 — Inspect Replication Rule

```bash
aws s3api get-bucket-replication \
  --bucket "$SOURCE_BUCKET" \
  --region "$SOURCE_REGION"
```

Confirm:

- Rule enabled
- Correct prefix
- Correct destination
- Correct role

### Check 4 — Inspect IAM Role Policy

```bash
aws iam get-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name Lab15ReplicationPolicy
```

Identify the missing permission:

```text
s3:ReplicateObject
```

### Check 5 — Check Object Replication Status

```bash
aws s3api head-object \
  --bucket "$SOURCE_BUCKET" \
  --key "$OBJECT_KEY" \
  --query '{Status:ReplicationStatus,Version:VersionId}' \
  --region "$SOURCE_REGION"
```

### Investigation Summary

| Check | Finding |
|---|---|
| Source bucket exists | Yes |
| Destination bucket exists | Yes |
| Both buckets versioned | Yes |
| Replication rule enabled | Yes |
| Prefix matches | Yes |
| Replication IAM role exists | Yes |
| Source permissions | Allowed |
| Destination replication permission | Missing |
| Replication result | FAILED expected |
| Root cause | Missing destination write permission |

---

## 12. Root Cause Analysis

### Root Cause

The replication IAM role lacks `s3:ReplicateObject` permission on the destination S3 bucket.

Although it can read eligible source versions, it cannot write their replicas.

### Root Cause Flow

```text
Source Object Uploaded
          |
          v
Replication Rule Matches
          |
          v
S3 Assumes Replication Role
          |
          v
Read Source Object Version
          |
          v
Attempt Destination Write
          |
          v
s3:ReplicateObject Missing
          |
          v
Authorization Denied
          |
          v
Replication FAILED
```

### Five Whys

1. **Why did replication fail?** S3 could not create the destination replica.
2. **Why could it not create the replica?** The replication role lacked destination-write permission.
3. **Why was the role insufficient?** Its IAM policy contained only source-read permissions.
4. **Why did the replication rule still exist?** The configuration was accepted even though the role was missing required effective permissions.
5. **How can this be prevented?** Validate source and destination permissions before enabling replication and monitor replication failures.

---

## 13. Apply Least-Privilege Remediation

### Step 1 — Create Corrected Policy

Create `fixed-replication-policy.json`:

```bash
cat > fixed-replication-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadReplicationConfiguration",
      "Effect": "Allow",
      "Action": [
        "s3:GetReplicationConfiguration",
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::$SOURCE_BUCKET"
    },
    {
      "Sid": "ReadSourceVersions",
      "Effect": "Allow",
      "Action": [
        "s3:GetObjectVersionForReplication",
        "s3:GetObjectVersionAcl",
        "s3:GetObjectVersionTagging"
      ],
      "Resource": "arn:aws:s3:::$SOURCE_BUCKET/reports/*"
    },
    {
      "Sid": "WriteDestinationReplicas",
      "Effect": "Allow",
      "Action": [
        "s3:ReplicateObject",
        "s3:ReplicateTags"
      ],
      "Resource": "arn:aws:s3:::$DEST_BUCKET/reports/*"
    }
  ]
}
EOF
```

### Step 2 — Understand the Permissions

| Permission | Purpose |
|---|---|
| `s3:GetReplicationConfiguration` | Read source replication configuration |
| `s3:ListBucket` | List source bucket objects |
| `s3:GetObjectVersionForReplication` | Read source object versions |
| `s3:GetObjectVersionAcl` | Read source object ACL metadata |
| `s3:GetObjectVersionTagging` | Read source version tags |
| `s3:ReplicateObject` | Write replicated object versions |
| `s3:ReplicateTags` | Replicate associated object tags |

Delete-marker replication is disabled in this lab, so `s3:ReplicateDelete` is not needed for this exercise.

### Step 3 — Apply Fixed Policy

```bash
aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name Lab15ReplicationPolicy \
  --policy-document file://fixed-replication-policy.json
```

### Step 4 — Verify Policy

```bash
aws iam get-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name Lab15ReplicationPolicy
```

Confirm `s3:ReplicateObject` is allowed on the intended destination object ARN.

### Security Improvement

The corrected policy is restricted to the two dedicated buckets and the `reports/` object prefix.

It does not grant full S3 administrative access.

---

## 14. Verify Successful Replication

### Step 1 — Upload a New Version

Update the report:

```bash
cat > replication-report.txt <<'EOF'
Cloud Engineering Lab 15

Application: Disaster Recovery
Replication: Cross-Region
Status: Remediation Successful
Version: 2
EOF
```

Upload:

```bash
aws s3api put-object \
  --bucket "$SOURCE_BUCKET" \
  --key "$OBJECT_KEY" \
  --body replication-report.txt \
  --region "$SOURCE_REGION"
```

Because versioning is enabled, S3 creates a new source version.

### Step 2 — Inspect New Version Status

```bash
aws s3api head-object \
  --bucket "$SOURCE_BUCKET" \
  --key "$OBJECT_KEY" \
  --query '{Status:ReplicationStatus,Version:VersionId}' \
  --region "$SOURCE_REGION"
```

Initially:

```text
Status: PENDING
```

After successful replication:

```text
Status: COMPLETED
```

### Step 3 — Poll for Completion

```bash
for i in {1..12}; do
  STATUS=$(aws s3api head-object \
    --bucket "$SOURCE_BUCKET" \
    --key "$OBJECT_KEY" \
    --query ReplicationStatus \
    --output text \
    --region "$SOURCE_REGION")

  echo "Check $i: $STATUS"

  if [[ "$STATUS" == "COMPLETED" ]]; then
    echo "Replication completed."
    break
  fi

  if [[ "$STATUS" == "FAILED" ]]; then
    echo "Replication failed. Investigate further."
    break
  fi

  sleep 10
done
```

This example checks at intervals. It does not guarantee replication will finish within the polling window.

### Step 4 — Verify Destination Object

```bash
aws s3api head-object \
  --bucket "$DEST_BUCKET" \
  --key "$OBJECT_KEY" \
  --query '{Status:ReplicationStatus,Version:VersionId,Size:ContentLength}' \
  --region "$DEST_REGION"
```

Expected:

```text
Status: REPLICA
```

### Step 5 — Download the Replica

```bash
aws s3api get-object \
  --bucket "$DEST_BUCKET" \
  --key "$OBJECT_KEY" \
  destination-report.txt \
  --region "$DEST_REGION"
```

### Step 6 — Compare Contents

```bash
diff replication-report.txt destination-report.txt
```

No output means the files match.

### Verification Summary

| Check | Before Fix | After Fix |
|---|---|---|
| Source bucket versioning | Enabled | Enabled |
| Destination bucket versioning | Enabled | Enabled |
| Replication rule | Enabled | Enabled |
| Source read access | Allowed | Allowed |
| Destination write access | Missing | Allowed |
| Source status | FAILED expected | COMPLETED |
| Destination replica | Missing | Present |
| Destination status | — | REPLICA |
| File integrity | — | Verified |
| Public access | Blocked | Blocked |

---

## 15. Handling Previously Failed Versions

Correcting the IAM role does not automatically replicate a version that has already failed.

Creating a new version demonstrates that future replication works, but the original version may remain unreplicated.

For production recovery, evaluate **S3 Batch Replication** to process existing or previously failed versions.

### Production Recovery Workflow

1. Identify affected source versions.
2. Determine why replication failed.
3. Correct the underlying issue.
4. Verify replication of newly created versions.
5. Identify historical versions requiring recovery.
6. Configure S3 Batch Replication where appropriate.
7. Monitor the batch job.
8. Confirm expected replicas exist.
9. Document remaining exceptions.

---

## 16. Production Engineering Considerations

### Common Reasons Replication Fails

- Missing `s3:ReplicateObject`
- Missing source-version read permissions
- Incorrect replication IAM trust policy
- Missing destination bucket permissions
- Versioning disabled or suspended
- Incorrect replication prefix
- Destination bucket not available
- Missing KMS permissions for SSE-KMS objects
- Conflicting explicit deny statements
- Incorrect ownership or replication configuration
- Object not eligible for automatic replication

### SSE-KMS Replication Considerations

Replicating objects encrypted with SSE-KMS requires additional replication configuration and KMS authorization.

This lab uses S3's default SSE-S3 encryption to focus on IAM destination permissions.

### Monitoring

Production environments should consider:

- S3 Replication metrics
- Replication failure notifications
- CloudWatch alarms
- S3 Inventory
- S3 Batch Replication
- CloudTrail auditing
- Disaster recovery testing

### Security Best Practices

- Apply least-privilege replication permissions.
- Use dedicated replication roles.
- Keep both buckets private.
- Enable versioning on both buckets.
- Restrict destination access.
- Monitor replication failures.
- Verify replica integrity.
- Review IAM changes through pull requests.
- Test replication recovery procedures.

---

## 17. Related Replication Errors

| Symptom | Possible Cause |
|---|---|
| `PENDING` | Replication is processing |
| `FAILED` | Replication attempt failed |
| No destination object | Missing permissions or ineligible object |
| Replication role access denied | Incorrect trust or IAM policy |
| KMS-related replication failure | Missing key permissions |
| Old objects not replicated | They predate the rule or were previously failed |
| Delete markers not replicated | Delete-marker replication disabled |
| Destination bucket error | Incorrect destination or policy |

---

## 18. Interview Questions and Answers

### Q1. What is S3 Cross-Region Replication?

S3 Cross-Region Replication automatically copies eligible object versions to a destination bucket in another AWS Region.

### Q2. Is versioning required?

Yes. Versioning must be enabled on both the source and destination buckets.

### Q3. What permission is required to write replicas?

`s3:ReplicateObject`.

### Q4. What permission allows S3 to read source versions?

`s3:GetObjectVersionForReplication`.

### Q5. What does PENDING mean?

S3 has not completed replication processing for the object version.

### Q6. What does FAILED mean?

The replication attempt did not succeed.

### Q7. What does REPLICA mean?

The object version is a replica stored in the destination bucket.

### Q8. Will fixing IAM permissions automatically retry failed versions?

Not necessarily. Previously failed versions may require S3 Batch Replication.

### Q9. Can SSE-KMS encrypted objects be replicated?

Yes, but they require additional replication configuration and suitable KMS permissions.

### Q10. How would you explain this incident in an interview?

> Cross-Region Replication was configured between S3 buckets in us-east-1 and us-east-2, but source objects were not appearing in the destination. I verified versioning, replication rules, object status, and the replication IAM role. I identified that the role could read source object versions but lacked s3:ReplicateObject on the destination. I corrected the IAM policy, uploaded a new version, verified its source replication status became COMPLETED, confirmed the destination reported REPLICA, and checked that the downloaded contents matched the original.

---

## 19. Cleanup

**Warning:** Both buckets are versioning-enabled. Every object version and delete marker must be removed before deleting the buckets.

These instructions are intended only for the isolated Lab 15 resources.

### Step 1 — Verify AWS Identity

```bash
aws sts get-caller-identity

echo "$SOURCE_BUCKET"
echo "$DEST_BUCKET"
echo "$ROLE_NAME"
```

### Step 2 — Remove Replication Configuration

```bash
aws s3api delete-bucket-replication \
  --bucket "$SOURCE_BUCKET" \
  --region "$SOURCE_REGION"
```

Verify:

```bash
aws s3api get-bucket-replication \
  --bucket "$SOURCE_BUCKET" \
  --region "$SOURCE_REGION"
```

Expected: `ReplicationConfigurationNotFoundError`.

### Step 3 — Remove IAM Role Policy

```bash
aws iam delete-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name Lab15ReplicationPolicy
```

### Step 4 — Delete IAM Role

```bash
aws iam delete-role \
  --role-name "$ROLE_NAME"
```

### Step 5 — Inspect Object Versions

Source:

```bash
aws s3api list-object-versions \
  --bucket "$SOURCE_BUCKET" \
  --region "$SOURCE_REGION"
```

Destination:

```bash
aws s3api list-object-versions \
  --bucket "$DEST_BUCKET" \
  --region "$DEST_REGION"
```

Confirm both buckets contain only Lab 15 test versions.

### Step 6 — Create Version Cleanup Helper

Create `cleanup-versions.sh`:

```bash
cat > cleanup-versions.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 BUCKET REGION"
  exit 1
fi

BUCKET="$1"
REGION="$2"
KEY="reports/replication-report.txt"

if [[ "$BUCKET" != cloud-lab15-* ]]; then
  echo "Unexpected bucket name. Aborting."
  exit 1
fi

echo "Bucket: $BUCKET"
echo "Region: $REGION"
echo "Object: $KEY"

aws s3api list-object-versions \
  --bucket "$BUCKET" \
  --prefix "$KEY" \
  --region "$REGION" \
  --output json |
python3 -c '
import json
import sys

data = json.load(sys.stdin)
target = "reports/replication-report.txt"

for collection in ("Versions", "DeleteMarkers"):
    for item in data.get(collection, []):
        if item["Key"] == target:
            print(item["VersionId"])
' |
while IFS= read -r VERSION_ID; do
  [[ -z "$VERSION_ID" ]] && continue

  aws s3api delete-object \
    --bucket "$BUCKET" \
    --key "$KEY" \
    --version-id "$VERSION_ID" \
    --region "$REGION"
done
EOF
```

Make executable:

```bash
chmod +x cleanup-versions.sh
```

**Safety:** This helper permanently deletes versions belonging to the specified object. Verify ownership, account, bucket, and contents before running it.

It is intended for the small, isolated lab dataset.

### Step 7 — Clean Source Versions

```bash
./cleanup-versions.sh \
  "$SOURCE_BUCKET" \
  "$SOURCE_REGION"
```

### Step 8 — Clean Destination Versions

```bash
./cleanup-versions.sh \
  "$DEST_BUCKET" \
  "$DEST_REGION"
```

### Step 9 — Verify Both Buckets Are Empty

```bash
aws s3api list-object-versions \
  --bucket "$SOURCE_BUCKET" \
  --region "$SOURCE_REGION"
```

```bash
aws s3api list-object-versions \
  --bucket "$DEST_BUCKET" \
  --region "$DEST_REGION"
```

Confirm no versions or delete markers remain.

Also check for unexpected object keys before deleting either bucket.

### Step 10 — Delete Source Bucket

```bash
aws s3api delete-bucket \
  --bucket "$SOURCE_BUCKET" \
  --region "$SOURCE_REGION"
```

### Step 11 — Delete Destination Bucket

```bash
aws s3api delete-bucket \
  --bucket "$DEST_BUCKET" \
  --region "$DEST_REGION"
```

### Step 12 — Remove Temporary Downloads

```bash
rm -f destination-report.txt
```

Keep the lab example files for your GitHub repository.

---

## 20. Repository Structure

```text
15-s3-cross-region-replication/
│
├── README.md
├── replication-report.txt
├── replication-trust-policy.json
├── broken-replication-policy.json
├── fixed-replication-policy.json
├── replication-config.json
└── cleanup-versions.sh
```

### GitHub Security Notes

- Do not commit AWS credentials or temporary tokens.
- Review IAM policies before publishing.
- Replace account-specific ARNs with placeholders when appropriate.
- Do not commit production bucket names or sensitive data.
- Keep only educational sample content.
- Review destructive cleanup scripts carefully before reuse.

---

## 21. Lessons Learned

This lab demonstrated how Amazon S3 Cross-Region Replication can fail even when versioning and replication rules are correctly configured.

The failure was caused by missing destination permissions in the replication IAM role.

The investigation involved checking bucket versioning, replication configuration, source object status, and IAM policies.

After correcting the role's destination-write permissions, a newly uploaded object version could be replicated successfully.

The lab also demonstrated why historical failed versions require separate recovery consideration and why versioned buckets need careful cleanup.

The main lesson is that successful S3 replication requires correct configuration and authorization across both the source and destination.

---

## 22. Skills Demonstrated

- Amazon S3 Cross-Region Replication
- Disaster recovery architecture
- AWS IAM replication roles
- S3 versioning
- Cross-Region storage
- `s3:ReplicateObject`
- `s3:GetObjectVersionForReplication`
- Replication status troubleshooting
- AWS CLI v2
- Linux Bash
- Python 3
- Least-privilege remediation
- Data integrity verification
- Versioned bucket cleanup
- Root cause analysis
- Production incident documentation

## Final Outcome

| Item | Expected Result |
|---|---|
| Incident | INC-S3-015 |
| AWS Services | Amazon S3 + IAM |
| Feature | Cross-Region Replication |
| Source | us-east-1 |
| Destination | us-east-2 |
| Root Cause | Missing `s3:ReplicateObject` |
| Remediation | Correct destination IAM permissions |
| Source Verification | COMPLETED |
| Destination Verification | REPLICA |
| File Integrity | Verified |
| Historical Failed Versions | May need Batch Replication |
| Public Access | Blocked |
| Expected Lab Status | Resolved |

**Key Takeaway:** When S3 Cross-Region Replication fails, verify bucket versioning, replication rules, IAM role trust, source-read permissions, and destination-write permissions. A configured replication rule is not proof that replication is succeeding.
