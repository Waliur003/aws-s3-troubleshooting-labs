# Lab 01 — Amazon S3 Bucket Not Found (`NoSuchBucket`)

## Overview

This hands-on lab demonstrates how to investigate and resolve the `NoSuchBucket` error in Amazon Simple Storage Service (S3).

The scenario simulates an application attempting to access an S3 bucket that does not exist because of an incorrect bucket name in its configuration.

The objective is to reproduce the failure, investigate the error using AWS CLI, identify the root cause, apply a safe remediation, and verify that S3 operations succeed again.

**AWS Service:** Amazon S3  
**Difficulty:** Beginner  
**Error:** `NoSuchBucket`  
**Tools:** AWS CLI, PowerShell, AWS Management Console  
**Troubleshooting Focus:** Bucket name validation, AWS identity verification, configuration troubleshooting, and recovery verification

---

## 1. Incident Scenario

**Incident ID:** INC-S3-001

**Reported Issue:**

An application that retrieves files from an S3 bucket suddenly fails with the following error:

```text
An error occurred (NoSuchBucket) when calling the
GetObject operation: The specified bucket does not exist
```

The application support team reports that users cannot download the required files.

As the Cloud Engineer, the responsibility is to investigate why the application cannot access the bucket and restore the functionality safely.

### Expected Behavior

The application should be able to download an existing object from the correct S3 bucket.

### Actual Behavior

The application references a nonexistent bucket and receives `NoSuchBucket`.

### Impact

The affected application's file download operation fails.

In a real production environment, the severity depends on the number of affected users, whether other operations are impacted, and the business importance of the application.

---

## 2. Architecture

### Working Architecture

```text
Application / AWS CLI
         |
         | GetObject
         v
  Correct S3 Bucket
         |
         v
      test.txt
         |
         v
  Successful Download
```

### Broken Architecture

```text
Application / AWS CLI
         |
         | GetObject
         v
 Incorrect Bucket Name
         |
         X
    NoSuchBucket
```

The S3 service remains available. The failure is caused by the incorrect bucket reference in the request.

---

## 3. Prerequisites

Before starting the lab, ensure that:

- AWS CLI is installed.
- AWS credentials are configured.
- The account has the required S3 permissions.
- PowerShell is available.
- A dedicated AWS lab environment is being used.

Verify the AWS CLI installation:

```powershell
aws --version
```

Check the AWS identity:

```powershell
aws sts get-caller-identity
```

Check the CLI configuration:

```powershell
aws configure list
```

These commands help confirm the AWS account, principal, and configuration used by the CLI.

---

## 4. Create the Working Environment

### Step 1 — Configure Variables

```powershell
$Region = "us-east-1"

$AccountId = aws sts get-caller-identity --query Account --output text

$Bucket = "cloud-lab01-$AccountId"
```

The bucket name must be globally unique within its S3 bucket namespace.

If the selected name is unavailable, choose a unique suffix.

### Step 2 — Create the Bucket

```powershell
aws s3api create-bucket `
  --bucket $Bucket `
  --region $Region
```

The example uses `us-east-1`, where a `LocationConstraint` is not required.

### Step 3 — Verify the Bucket

```powershell
aws s3api head-bucket `
  --bucket $Bucket `
  --region $Region
```

A successful `HeadBucket` request normally returns no output.

List the bucket contents:

```powershell
aws s3 ls "s3://$Bucket" --region $Region
```

An empty result is expected when the bucket has no objects.

### Step 4 — Create a Test File

```powershell
"Cloud Engineering Troubleshooting Lab 01" |
  Out-File -Encoding utf8 test.txt
```

### Step 5 — Upload the Test File

```powershell
aws s3 cp test.txt "s3://$Bucket/test.txt" --region $Region
```

Verify the object:

```powershell
aws s3 ls "s3://$Bucket" --region $Region
```

The output should show `test.txt`.

The working environment is now ready.

---

## 5. Introduce the Failure

To simulate an incorrect application configuration, create a variable containing a nonexistent bucket name:

```powershell
$WrongBucket = "$Bucket-missing"
```

Display the bucket names:

```powershell
Write-Host "Correct Bucket: $Bucket"
Write-Host "Wrong Bucket: $WrongBucket"
```

Attempt to download an object from the incorrect bucket:

```powershell
aws s3api get-object `
  --bucket $WrongBucket `
  --key test.txt `
  failed-download.txt `
  --region $Region
```

### Expected Error

```text
An error occurred (NoSuchBucket) when calling
the GetObject operation: The specified bucket
does not exist
```

The application is attempting to access an S3 bucket that does not exist.

**Important:** The failure is introduced in the request configuration only. The real bucket is not deleted or modified.

---

## 6. Troubleshooting Investigation

### Check 1 — Verify AWS Identity

```powershell
aws sts get-caller-identity
```

**Purpose:**

Identify which AWS principal and account are being used.

**Production Reasoning:**

Applications can sometimes use incorrect credentials, profiles, or accounts.

Confirming the identity helps eliminate one potential source of configuration errors.

### Check 2 — Inspect the Failing Request

The failing operation uses:

```text
Bucket: Incorrect bucket name
Object Key: test.txt
Operation: GetObject
```

The relevant S3 API operation is `GetObject`.

The error returned is `NoSuchBucket`.

This provides evidence that the request is targeting a bucket that S3 reports does not exist.

### Check 3 — Check the Incorrect Bucket

```powershell
aws s3api head-bucket `
  --bucket $WrongBucket `
  --region $Region
```

A possible response is:

```text
An error occurred (404) when calling the
HeadBucket operation: Not Found
```

**Important troubleshooting detail:**

`HeadBucket` can return generic HTTP errors such as `400`, `403`, and `404`. These responses are not always enough to determine the exact cause.

Engineers should combine the response with other evidence rather than assuming every failed `HeadBucket` request proves that a bucket is missing.

### Check 4 — Verify the Correct Bucket

```powershell
aws s3api head-bucket `
  --bucket $Bucket `
  --region $Region
```

Then:

```powershell
aws s3 ls "s3://$Bucket" --region $Region
```

The correct bucket should be accessible and contain the expected test object.

### Check 5 — Compare Configurations

| Configuration | Expected Result |
|---|---|
| Correct bucket name | Successful request |
| Incorrect bucket name | `NoSuchBucket` |
| AWS identity | Verified |
| Test object | Exists in correct bucket |
| S3 service | Working for the valid request |

The comparison strongly indicates that the bucket reference is the cause of the failure.

---

## 7. Root Cause Analysis

### Root Cause

The S3 request uses an incorrect bucket name.

The application is configured to retrieve an object from a bucket that does not exist.

### Technical Explanation

Amazon S3 identifies buckets using their bucket names.

When the application sends a request to a nonexistent bucket, S3 cannot locate the requested bucket and returns `NoSuchBucket`.

The error is not caused by the test object's content or a failure of the existing bucket.

### Root Cause Summary

```text
Incorrect Bucket Name
          |
          v
GetObject Request
          |
          v
Amazon S3
          |
          v
Bucket Does Not Exist
          |
          v
NoSuchBucket
```

### Five Whys — Simplified

1. **Why did the download fail?** The application received `NoSuchBucket`.
2. **Why was `NoSuchBucket` returned?** The requested bucket name did not exist.
3. **Why was the nonexistent bucket requested?** The request used an incorrect bucket variable.
4. **Why did the configuration contain the wrong name?** The lab deliberately introduced an incorrect value.
5. **What should prevent this issue in production?** Configuration validation, deployment checks, and verification against the intended AWS environment.

---

## 8. Remediation

The solution is to use the correct S3 bucket name.

Do not create an unnecessary replacement bucket just to avoid the error.

### Step 1 — Correct the Bucket Reference

Use the valid `$Bucket` variable.

### Step 2 — Repeat the Download

```powershell
aws s3api get-object `
  --bucket $Bucket `
  --key test.txt `
  recovered-test.txt `
  --region $Region
```

### Step 3 — Verify Downloaded Content

```powershell
Get-Content recovered-test.txt
```

Expected content:

```text
Cloud Engineering Troubleshooting Lab 01
```

The object download now succeeds.

---

## 9. Verification

The remediation is considered successful when:

- The AWS identity is correct.
- The intended S3 bucket is accessible.
- The expected object exists.
- The corrected `GetObject` request succeeds.
- The downloaded object contains the expected data.

### Final Verification Commands

```powershell
aws sts get-caller-identity
```

```powershell
aws s3api head-bucket `
  --bucket $Bucket `
  --region $Region
```

```powershell
aws s3api head-object `
  --bucket $Bucket `
  --key test.txt `
  --region $Region
```

```powershell
Get-Content recovered-test.txt
```

### Expected Result

```text
Bucket Exists: YES
Object Exists: YES
Download Successful: YES
Content Verified: YES
```

The simulated incident is resolved.

---

## 10. Production Troubleshooting Considerations

In a production AWS environment, engineers should perform additional checks before modifying infrastructure.

### Check Application Configuration

Investigate where the bucket name is configured:

- Environment variables
- Application configuration files
- Terraform outputs
- Deployment parameters
- AWS Systems Manager Parameter Store
- CI/CD pipeline configuration

### Check Recent Changes

Determine whether a recent deployment or configuration change introduced the incorrect bucket reference.

### Avoid Unnecessary Changes

Do not:

- Delete a working S3 bucket.
- Create a replacement bucket without understanding the requirement.
- Disable security controls.
- Change unrelated IAM permissions.
- Modify production configuration without appropriate approval.

### Improve Reliability

Possible preventive controls include:

- Validate required bucket names during deployment.
- Use infrastructure outputs instead of manually copying resource names.
- Add integration tests for storage dependencies.
- Monitor application storage errors.
- Maintain documented troubleshooting procedures.

---

## 11. Interview Questions and Answers

### Q1. What does `NoSuchBucket` mean?

`NoSuchBucket` means Amazon S3 reports that the specified bucket does not exist.

A common cause is an incorrect bucket name in an application or CLI request.

### Q2. How would you troubleshoot `NoSuchBucket`?

First, verify the AWS account and configured bucket name. Then reproduce the failure, inspect the request, check whether the intended bucket exists, compare against a known-good configuration, correct the bucket reference, and verify the operation.

### Q3. What is the difference between `NoSuchBucket` and `NoSuchKey`?

`NoSuchBucket` means the requested bucket does not exist.

`NoSuchKey` means the requested object key does not exist in the bucket. Depending on permissions, a missing object may also produce a `403` response.

### Q4. Why use `aws sts get-caller-identity`?

It helps identify the AWS principal and account used by the CLI.

This is especially useful when multiple AWS profiles or accounts are configured.

### Q5. What does `head-bucket` do?

It checks whether an S3 bucket is accessible to the caller and returns response metadata.

A successful request indicates that the request was accepted, but some failures return generic HTTP status codes that require additional investigation.

### Q6. Would you create a new bucket to fix `NoSuchBucket`?

Not automatically.

First, confirm whether the application should reference an existing bucket. Creating a new bucket unnecessarily can cause configuration drift, data inconsistencies, and operational confusion.

### Q7. How can this problem be prevented?

Use validated configuration values, infrastructure outputs, deployment checks, monitoring, and documented operational procedures.

---

## 12. Cleanup

After completing the lab, remove the dedicated lab resources.

### Delete the Test Object

```powershell
aws s3 rm "s3://$Bucket/test.txt" --region $Region
```

### Delete the Bucket

```powershell
aws s3api delete-bucket `
  --bucket $Bucket `
  --region $Region
```

Verify that the bucket name belongs to this lab before deleting it.

These cleanup commands assume the lab bucket does not contain additional objects or versions.

### Remove Temporary Local Files

```powershell
Remove-Item recovered-test.txt -ErrorAction SilentlyContinue
Remove-Item failed-download.txt -ErrorAction SilentlyContinue
```

The original `test.txt` may be retained as a sample test artifact.

---

## 13. Lessons Learned

This lab demonstrated that a cloud storage failure can result from something as simple as an incorrect resource name.

The important lesson is to investigate before making changes.

I practiced verifying AWS identity, checking S3 bucket availability, reproducing an error, comparing a failed request against a working configuration, and validating the remediation.

This troubleshooting approach also applies to EC2, Lambda, RDS, DynamoDB, and other AWS services.

---

## 14. Skills Demonstrated

- Amazon S3 troubleshooting
- AWS CLI
- AWS identity verification
- S3 bucket validation
- S3 object operations
- Root cause analysis
- Configuration troubleshooting
- Incident documentation
- Remediation verification
- Production troubleshooting awareness

## 15. Final Outcome

**Incident:** INC-S3-001  
**Problem:** S3 `NoSuchBucket`  
**Root Cause:** Incorrect bucket name  
**Remediation:** Corrected S3 bucket reference  
**Verification:** Successful object download  
**Lab Result:** Resolved in the simulated environment

This lab demonstrates a foundational troubleshooting technique used in cloud engineering: verify the environment, reproduce the failure, gather evidence, correct the root cause, and validate recovery.
