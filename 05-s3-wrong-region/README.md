# Lab 05 — Amazon S3 Wrong Region / PermanentRedirect

## Overview

This lab demonstrates how to investigate and resolve an Amazon S3 endpoint or AWS Region configuration problem.

The scenario simulates an application attempting to access an S3 bucket through an incorrect regional endpoint.

The bucket exists in `us-east-1`, but the application is configured to use `us-west-2`.

Depending on the client and endpoint, this may produce an HTTP redirect, a Region-related error, or an automatic retry to the correct Region.

The goal is to diagnose the Region mismatch using AWS CLI, HTTP headers, and request debugging, then correct the configuration and verify successful object retrieval.

**Troubleshooting workflow:**

Reproduce → Observe → Investigate → Identify Root Cause → Remediate → Verify → Document

## Lab Information

| Item | Details |
|---|---|
| AWS Service | Amazon S3 |
| Difficulty | Beginner–Intermediate |
| Incident ID | INC-S3-005 |
| Issue | Incorrect S3 Region / endpoint |
| Possible Error | `PermanentRedirect`, HTTP 301, Region mismatch |
| Actual Bucket Region | `us-east-1` |
| Incorrect Region | `us-west-2` |
| Environment | Ubuntu Linux (WSL2) |
| Tools | AWS CLI v2, Bash, curl, grep |
| Root Cause | Incorrect regional endpoint configuration |
| Remediation | Configure the correct bucket Region |

---

## 1. Production Incident Scenario

### Incident Description

An application support team reports that an application cannot consistently retrieve files from Amazon S3.

The application configuration points to an S3 endpoint in `us-west-2`, but the required bucket is located in `us-east-1`.

Depending on the client implementation, requests may fail or automatically retry against the correct endpoint.

### Possible Error

```text
PermanentRedirect
The bucket you are attempting to access
must be addressed using the specified endpoint.
```

Other possible responses include:

```text
HTTP 301
HTTP 400
AuthorizationHeaderMalformed
```

These are possible symptoms, not guaranteed outputs for every wrong-Region request.

### Expected Behavior

The application accesses the S3 bucket through the correct regional endpoint and retrieves the requested object.

### Actual Problem

The request configuration selects an endpoint associated with the wrong AWS Region.

### Potential Business Impact

- Failed or delayed file retrieval
- Increased request latency from redirect handling
- Application errors
- Repeated retry attempts
- Interrupted data-processing workflows

---

## 2. Architecture

### Correct Configuration

```text
Application / AWS CLI
         |
         | Region: us-east-1
         v
S3 Regional Endpoint
s3.us-east-1.amazonaws.com
         |
         v
S3 Bucket (us-east-1)
         |
         v
region-test.txt
         |
         v
Successful Download
```

### Incorrect Configuration

```text
Application / AWS CLI
         |
         | Region: us-west-2
         v
Wrong S3 Regional Endpoint
s3.us-west-2.amazonaws.com
         |
         v
Region Mismatch
         |
         +-------------------------+
         |                         |
         v                         v
Redirect / Error         Client Automatically Retries
         |                         |
         v                         v
Application Failure      Correct Regional Endpoint
                                   |
                                   v
                              Successful Request
```

### Key Concept

An S3 bucket belongs to a specific AWS Region.

Clients should use the appropriate regional endpoint and request-signing configuration.

AWS CLI v2 can automatically handle some wrong-Region requests, so inspecting the actual HTTP exchange is important.

---

## 3. Prerequisites

Required tools:

- AWS account
- AWS CLI v2
- Ubuntu Linux / WSL2
- Bash
- curl
- grep
- Permission to create and delete test buckets
- Permission to upload, download, and inspect S3 objects

### Verify AWS CLI

```bash
aws --version
```

### Verify Identity

```bash
aws sts get-caller-identity
```

### Inspect AWS Configuration

```bash
aws configure list
```

Confirm that your AWS credentials belong to the intended lab account.

---

## 4. Configure the Environment

### Step 1 — Set Environment Variables

```bash
export AWS_REGION="us-east-1"

export WRONG_REGION="us-west-2"

export ACCOUNT_ID=$(aws sts get-caller-identity \
  --query Account \
  --output text)

export BUCKET="cloud-lab05-${ACCOUNT_ID}"
```

### Step 2 — Verify Variables

```bash
echo "Actual Region: $AWS_REGION"
echo "Wrong Region: $WRONG_REGION"
echo "Bucket: $BUCKET"
```

Expected example:

```text
Actual Region: us-east-1
Wrong Region: us-west-2
Bucket: cloud-lab05-123456789012
```

These variables apply to the current Bash session.

---

## 5. Create the Working Environment

### Step 1 — Check the Bucket

```bash
aws s3api head-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

If the bucket does not exist and the name is available, create it.

Do not assume that every `403` or `404` response means the bucket name is available.

### Step 2 — Create the Bucket

```bash
aws s3api create-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

This command is appropriate for `us-east-1`.

### Step 3 — Verify Bucket Access

```bash
aws s3api head-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

A successful command normally returns no output.

### Step 4 — Create a Test Object

```bash
echo "Cloud Engineering Lab 05 - Region Test" > region-test.txt
```

Verify:

```bash
cat region-test.txt
```

### Step 5 — Upload the Object

```bash
aws s3 cp region-test.txt \
  "s3://$BUCKET/region-test.txt" \
  --region "$AWS_REGION"
```

### Step 6 — Verify the Object

```bash
aws s3api head-object \
  --bucket "$BUCKET" \
  --key "region-test.txt" \
  --region "$AWS_REGION"
```

The object should exist and be accessible.

---

## 6. Establish the Correct Bucket Region

### Method 1 — GetBucketLocation

```bash
aws s3api get-bucket-location \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

Expected for `us-east-1`:

```json
{
  "LocationConstraint": null
}
```

For general-purpose S3 buckets, a null location constraint represents `us-east-1`.

### Method 2 — HeadBucket

```bash
aws s3api head-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

The S3 `HeadBucket` response includes the `x-amz-bucket-region` header.

To inspect the headers using AWS CLI debugging:

```bash
aws s3api head-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION" \
  --debug 2> head-bucket-debug.log
```

Search for the Region header:

```bash
grep -i "x-amz-bucket-region" \
  head-bucket-debug.log | head
```

Expected Region:

```text
us-east-1
```

**Security note:** AWS CLI debug logs may contain sensitive request information. Do not commit raw debug logs to GitHub.

---

## 7. Introduce the Wrong-Region Configuration

We will deliberately request the S3 object using `us-west-2`.

```bash
aws s3api head-object \
  --bucket "$BUCKET" \
  --key "region-test.txt" \
  --region "$WRONG_REGION"
```

### Expected Behavior

AWS CLI v2 may automatically discover the correct bucket Region and retry the request.

Therefore, the command may succeed even though the initial Region was incorrect.

A successful CLI response does not automatically prove that the original configuration was correct.

---

## 8. Investigate Endpoint Selection

### Step 1 — Enable CLI Debugging

```bash
aws s3api head-object \
  --bucket "$BUCKET" \
  --key "region-test.txt" \
  --region "$WRONG_REGION" \
  --debug 2> wrong-region-debug.log
```

### Step 2 — Inspect Relevant Debug Lines

```bash
grep -Ei \
  "endpoint|redirect|x-amz-bucket-region|us-east-1|us-west-2" \
  wrong-region-debug.log | head -n 35
```

Look for:

- Initial endpoint selection
- Wrong Region in the request
- S3 Region response header
- Endpoint correction
- Retry behavior

### Production Lesson

AWS CLI and SDK behavior matters.

A modern client may recover automatically from certain configuration mistakes, while another application might surface a redirect or request-signing error.

The goal is to understand the actual behavior rather than assume a specific error must appear.

---

## 9. Inspect the HTTP Response

Use `curl` to examine a request sent directly to the incorrect regional endpoint.

This diagnostic request is unsigned and does not attempt to retrieve private object contents successfully.

```bash
curl -sS \
  -D wrong-region-headers.txt \
  -o /dev/null \
  "https://${BUCKET}.s3.${WRONG_REGION}.amazonaws.com/region-test.txt"
```

Display the headers:

```bash
cat wrong-region-headers.txt
```

Look for:

```text
x-amz-bucket-region: us-east-1
```

The response may include a redirect status or an access error, depending on the endpoint and request context.

The key diagnostic finding is that the bucket's actual Region differs from the endpoint used by the request.

### Why Not Assume HTTP 301?

S3 routing behavior varies by request type, Region, endpoint, and client.

Some incorrect endpoint requests return permanent redirects, others return different errors, and AWS CLI may automatically retry.

A production engineer should document the response actually observed.

---

## 10. Troubleshooting Investigation

### Check 1 — Confirm AWS Identity

```bash
aws sts get-caller-identity
```

### Check 2 — Inspect CLI Configuration

```bash
aws configure list
```

### Check 3 — Confirm the Actual Bucket Region

```bash
aws s3api get-bucket-location \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

### Check 4 — Compare Configured Regions

```bash
echo "Expected: $AWS_REGION"
echo "Incorrect: $WRONG_REGION"
```

### Check 5 — Inspect Debug Output

```bash
grep -Ei "endpoint|redirect|region" \
  wrong-region-debug.log | head -n 35
```

### Investigation Summary

| Check | Finding |
|---|---|
| AWS identity | Intended lab account |
| Bucket exists | Yes |
| Object exists | Yes |
| Bucket Region | `us-east-1` |
| Incorrect endpoint Region | `us-west-2` |
| Root cause | Regional endpoint mismatch |
| CLI behavior | May automatically retry |

---

## 11. Root Cause Analysis

### Root Cause

The application or request configuration uses `us-west-2` to access an S3 bucket located in `us-east-1`.

### Technical Explanation

Amazon S3 uses regional endpoints to route requests.

When the client sends a request to an inappropriate regional endpoint, S3 may respond with redirect or Region-related information.

Some SDKs and AWS CLI versions automatically correct the destination.

An application that does not handle the mismatch appropriately may experience failures.

### Root Cause Flow

```text
Application Request
         |
         v
Configured Region: us-west-2
         |
         v
Bucket Located: us-east-1
         |
         v
Endpoint / Region Mismatch
         |
         v
Redirect, Error, or Automatic Retry
```

### Five Whys

1. **Why might the application fail?** The request uses an incorrect regional endpoint.
2. **Why is the endpoint incorrect?** The client is configured for `us-west-2`.
3. **Where is the bucket located?** In `us-east-1`.
4. **Why was the incorrect Region used?** The lab deliberately introduced a configuration mismatch.
5. **How can the problem be prevented?** Validate bucket Regions and use consistent application and infrastructure configuration.

---

## 12. Remediation

The correct solution is to configure the application or AWS client to use the bucket's actual Region.

### Step 1 — Use the Correct Region

```bash
aws s3api get-object \
  --bucket "$BUCKET" \
  --key "region-test.txt" \
  recovered-region-test.txt \
  --region "$AWS_REGION"
```

### Step 2 — Verify Download

```bash
cat recovered-region-test.txt
```

Expected:

```text
Cloud Engineering Lab 05 - Region Test
```

### Step 3 — Verify File Integrity

```bash
diff region-test.txt recovered-region-test.txt
```

No output means the original and recovered files match.

### Production Remediation

In production, correct the Region in the appropriate configuration source:

- AWS SDK client configuration
- Application environment variables
- Container environment settings
- Terraform variables or outputs
- CI/CD deployment configuration
- Application configuration files

Avoid making unrelated infrastructure changes.

---

## 13. Final Verification

### Verify the Correct Region

```bash
aws s3api get-bucket-location \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

### Verify Object Metadata

```bash
aws s3api head-object \
  --bucket "$BUCKET" \
  --key "region-test.txt" \
  --region "$AWS_REGION"
```

### Verify Successful Download

```bash
aws s3api get-object \
  --bucket "$BUCKET" \
  --key "region-test.txt" \
  recovered-region-test.txt \
  --region "$AWS_REGION"
```

### Compare File Hashes

```bash
sha256sum region-test.txt recovered-region-test.txt
```

The hashes should match.

### Verification Summary

| Check | Expected Result |
|---|---|
| Bucket exists | Pass |
| Bucket Region identified | Pass |
| Wrong Region investigated | Pass |
| HTTP headers inspected | Pass |
| Correct endpoint used | Pass |
| Object download | Success |
| File integrity | Verified |

These are the expected results of a successful lab.

---

## 14. Production Engineering Considerations

### Incident Triage

Determine:

- Which application is affected?
- Which S3 bucket is involved?
- What is the actual error response?
- Which endpoint is configured?
- Did a recent deployment change the Region?
- Does the application retry automatically?

### Evidence Collection

Useful evidence includes:

- AWS CLI debug logs
- Application error logs
- HTTP response status and headers
- Bucket Region metadata
- SDK client configuration
- Recent configuration changes

### Safe Remediation

A Cloud Engineer should:

1. Verify the AWS identity and environment.
2. Confirm the bucket's actual Region.
3. Inspect the endpoint used by the failing client.
4. Identify the configuration mismatch.
5. Correct only the relevant client configuration.
6. Test the original failing operation.
7. Verify application recovery.
8. Document the incident.

### Prevention

- Use AWS SDKs with appropriate regional configuration.
- Validate bucket Region during deployment.
- Manage environment-specific settings consistently.
- Use infrastructure outputs for resource configuration.
- Add integration tests.
- Monitor S3 request failures and retries.
- Review application logs after infrastructure changes.

---

## 15. Related S3 Errors

| Error | Possible Investigation |
|---|---|
| `PermanentRedirect` | Incorrect S3 endpoint or request addressing |
| HTTP 301 | Redirect to a different S3 endpoint |
| HTTP 307 | Temporary routing redirection |
| `AuthorizationHeaderMalformed` | Request signing Region mismatch |
| `IllegalLocationConstraintException` | Bucket creation Region configuration mismatch |
| `AccessDenied` | Permissions, resource policies, encryption |
| `NoSuchBucket` | Bucket name or existence |
| `NoSuchKey` | Object key or existence |

An error code must always be interpreted with its request context.

---

## 16. Interview Questions and Answers

### Q1. What causes a PermanentRedirect error in S3?

A permanent redirect may occur when an S3 request uses an inappropriate endpoint or addressing format.

The engineer should inspect the response and determine the correct bucket endpoint.

### Q2. How do you find an S3 bucket's Region?

Use `HeadBucket` and inspect the `x-amz-bucket-region` response header, or use `GetBucketLocation` when permitted.

### Q3. What does a null LocationConstraint mean?

For a general-purpose S3 bucket, it indicates `us-east-1`.

### Q4. Will AWS CLI always fail when using the wrong Region?

No.

AWS CLI may automatically discover the correct bucket Region and retry requests.

### Q5. How do you investigate the endpoint selected by AWS CLI?

Use the `--debug` option and examine the endpoint selection, HTTP response headers, and retry information.

### Q6. Why can one application fail while AWS CLI succeeds?

Different applications and AWS SDKs may handle Region discovery, request signing, and redirects differently.

AWS CLI may recover from certain Region mismatches automatically.

### Q7. Should you move the bucket to another Region to fix the problem?

Not automatically.

If the problem is an incorrect client configuration, the appropriate fix is generally to correct that configuration.

### Q8. How would you prevent Region configuration problems?

Use consistent infrastructure configuration, validate resource Regions, implement integration tests, and monitor application errors.

---

## 17. Cleanup

Confirm the bucket name:

```bash
echo "$BUCKET"
```

List the objects:

```bash
aws s3 ls "s3://$BUCKET/" \
  --recursive \
  --region "$AWS_REGION"
```

After confirming that this is the dedicated lab bucket containing only the test object, remove it:

```bash
aws s3 rm "s3://$BUCKET/region-test.txt" \
  --region "$AWS_REGION"
```

Delete the empty bucket:

```bash
aws s3api delete-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

These commands assume versioning was not enabled and no unrelated data was added.

Remove local temporary files:

```bash
rm -f recovered-region-test.txt \
  head-bucket-debug.log \
  wrong-region-debug.log \
  wrong-region-headers.txt
```

Keep `region-test.txt` as a sample artifact for the repository.

---

## 18. Repository Structure

```text
05-s3-wrong-region/
│
├── README.md
└── region-test.txt
```

Temporary debug logs and downloaded files should not be committed.

---

## 19. Lessons Learned

This lab demonstrates how an incorrect AWS Region or S3 endpoint can affect application requests.

The investigation used AWS CLI, bucket location metadata, HTTP headers, and debug output to identify the difference between the configured endpoint and the bucket's actual Region.

An important observation is that modern AWS clients may automatically recover from some Region mismatches.

The main lesson is to inspect the actual request behavior, identify the correct regional endpoint, and validate the configuration before changing infrastructure.

---

## 20. Skills Demonstrated

- Amazon S3 troubleshooting
- Linux Bash
- AWS CLI v2
- S3 regional endpoint investigation
- HTTP response header analysis
- curl troubleshooting
- AWS CLI debug analysis
- Root cause investigation
- Client configuration remediation
- File integrity verification
- Production incident documentation

## Final Outcome

| Item | Result |
|---|---|
| Incident | INC-S3-005 |
| Service | Amazon S3 |
| Issue | Incorrect S3 Region / endpoint |
| Actual Region | `us-east-1` |
| Incorrect Region | `us-west-2` |
| Root Cause | Regional endpoint mismatch |
| Remediation | Use the correct bucket Region |
| Verification | Correct-region download and file comparison |
| Expected Lab Status | Resolved |

**Key Takeaway:** When investigating S3 redirect or Region errors, verify the bucket's actual Region, inspect the selected endpoint, understand client retry behavior, and correct the client configuration rather than making unnecessary infrastructure changes.
