# Lab 02 — Amazon S3 Object Not Found (`NoSuchKey`)

## Overview

This lab demonstrates how to troubleshoot an Amazon S3 `NoSuchKey` error when an application attempts to download an object that does not exist at the requested key.

In this scenario, the S3 bucket and the actual object exist, but the application requests an incorrect object key due to a case-sensitive filename mismatch.

The lab follows a production-inspired troubleshooting workflow:

**Reproduce → Investigate → Identify Root Cause → Remediate → Verify → Document**

## Lab Information

| Item | Details |
|---|---|
| AWS Service | Amazon S3 |
| Difficulty | Beginner |
| Error | `NoSuchKey` |
| Tools | AWS CLI v2, Ubuntu Linux, Bash |
| Operating Environment | Ubuntu WSL2 |
| Root Cause | Incorrect object key capitalization |
| Resolution | Correct the requested S3 object key |

---

## 1. Incident Scenario

**Incident ID:** INC-S3-002

**Reported Problem:**

An application that retrieves files from Amazon S3 fails to download a report.

The application returns:

```text
An error occurred (NoSuchKey) when calling the GetObject operation:
The specified key does not exist.
```

The application support team confirms that the S3 bucket exists and that the report was previously uploaded successfully.

As the Cloud Engineer, the responsibility is to determine why the request fails, identify the root cause, restore the download functionality, and verify the solution.

### Expected Behavior

The application should successfully retrieve:

```text
s3://BUCKET_NAME/reports/data.txt
```

### Actual Behavior

The application requests:

```text
s3://BUCKET_NAME/reports/Data.txt
```

Amazon S3 treats these as different object keys.

Consequently, the request fails.

### Business Impact

The affected application's report retrieval operation is unavailable.

In a real production environment, this could prevent users or downstream applications from accessing required data.

---

## 2. Architecture

### Working Architecture

```text
Application / AWS CLI
         |
         | GetObject
         v
     Amazon S3
         |
         v
    S3 Bucket
         |
         v
  reports/data.txt
         |
         v
   HTTP 200 Success
```

### Broken Architecture

```text
Application / AWS CLI
         |
         | GetObject
         v
     Amazon S3
         |
         v
    S3 Bucket
         |
         v
  reports/Data.txt
         |
         X
     NoSuchKey
```

### Key Difference

```text
Actual key:     reports/data.txt
Requested key:  reports/Data.txt
```

S3 object keys are case-sensitive.

---

## 3. Prerequisites

The following tools and permissions are required:

- AWS account
- AWS CLI v2
- Ubuntu Linux / WSL2
- Bash terminal
- Permission to create and delete S3 test buckets
- Permission to upload, list, and download S3 objects

### Verify AWS CLI

```bash
aws --version
```

### Verify AWS Identity

```bash
aws sts get-caller-identity
```

This verifies which AWS account and identity are being used.

### Verify AWS Region

```bash
aws configure get region
```

The lab uses `us-east-1`.

---

## 4. Configure the Environment

### Step 1 — Set Environment Variables

```bash
export AWS_REGION="us-east-1"

export ACCOUNT_ID=$(aws sts get-caller-identity \
  --query Account \
  --output text)

export BUCKET="cloud-lab02-${ACCOUNT_ID}"
```

Verify:

```bash
echo "Region: $AWS_REGION"
echo "Bucket: $BUCKET"
```

Environment variables must be set again when opening a new Bash session, unless they have been persisted in the shell configuration.

### Step 2 — Create the Lab Bucket

First check whether it already exists:

```bash
aws s3api head-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

If the bucket does not exist and the name is available, create it:

```bash
aws s3api create-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

This example uses `us-east-1`.

Keep S3 Block Public Access enabled.

Do not create a new bucket when a failed `HeadBucket` request is due to missing permissions.

---

## 5. Create the Working Environment

### Step 1 — Create the Directory

```bash
mkdir -p reports
```

### Step 2 — Create the Test File

```bash
echo "Cloud Engineering Lab 02 - Production Report" > reports/data.txt
```

Verify:

```bash
cat reports/data.txt
```

Expected output:

```text
Cloud Engineering Lab 02 - Production Report
```

### Step 3 — Upload to S3

```bash
aws s3 cp reports/data.txt \
  "s3://$BUCKET/reports/data.txt" \
  --region "$AWS_REGION"
```

### Step 4 — Verify the Object

```bash
aws s3 ls "s3://$BUCKET/reports/" \
  --region "$AWS_REGION"
```

Expected: the listing contains `data.txt`.

Check object metadata:

```bash
aws s3api head-object \
  --bucket "$BUCKET" \
  --key "reports/data.txt" \
  --region "$AWS_REGION"
```

A successful response returns object metadata.

The baseline environment is now working.

---

## 6. Introduce the Failure

The goal is to reproduce a common application configuration error.

### Correct Object Key

```text
reports/data.txt
```

### Incorrect Object Key

```text
reports/Data.txt
```

Notice the uppercase `D`.

Run:

```bash
aws s3api get-object \
  --bucket "$BUCKET" \
  --key "reports/Data.txt" \
  failed-download.txt \
  --region "$AWS_REGION"
```

### Expected Error

```text
An error occurred (NoSuchKey) when calling the GetObject operation:
The specified key does not exist.
```

**Note:** When an object is absent, S3 generally returns `404` if the caller has `s3:ListBucket`, but may return `403 AccessDenied` without that permission.

The error is simulated without deleting or modifying the actual stored object.

---

## 7. Troubleshooting Investigation

### Check 1 — Confirm AWS Identity

```bash
aws sts get-caller-identity
```

**Purpose:** Confirm the AWS account and principal used to perform the request.

An incorrect AWS profile or account can cause applications to access unexpected resources.

### Check 2 — Verify the Bucket Name

```bash
echo "$BUCKET"
```

Check that the bucket name matches the application's expected configuration.

### Check 3 — List Existing Objects

```bash
aws s3 ls "s3://$BUCKET/" --recursive \
  --region "$AWS_REGION"
```

Look for the actual object key:

```text
reports/data.txt
```

### Check 4 — Inspect the Correct Object

```bash
aws s3api head-object \
  --bucket "$BUCKET" \
  --key "reports/data.txt" \
  --region "$AWS_REGION"
```

**Expected:** Object metadata is returned.

### Check 5 — Inspect the Incorrect Key

```bash
aws s3api head-object \
  --bucket "$BUCKET" \
  --key "reports/Data.txt" \
  --region "$AWS_REGION"
```

A missing object may produce `404 Not Found` or `403 AccessDenied`, depending on permissions.

`HeadObject` does not necessarily return the detailed `NoSuchKey` message shown by `GetObject`.

### Check 6 — Compare Object Keys

| Property | Actual | Requested |
|---|---|---|
| Bucket | Same | Same |
| Prefix | `reports/` | `reports/` |
| Filename | `data.txt` | `Data.txt` |
| Case | Lowercase `d` | Uppercase `D` |
| Result | Found | Not found |

**Finding:** The object key in the request does not exactly match the stored key.

---

## 8. Root Cause Analysis

### Root Cause

The application requested the wrong S3 object key because of incorrect capitalization.

The actual object is:

```text
reports/data.txt
```

The application requested:

```text
reports/Data.txt
```

Amazon S3 uses exact object keys and treats uppercase and lowercase letters as different characters.

### Technical Explanation

The S3 `GetObject` operation requires an exact key identifying the requested object.

Because `reports/Data.txt` was never uploaded, the request cannot retrieve that object.

### Root Cause Flow

```text
Incorrect Object Key
         |
         v
GetObject Request
         |
         v
Amazon S3
         |
         v
Exact Key Not Found
         |
         v
     NoSuchKey
```

### Five Whys

1. **Why did the download fail?** The request returned `NoSuchKey`.
2. **Why was `NoSuchKey` returned?** The requested key did not exist.
3. **Why did the requested key not exist?** The filename used different capitalization.
4. **Why did the application use the wrong filename?** The lab deliberately introduced an incorrect object reference.
5. **How can the problem be prevented?** Validate object keys and test storage operations during deployment.

---

## 9. Remediation

The solution is to use the exact existing object key.

### Step 1 — Correct the Request

Use:

```text
reports/data.txt
```

instead of:

```text
reports/Data.txt
```

### Step 2 — Download the Object

```bash
aws s3api get-object \
  --bucket "$BUCKET" \
  --key "reports/data.txt" \
  recovered-report.txt \
  --region "$AWS_REGION"
```

### Step 3 — Verify Content

```bash
cat recovered-report.txt
```

Expected:

```text
Cloud Engineering Lab 02 - Production Report
```

The corrected request successfully retrieves the object.

---

## 10. Verification

### Verify Object Metadata

```bash
aws s3api head-object \
  --bucket "$BUCKET" \
  --key "reports/data.txt" \
  --region "$AWS_REGION"
```

### Compare Files

```bash
diff reports/data.txt recovered-report.txt
```

No output means the file contents match.

### Verify SHA-256 Hashes

```bash
sha256sum reports/data.txt recovered-report.txt
```

The hashes should match.

### Verification Summary

| Check | Expected Result |
|---|---|
| Bucket accessible | Pass |
| Object present | Pass |
| Wrong key request | Failure reproduced |
| Correct key request | Successful download |
| File comparison | Identical |
| Root cause identified | Key capitalization mismatch |

These are the expected results of a successful lab execution.

---

## 11. Production Troubleshooting Considerations

In a production environment, engineers should avoid changing or recreating resources without identifying the cause.

### Review Application Configuration

Check the object's key source:

- Application environment variables
- Configuration files
- Database records storing object references
- Deployment parameters
- Event payloads
- CI/CD configuration

### Verify Prefixes and Case Sensitivity

Check:

```text
reports/data.txt
reports/Data.txt
Reports/data.txt
reports/2026/data.txt
```

These are different S3 object keys.

### Check Recent Deployments

Determine whether a recent deployment changed the object's path or naming convention.

### Inspect Monitoring and Logs

Useful sources may include:

- Application logs
- CloudTrail S3 data events, if enabled
- S3 server access logs, if configured
- CloudWatch metrics and alarms

CloudTrail Event History alone does not provide ordinary S3 object-level `GetObject` data events. Data-event logging must be configured when this visibility is required.

### Prevention

- Use consistent object naming conventions.
- Validate object keys before making requests.
- Add automated integration tests.
- Avoid manually hardcoding object paths when possible.
- Monitor repeated `4xx` errors.
- Implement appropriate error handling in applications.

---

## 12. Common Related S3 Errors

| Error | Meaning or Investigation |
|---|---|
| `NoSuchBucket` | Requested bucket does not exist |
| `NoSuchKey` | Requested object key does not exist |
| `AccessDenied` | Permission or access-control investigation required |
| `InvalidAccessKeyId` | AWS access key validation required |
| `SignatureDoesNotMatch` | Credentials or request-signing investigation required |
| `PermanentRedirect` | Bucket endpoint or Region configuration may be incorrect |

Understanding these differences is important when troubleshooting AWS storage applications.

---

## 13. Interview Questions

### Q1. What causes `NoSuchKey` in Amazon S3?

The requested object key does not exist in the specified bucket.

Common causes include incorrect filenames, capitalization, prefixes, missing uploads, or deleted objects.

### Q2. Does S3 treat `data.txt` and `Data.txt` as the same object?

No. Amazon S3 object keys are case-sensitive.

### Q3. How do you troubleshoot an S3 `NoSuchKey` error?

I would verify the AWS identity, bucket name, and exact object key. Then I would inspect existing objects using AWS CLI, compare the requested key with the actual key, and correct the application's object reference.

Finally, I would verify that the object can be retrieved successfully.

### Q4. What is the difference between `NoSuchKey` and `NoSuchBucket`?

`NoSuchBucket` indicates that the specified bucket does not exist.

`NoSuchKey` indicates that the specified object key does not exist.

### Q5. Can a missing S3 object return `AccessDenied` instead of `NoSuchKey`?

Yes.

If the caller does not have `s3:ListBucket`, S3 may return `403 AccessDenied` rather than disclosing that the object is missing.

### Q6. How would you prevent object naming problems in production?

I would use consistent naming conventions, validate object keys, avoid unnecessary hardcoded paths, and use automated integration tests.

### Q7. Would you modify the IAM policy immediately?

No.

I would first investigate the error and compare the requested object key with the actual object.

Changing IAM permissions without evidence can introduce security risks.

---

## 14. Cleanup

After successful verification, remove the dedicated lab resources.

Confirm the bucket:

```bash
echo "$BUCKET"
```

List its contents:

```bash
aws s3 ls "s3://$BUCKET/" --recursive \
  --region "$AWS_REGION"
```

Remove the test object:

```bash
aws s3 rm "s3://$BUCKET/reports/data.txt" \
  --region "$AWS_REGION"
```

Delete the bucket once it is empty:

```bash
aws s3api delete-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

Only delete the dedicated lab bucket. If bucket versioning was enabled or additional resources exist, further cleanup may be required.

Remove the temporary downloaded file:

```bash
rm -f recovered-report.txt failed-download.txt
```

Keep `reports/data.txt` as a harmless sample file for the GitHub repository.

---

## 15. Lessons Learned

This lab demonstrates that an application can fail to access an S3 object even when the bucket and the actual file exist.

The root cause was a difference in object key capitalization.

I practiced using AWS CLI on Ubuntu Linux, verifying the AWS identity, listing S3 objects, inspecting object metadata, investigating missing object errors, and confirming a successful recovery.

The most important troubleshooting lesson is to verify the exact resource identifier before changing permissions or infrastructure.

---

## 16. Skills Demonstrated

- Amazon S3 troubleshooting
- Linux Bash
- AWS CLI
- Object key validation
- Error analysis
- Root cause investigation
- Configuration remediation
- File integrity verification
- Production troubleshooting workflow
- Incident documentation

---

## Final Outcome

| Item | Result |
|---|---|
| Incident | INC-S3-002 |
| Service | Amazon S3 |
| Error | `NoSuchKey` |
| Root Cause | Object key capitalization mismatch |
| Remediation | Corrected the object key |
| Verification | Successful download and matching file contents |
| Expected Lab Status | Resolved |

**Key Takeaway:** Always verify the full S3 object key, including its prefix and capitalization, before modifying AWS permissions or infrastructure.
