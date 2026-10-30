# Lab 13 — Amazon S3 Lifecycle Rule Not Working

## Overview

This lab demonstrates how to troubleshoot an Amazon S3 Lifecycle rule that is enabled but does not apply to the intended objects.

The simulated production incident involves application logs that should automatically expire after 30 days.

However, the lifecycle configuration contains an incorrect object key prefix:

- **Configured prefix:** `log/`
- **Actual object prefix:** `logs/`

Because the prefixes do not match, the lifecycle rule does not select the intended log objects.

The goal is to reproduce the configuration error, inspect the rule, identify its root cause, apply a correction, and verify the intended object scope without waiting 30 days.

**Troubleshooting workflow:**

Baseline → Misconfiguration → Investigation → Root Cause Analysis → Remediation → Verification → Cleanup

---

## Lab Information

| Item | Details |
|---|---|
| AWS Service | Amazon S3 |
| Incident ID | INC-S3-013 |
| Difficulty | Intermediate |
| Feature | S3 Lifecycle Management |
| Incident | Lifecycle rule does not select intended objects |
| Intended Prefix | `logs/` |
| Incorrect Prefix | `log/` |
| Expiration | 30 days |
| Root Cause | Incorrect lifecycle prefix filter |
| Environment | Ubuntu Linux / WSL2 |
| Tools | AWS CLI v2, Bash |
| Remediation | Correct the lifecycle rule filter |
| Verification | Validate rule configuration and matching object keys |

---

## 1. Production Incident Scenario

### Incident Description

A Cloud Operations team stores application logs in Amazon S3.

The team wants these logs automatically deleted after 30 days to control storage costs.

The bucket contains the following objects:

```text
s3://LAB_BUCKET/
├── logs/
│   └── application.log
└── config/
    └── config.txt
```

The lifecycle rule is enabled, but its filter contains an incorrect prefix.

### Expected Behavior

Objects beginning with `logs/` become eligible for expiration after 30 days.

Objects under `config/` remain outside the lifecycle rule.

### Actual Behavior

The configured rule uses `log/`, which does not match `logs/application.log`.

Consequently, the intended log objects are not selected for expiration.

### Potential Business Impact

- Unnecessary S3 storage costs
- Retention policy violations
- Accumulation of old logs
- Incorrect assumptions about data deletion
- Operational compliance risks

### Investigation Objective

Determine why an enabled lifecycle rule does not apply to the intended objects.

---

## 2. Architecture

### Broken Configuration

```text
Application
     |
     v
Amazon S3 Bucket
     |
     +-- logs/application.log
     |
     +-- config/config.txt
     |
     v
S3 Lifecycle Rule
     |
     +-- Status: Enabled
     +-- Filter: log/
     +-- Expiration: 30 days
     |
     v
Prefix Does Not Match
     |
     v
Log Object Not Selected
```

### Corrected Configuration

```text
Amazon S3 Bucket
     |
     +-- logs/application.log
     |          |
     |          v
     |    Prefix Match: logs/
     |          |
     |          v
     |    Eligible After 30 Days
     |
     +-- config/config.txt
                |
                v
         Outside Rule Scope
```

**Important:** S3 Lifecycle is asynchronous. Correct configuration does not guarantee immediate object deletion.

---

## 3. Understanding Amazon S3 Lifecycle

S3 Lifecycle automates actions on objects based on their age and specified conditions.

Common lifecycle operations include:

- Expiring objects
- Transitioning objects to another storage class
- Managing noncurrent object versions
- Removing expired delete markers
- Aborting incomplete multipart uploads

### Important Lifecycle Configuration Fields

| Field | Purpose |
|---|---|
| `ID` | Unique rule identifier |
| `Status` | Enables or disables a rule |
| `Filter` | Determines which objects are selected |
| `Prefix` | Matches the beginning of an object key |
| `Expiration.Days` | Defines object age for expiration |
| `Transitions` | Defines storage-class changes |
| `NoncurrentVersionExpiration` | Manages eligible older object versions |

### Lifecycle Prefix Matching

An object key can be:

```text
logs/application.log
```

A filter using:

```text
logs/
```

matches that object.

A filter using:

```text
log/
```

does not match.

Lifecycle prefixes are case-sensitive.

### Eligibility vs Actual Deletion

When an object reaches its configured expiration age, it becomes eligible for expiration.

Amazon S3 performs the actual lifecycle operation asynchronously.

Therefore, an object may remain visible after its expiration threshold has been reached.

---

## 4. Prerequisites

Required:

- AWS account
- AWS CLI v2
- Ubuntu Linux / WSL2
- Bash
- Permission to create and manage an isolated S3 bucket
- Permission to manage bucket lifecycle configurations
- Git and GitHub

Use a dedicated test bucket.

Do not replace lifecycle configurations on existing production or shared buckets.

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

export BUCKET="cloud-lab13-${ACCOUNT_ID}"

export OBJECT_KEY="logs/application.log"
```

Verify:

```bash
echo "Region: $AWS_REGION"
echo "Bucket: $BUCKET"
echo "Object: $OBJECT_KEY"
```

---

## 5. Create the Working Environment

### Step 1 — Check Bucket Availability

```bash
aws s3api head-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

Only create a new bucket if the name is available.

Do not modify an existing bucket without verifying its ownership and purpose.

### Step 2 — Create the Bucket

```bash
aws s3api create-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

### Step 3 — Verify Bucket

```bash
aws s3api head-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

Keep S3 Block Public Access enabled.

### Step 4 — Create an Application Log

Create `application.log`:

```bash
cat > application.log <<'EOF'
2026-10-29 10:00:00 INFO Application started
2026-10-29 10:05:00 INFO Health check passed
2026-10-29 10:10:00 INFO Backup completed
EOF
```

### Step 5 — Upload the Log

```bash
aws s3api put-object \
  --bucket "$BUCKET" \
  --key "$OBJECT_KEY" \
  --body application.log \
  --region "$AWS_REGION"
```

### Step 6 — Create an Unrelated Configuration File

```bash
echo "Important application configuration" > config.txt
```

Upload:

```bash
aws s3api put-object \
  --bucket "$BUCKET" \
  --key "config/config.txt" \
  --body config.txt \
  --region "$AWS_REGION"
```

### Step 7 — Verify Objects

```bash
aws s3 ls "s3://$BUCKET/" \
  --recursive \
  --region "$AWS_REGION"
```

Expected keys:

```text
logs/application.log
config/config.txt
```

---

## 6. Establish the Baseline

Verify the log object:

```bash
aws s3api head-object \
  --bucket "$BUCKET" \
  --key "$OBJECT_KEY" \
  --region "$AWS_REGION"
```

Verify the unrelated configuration file:

```bash
aws s3api head-object \
  --bucket "$BUCKET" \
  --key "config/config.txt" \
  --region "$AWS_REGION"
```

### Inspect the Existing Lifecycle Configuration

```bash
aws s3api get-bucket-lifecycle-configuration \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

For a new bucket, the expected error is:

```text
NoSuchLifecycleConfiguration
```

This confirms the bucket has no existing lifecycle rules before the incident simulation.

---

## 7. Introduce the Lifecycle Misconfiguration

### Step 1 — Create a Broken Lifecycle Rule

Create `broken-lifecycle.json`:

```bash
cat > broken-lifecycle.json <<'EOF'
{
  "Rules": [
    {
      "ID": "ExpireApplicationLogsAfter30Days",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "log/"
      },
      "Expiration": {
        "Days": 30
      }
    }
  ]
}
EOF
```

### Step 2 — Examine the Error

The configuration uses:

```json
"Filter": {
  "Prefix": "log/"
}
```

However, the intended object key is:

```text
logs/application.log
```

The prefix is incorrect.

### Step 3 — Apply the Broken Rule

```bash
aws s3api put-bucket-lifecycle-configuration \
  --bucket "$BUCKET" \
  --lifecycle-configuration file://broken-lifecycle.json \
  --region "$AWS_REGION"
```

### Step 4 — Verify the Active Rule

```bash
aws s3api get-bucket-lifecycle-configuration \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

Expected configuration:

```json
{
  "Rules": [
    {
      "ID": "ExpireApplicationLogsAfter30Days",
      "Filter": {
        "Prefix": "log/"
      },
      "Status": "Enabled",
      "Expiration": {
        "Days": 30
      }
    }
  ]
}
```

Field order may differ.

**Observation:** AWS accepts the lifecycle configuration because it is syntactically valid, even though its filter does not select the intended objects.

---

## 8. Troubleshooting Investigation

### Check 1 — Verify the Bucket

```bash
aws s3api head-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

### Check 2 — List Object Keys

```bash
aws s3api list-objects-v2 \
  --bucket "$BUCKET" \
  --query 'Contents[].Key' \
  --output table \
  --region "$AWS_REGION"
```

Expected:

```text
config/config.txt
logs/application.log
```

### Check 3 — Inspect Lifecycle Rule Settings

```bash
aws s3api get-bucket-lifecycle-configuration \
  --bucket "$BUCKET" \
  --query 'Rules[].{ID:ID,Status:Status,Prefix:Filter.Prefix,Days:Expiration.Days}' \
  --output table \
  --region "$AWS_REGION"
```

Expected:

```text
ID: ExpireApplicationLogsAfter30Days
Status: Enabled
Prefix: log/
Days: 30
```

### Check 4 — Test the Incorrect Prefix

```bash
aws s3api list-objects-v2 \
  --bucket "$BUCKET" \
  --prefix "log/" \
  --query 'Contents[].Key' \
  --output json \
  --region "$AWS_REGION"
```

Expected:

```json
null
```

No objects match the incorrect prefix in this lab.

### Check 5 — Test the Intended Prefix

```bash
aws s3api list-objects-v2 \
  --bucket "$BUCKET" \
  --prefix "logs/" \
  --query 'Contents[].Key' \
  --output json \
  --region "$AWS_REGION"
```

Expected:

```json
[
  "logs/application.log"
]
```

### Investigation Findings

| Check | Result |
|---|---|
| S3 bucket exists | Yes |
| Application log exists | Yes |
| Lifecycle rule exists | Yes |
| Rule enabled | Yes |
| Expiration period | 30 days |
| Configured prefix | `log/` |
| Required prefix | `logs/` |
| Intended object selected | No |
| Root cause | Prefix mismatch |

---

## 9. Root Cause Analysis

### Root Cause

The S3 lifecycle rule contains an incorrect object key prefix.

The rule targets `log/`, while the application objects are stored under `logs/`.

Because S3 matches the beginning of the object key, the rule does not apply to the intended objects.

### Root Cause Flow

```text
Lifecycle Rule Created
         |
         v
Status: Enabled
         |
         v
Filter: log/
         |
         v
Object: logs/application.log
         |
         v
Prefix Comparison
         |
         v
No Match
         |
         v
Object Not Selected for Expiration
```

### Five Whys

1. **Why were the intended log objects not selected?** The lifecycle rule's prefix did not match them.
2. **Why didn't the prefix match?** The rule used `log/` instead of `logs/`.
3. **Why did S3 accept the rule?** The configuration was valid, although its filter did not cover the expected objects.
4. **Why wasn't this immediately obvious?** The lifecycle configuration was enabled, which alone does not verify its scope.
5. **How can this be prevented?** Validate rule filters against actual object keys before deployment.

---

## 10. Apply Remediation

### Step 1 — Create the Correct Lifecycle Configuration

Create `fixed-lifecycle.json`:

```bash
cat > fixed-lifecycle.json <<'EOF'
{
  "Rules": [
    {
      "ID": "ExpireApplicationLogsAfter30Days",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "logs/"
      },
      "Expiration": {
        "Days": 30
      }
    }
  ]
}
EOF
```

### Step 2 — Review the Correction

The corrected rule contains:

```json
"Filter": {
  "Prefix": "logs/"
}
```

The rule now targets objects whose keys begin with `logs/`.

### Step 3 — Apply the Corrected Rule

```bash
aws s3api put-bucket-lifecycle-configuration \
  --bucket "$BUCKET" \
  --lifecycle-configuration file://fixed-lifecycle.json \
  --region "$AWS_REGION"
```

### Step 4 — Verify the Configuration

```bash
aws s3api get-bucket-lifecycle-configuration \
  --bucket "$BUCKET" \
  --query 'Rules[].{ID:ID,Status:Status,Prefix:Filter.Prefix,Days:Expiration.Days}' \
  --output table \
  --region "$AWS_REGION"
```

Expected:

```text
ID: ExpireApplicationLogsAfter30Days
Status: Enabled
Prefix: logs/
Days: 30
```

---

## 11. Verify the Remediation

### Test 1 — List Matching Objects

```bash
aws s3api list-objects-v2 \
  --bucket "$BUCKET" \
  --prefix "logs/" \
  --query 'Contents[].Key' \
  --output json \
  --region "$AWS_REGION"
```

Expected:

```json
[
  "logs/application.log"
]
```

### Test 2 — Verify Unrelated Objects Remain Outside the Rule

```bash
aws s3api list-objects-v2 \
  --bucket "$BUCKET" \
  --prefix "config/" \
  --query 'Contents[].Key' \
  --output json \
  --region "$AWS_REGION"
```

Expected:

```json
[
  "config/config.txt"
]
```

Because the lifecycle filter is `logs/`, the `config/` object is not selected by this rule.

### Test 3 — Verify Rule Status

```bash
aws s3api get-bucket-lifecycle-configuration \
  --bucket "$BUCKET" \
  --query 'Rules[].Status' \
  --output text \
  --region "$AWS_REGION"
```

Expected:

```text
Enabled
```

### Test 4 — Verify Expiration Setting

```bash
aws s3api get-bucket-lifecycle-configuration \
  --bucket "$BUCKET" \
  --query 'Rules[].Expiration.Days' \
  --output text \
  --region "$AWS_REGION"
```

Expected:

```text
30
```

### Test 5 — Inspect Object Metadata

```bash
aws s3api head-object \
  --bucket "$BUCKET" \
  --key "$OBJECT_KEY" \
  --query '{LastModified:LastModified,Expiration:Expiration}' \
  --region "$AWS_REGION"
```

Lifecycle expiration metadata may not appear immediately after a configuration change.

An absent expiration field by itself does not prove the rule is incorrect.

### Verification Summary

| Verification | Before Fix | After Fix |
|---|---|---|
| Lifecycle rule enabled | Yes | Yes |
| Configured prefix | `log/` | `logs/` |
| Log object matches | No | Yes |
| Configuration file excluded | Yes | Yes |
| Expiration setting | 30 days | 30 days |
| Rule configuration | Incorrect scope | Correct scope |
| Actual future deletion | Not observed | Not yet observed |

**Important:** We have verified the corrected rule configuration and object matching, not the completion of a future lifecycle expiration operation.

---

## 12. Why We Do Not Wait 30 Days

Amazon S3 Lifecycle evaluates objects and processes expiration or transition actions asynchronously.

Even after an object becomes eligible, actual deletion may occur later.

This lab therefore validates:

1. The intended objects exist.
2. The lifecycle rule exists.
3. The lifecycle rule is enabled.
4. The filter matches the intended prefix.
5. Unrelated objects remain outside the filter.
6. The expiration period is configured correctly.

For longer-running production investigations, S3 Inventory, lifecycle event notifications, and storage monitoring can provide additional evidence of actual lifecycle processing.

---

## 13. Production Engineering Considerations

### Troubleshooting Checklist

When an S3 lifecycle rule does not work as expected, inspect:

- Rule status
- Prefix filter
- Object tags
- Object-size filters
- Expiration or transition settings
- Object creation timestamps
- Bucket versioning status
- Current and noncurrent object versions
- Replication status
- S3 Object Lock restrictions
- Asynchronous processing delays

### Versioning Considerations

In a versioning-enabled bucket, lifecycle expiration of a current object generally creates a delete marker rather than immediately removing all historical versions.

Historical versions may require separate noncurrent-version lifecycle rules.

### Storage Transition Considerations

Lifecycle transitions have storage-class-specific requirements and limitations.

For example, AWS's default lifecycle transition behavior restricts transitions for small objects below 128 KB, subject to the documented configuration options.

### Safety Considerations

Lifecycle rules can affect both existing and newly uploaded objects.

Avoid broad filters that accidentally include:

- Production backups
- Configuration files
- Audit records
- Compliance evidence
- Long-term archives

Always review the object scope before applying lifecycle changes.

---

## 14. Prevention Strategies

### Use Infrastructure as Code

Manage lifecycle policies using Terraform or CloudFormation.

### Validate Prefixes

Compare filter prefixes against real S3 object keys.

### Use Pull Requests

Require review before changing retention and deletion policies.

### Monitor Lifecycle Activity

Use appropriate S3 monitoring, inventory, and event notifications.

### Test in a Sandbox

Validate lifecycle filters in a disposable bucket before applying them to production.

### Avoid Unnecessary Wildcards

Use exact prefixes or well-defined tag-based filters.

### Document Data Retention

Identify which objects should expire and which must be retained.

---

## 15. Related S3 Lifecycle Issues

| Problem | Possible Cause |
|---|---|
| Objects not expiring | Incorrect prefix |
| Objects not expiring | Disabled lifecycle rule |
| Objects not expiring | Tag mismatch |
| Objects not expiring | Object not yet eligible |
| Objects still visible | Asynchronous expiration delay |
| Old versions remain | Missing noncurrent-version expiration |
| Objects not transitioning | Storage-class transition restrictions |
| Lifecycle does not select objects | Incorrect filter conditions |
| Unexpected object deletion | Overly broad lifecycle rule |

---

## 16. Interview Questions and Answers

### Q1. What is Amazon S3 Lifecycle?

S3 Lifecycle automates actions such as object expiration, storage-class transitions, and management of older object versions.

### Q2. Why might an enabled lifecycle rule not affect an object?

The rule may have an incorrect prefix, tag, size filter, or expiration setting.

### Q3. Are lifecycle prefixes case-sensitive?

Yes. The filter must match the beginning of the object's key.

### Q4. What is the difference between `log/` and `logs/`?

They are different prefixes. An object beginning with `logs/` does not match `log/`.

### Q5. Does S3 delete an object immediately when it becomes eligible?

Not necessarily. Lifecycle processing is asynchronous.

### Q6. Does an expiration rule automatically delete all previous versions?

No. Versioned buckets require special consideration for noncurrent versions and delete markers.

### Q7. Can a lifecycle rule affect existing objects?

Yes. A new lifecycle rule can apply to existing objects that match its conditions.

### Q8. How can you verify a lifecycle rule's filter?

Inspect the bucket lifecycle configuration and compare the filter with actual object keys, tags, and other conditions.

### Q9. How do you prevent accidental lifecycle deletions?

Use narrowly scoped rules, infrastructure as code, reviews, and appropriate testing.

### Q10. How would you explain this incident in an interview?

> An S3 lifecycle rule was enabled but did not select the expected application logs. I inspected the rule configuration and compared its prefix with the actual object keys. The rule used log/ while the objects were stored under logs/. I corrected the prefix, verified the rule was enabled, confirmed the expected objects matched, and checked that unrelated configuration files remained outside the rule's scope. I also accounted for asynchronous lifecycle processing rather than assuming the object should immediately disappear.

---

## 17. Cleanup

**Warning:** Only remove resources created for this dedicated Lab 13 exercise.

### Step 1 — Verify AWS Identity

```bash
aws sts get-caller-identity

echo "$BUCKET"
```

### Step 2 — Remove Lifecycle Configuration

```bash
aws s3api delete-bucket-lifecycle \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

### Step 3 — Verify Lifecycle Removal

```bash
aws s3api get-bucket-lifecycle-configuration \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

Expected:

```text
NoSuchLifecycleConfiguration
```

### Step 4 — Inspect Bucket Contents

```bash
aws s3 ls "s3://$BUCKET/" \
  --recursive \
  --region "$AWS_REGION"
```

Confirm the only objects are the two lab files.

### Step 5 — Delete Application Log

```bash
aws s3api delete-object \
  --bucket "$BUCKET" \
  --key "logs/application.log" \
  --region "$AWS_REGION"
```

### Step 6 — Delete Configuration File

```bash
aws s3api delete-object \
  --bucket "$BUCKET" \
  --key "config/config.txt" \
  --region "$AWS_REGION"
```

### Step 7 — Delete Empty Bucket

```bash
aws s3api delete-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

These cleanup commands assume bucket versioning was not enabled.

### Step 8 — Remove Debug Logs

```bash
rm -f lifecycle-debug.log
```

Keep the sample files and lifecycle configuration examples for GitHub.

---

## 18. Repository Structure

```text
13-s3-lifecycle-failure/
│
├── README.md
├── application.log
├── config.txt
├── broken-lifecycle.json
└── fixed-lifecycle.json
```

The repository includes the broken and corrected configurations needed to reproduce the incident.

Do not commit AWS credentials, sensitive logs, or unsanitized debug output.

---

## 19. Lessons Learned

This lab demonstrated that an S3 lifecycle rule can be enabled and syntactically valid while still failing to select its intended objects.

The investigation involved inspecting object keys, reviewing the lifecycle configuration, comparing prefixes, and identifying the mismatch.

After correcting the prefix from `log/` to `logs/`, the intended application log matched the lifecycle filter while the unrelated configuration file remained excluded.

The most important lesson is to verify lifecycle rule scope instead of assuming a rule works simply because its status is enabled.

---

## 20. Skills Demonstrated

- Amazon S3 Lifecycle Management
- AWS CLI v2
- Linux Bash
- Object key prefix troubleshooting
- Lifecycle configuration inspection
- Lifecycle expiration rules
- Root cause analysis
- Cloud storage retention management
- Safe remediation
- Verification of rule scope
- S3 data protection
- Production incident documentation

## Final Outcome

| Item | Expected Result |
|---|---|
| Incident | INC-S3-013 |
| AWS Service | Amazon S3 |
| Problem | Lifecycle rule not selecting logs |
| Root Cause | Incorrect prefix |
| Broken Filter | `log/` |
| Correct Filter | `logs/` |
| Expiration | 30 days |
| Remediation | Correct filter |
| Verification | Intended objects match |
| Actual Future Expiration | Not tested |
| Expected Lab Status | Configuration resolved |

**Key Takeaway:** Always verify the rule status, filter configuration, and actual object keys when troubleshooting S3 Lifecycle. Correct matching makes the objects eligible for the configured lifecycle action, while actual execution happens asynchronously.
