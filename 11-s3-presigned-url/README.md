# Lab 11 — Amazon S3 Presigned URL Expired / SignatureDoesNotMatch

## Overview

This lab demonstrates how to troubleshoot Amazon S3 presigned URL failures using AWS CLI, Linux Bash, and curl.

Presigned URLs allow temporary access to private S3 objects without requiring the recipient to have AWS credentials.

In this exercise, we investigate two production-inspired incidents:

1. **Expired URL:** The application generates a download link that stops working after its expiration time.
2. **SignatureDoesNotMatch:** A signed URL is modified, causing Amazon S3 to reject the signature.

We will reproduce each failure, examine the S3 error response, apply the correct remediation, verify file integrity, and confirm that the bucket remains private.

**Workflow:** Establish Baseline → Simulate Failure → Investigate → Identify Root Cause → Remediate → Verify → Cleanup

## Lab Information

| Item | Details |
|---|---|
| AWS Service | Amazon S3 |
| Incident ID | INC-S3-011 |
| Difficulty | Intermediate |
| Feature | Presigned URLs |
| Errors | `AccessDenied`, `SignatureDoesNotMatch` |
| HTTP Status | 403 Forbidden |
| Environment | Ubuntu Linux / WSL2 |
| Tools | AWS CLI v2, Bash, curl, Python 3 |
| Authentication | AWS Signature Version 4 |
| Security | Private S3 Bucket |
| Recovery | Generate a fresh, unmodified URL |

---

## 1. Production Incident Scenario

### Incident Description

An application generates temporary download links for private customer documents stored in Amazon S3.

Users report that some links return `403 Forbidden`.

The Cloud Engineering team identifies two symptoms.

**Incident A — Expired URL**

```text
HTTP 403 Forbidden
AccessDenied: Request has expired
```

**Incident B — Signature Mismatch**

```text
HTTP 403 Forbidden
SignatureDoesNotMatch
```

### Expected Behavior

An authorized application generates a valid temporary link, allowing the recipient to download the intended S3 object.

### Actual Behavior

The request fails because the signed URL has expired or no longer matches the original signed request.

### Potential Business Impact

- Customers cannot download requested documents.
- Application workflows fail.
- Support requests increase.
- Automated file distribution is interrupted.

---

## 2. Architecture

### Working Request

```text
Authorized Application
         |
         | GeneratePresignedURL
         v
AWS Signature Version 4
         |
         v
Temporary Signed URL
         |
         v
User / curl
         |
         | HTTP GET
         v
Private Amazon S3 Bucket
         |
         v
Signature + Permissions Valid
         |
         v
HTTP 200 OK
```

### Failed Request

```text
User / Application
         |
         v
Expired or Modified URL
         |
         v
Amazon S3
         |
         v
Signature / Expiration Check
         |
         X
HTTP 403 Forbidden
```

The S3 bucket remains private in both scenarios.

---

## 3. Understanding Presigned URLs

A presigned URL includes cryptographic request-signing information in its query parameters.

Typical Signature Version 4 parameters include:

| Parameter | Purpose |
|---|---|
| `X-Amz-Algorithm` | Signing algorithm |
| `X-Amz-Credential` | Signing credential scope |
| `X-Amz-Date` | Signature creation timestamp |
| `X-Amz-Expires` | Configured URL lifetime |
| `X-Amz-SignedHeaders` | Headers included in the signature |
| `X-Amz-Signature` | Cryptographic signature |
| `X-Amz-Security-Token` | Temporary session token, when applicable |

A presigned URL is a bearer capability: anyone possessing a valid URL may potentially use it.

### Expiration Rules

AWS Signature Version 4 supports a configured maximum presigned URL expiration of seven days.

However, a URL created using temporary AWS credentials becomes unusable when those credentials expire, even if its configured URL lifetime has not ended.

A bucket policy can also restrict signature age.

### Important Security Concept

Presigned URLs do not make the bucket public.

The permissions of the signing identity and applicable S3 policies still control access.

---

## 4. Prerequisites

Required tools:

- AWS account
- AWS CLI v2
- Ubuntu Linux / WSL2
- Bash
- curl
- Python 3
- Permission to manage a dedicated S3 bucket
- `s3:GetObject` permission
- Git and GitHub

Use only non-sensitive test data.

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

export BUCKET="cloud-lab11-${ACCOUNT_ID}"

export OBJECT_KEY="documents/private-report.txt"
```

Verify:

```bash
echo "Region: $AWS_REGION"
echo "Bucket: $BUCKET"
echo "Object: $OBJECT_KEY"
```

---

## 5. Create the Working Environment

### Step 1 — Check the Bucket Name

```bash
aws s3api head-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

Only create the bucket if its name is available and it is not already used by another environment.

### Step 2 — Create the S3 Bucket

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

Verify:

```bash
aws s3api get-public-access-block \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

All four controls should be enabled.

### Step 4 — Create the Test Document

Create `private-report.txt`:

```bash
cat > private-report.txt <<'EOF'
Cloud Engineering Lab 11

Document: Private S3 Report
Status: Confidential Test Data
Purpose: Presigned URL Troubleshooting
EOF
```

This is educational sample content.

### Step 5 — Upload the Object

```bash
aws s3api put-object \
  --bucket "$BUCKET" \
  --key "$OBJECT_KEY" \
  --body private-report.txt \
  --region "$AWS_REGION"
```

### Step 6 — Verify Object

```bash
aws s3api head-object \
  --bucket "$BUCKET" \
  --key "$OBJECT_KEY" \
  --region "$AWS_REGION"
```

---

## 6. Verify the Bucket Is Private

Create the normal unsigned object URL:

```bash
export OBJECT_URL="https://${BUCKET}.s3.${AWS_REGION}.amazonaws.com/${OBJECT_KEY}"
```

Attempt anonymous access:

```bash
curl -sS -o /dev/null \
  -w "HTTP Status: %{http_code}\n" \
  "$OBJECT_URL"
```

Expected:

```text
HTTP Status: 403
```

The private object cannot be downloaded anonymously through this unsigned request.

---

## 7. Establish a Working Presigned URL

### Step 1 — Generate a Valid URL

```bash
export VALID_URL=$(aws s3 presign \
  "s3://$BUCKET/$OBJECT_KEY" \
  --expires-in 600 \
  --region "$AWS_REGION")
```

The URL is configured for a 10-minute lifetime, subject to the validity of the signing credentials and applicable policies.

Verify that generation succeeded without printing the URL:

```bash
if [[ -n "$VALID_URL" ]]; then
  echo "Presigned URL generated successfully"
else
  echo "Presigned URL generation failed"
fi
```

### Step 2 — Download the Object

```bash
curl -sS \
  -o downloaded-report.txt \
  -w "HTTP Status: %{http_code}\n" \
  "$VALID_URL"
```

Expected:

```text
HTTP Status: 200
```

### Step 3 — Verify File Integrity

```bash
diff private-report.txt downloaded-report.txt
```

No output means the contents match.

### Baseline Result

The object is private, but a properly generated presigned URL permits temporary access.

---

## 8. Incident A — Expired Presigned URL

### Step 1 — Generate a Short-Lived URL

```bash
export SHORT_URL=$(aws s3 presign \
  "s3://$BUCKET/$OBJECT_KEY" \
  --expires-in 5 \
  --region "$AWS_REGION")
```

### Step 2 — Allow It to Expire

```bash
sleep 8
```

### Step 3 — Reproduce the Failure

```bash
curl -sS \
  -o expired-response.xml \
  -w "HTTP Status: %{http_code}\n" \
  "$SHORT_URL"
```

Expected:

```text
HTTP Status: 403
```

Inspect:

```bash
cat expired-response.xml
```

A typical error response contains:

```xml
<Error>
  <Code>AccessDenied</Code>
  <Message>Request has expired</Message>
</Error>
```

The exact message may vary.

### Root Cause

The presigned URL was used after its configured expiration time.

The S3 object still exists, and the bucket's permissions have not changed.

---

## 9. Troubleshooting Expired URLs

When a presigned URL stops working, investigate:

1. Was its expiration time exceeded?
2. Did the AWS session used to sign it expire?
3. Is the system clock synchronized?
4. Does a bucket policy limit signature age?
5. Does the signing identity still have permission?
6. Has the URL been modified?

### Useful Diagnostic Information

Inspect the URL's non-secret metadata locally.

```bash
python3 - <<'PY'
import os
from urllib.parse import urlsplit, parse_qs

query = parse_qs(urlsplit(os.environ["SHORT_URL"]).query)

for key in ["X-Amz-Date", "X-Amz-Expires", "X-Amz-Algorithm"]:
    print(f"{key}: {query.get(key, ['Not found'])[0]}")
PY
```

Do not publish complete signed URLs or security tokens.

### Remediation

Generate a fresh URL:

```bash
export FRESH_URL=$(aws s3 presign \
  "s3://$BUCKET/$OBJECT_KEY" \
  --expires-in 600 \
  --region "$AWS_REGION")
```

Verify:

```bash
curl -sS \
  -o recovered-expired-report.txt \
  -w "HTTP Status: %{http_code}\n" \
  "$FRESH_URL"
```

Expected:

```text
HTTP Status: 200
```

Compare:

```bash
diff private-report.txt recovered-expired-report.txt
```

The expired-link incident is resolved when a fresh URL succeeds.

---

## 10. Incident B — SignatureDoesNotMatch

### Incident Description

A valid presigned URL is modified after it is generated.

Amazon S3 verifies the incoming request against the signature.

If the signature is incorrect, S3 rejects the request.

### Step 1 — Generate a Valid URL

```bash
export ORIGINAL_URL=$(aws s3 presign \
  "s3://$BUCKET/$OBJECT_KEY" \
  --expires-in 600 \
  --region "$AWS_REGION")
```

### Step 2 — Modify the Signature

Use Python to change one character in the signature parameter:

```bash
export TAMPERED_URL=$(python3 - <<'PY'
import os
from urllib.parse import (
    urlsplit,
    urlunsplit,
    parse_qsl,
    urlencode
)

url = os.environ["ORIGINAL_URL"]
parts = urlsplit(url)

parameters = parse_qsl(
    parts.query,
    keep_blank_values=True
)

modified = []

for key, value in parameters:
    if key == "X-Amz-Signature" and value:
        first = "0" if value[0] != "0" else "1"
        value = first + value[1:]

    modified.append((key, value))

print(urlunsplit((
    parts.scheme,
    parts.netloc,
    parts.path,
    urlencode(modified),
    parts.fragment
)))
PY
)
```

This intentionally invalidates the signature without modifying the stored S3 object or your AWS credentials.

### Step 3 — Send the Modified Request

```bash
curl -sS \
  -o signature-error.xml \
  -w "HTTP Status: %{http_code}\n" \
  "$TAMPERED_URL"
```

Expected:

```text
HTTP Status: 403
```

### Step 4 — Inspect the Error

```bash
grep -o '<Code>[^<]*</Code>' signature-error.xml
```

Expected:

```xml
<Code>SignatureDoesNotMatch</Code>
```

If a different error appears, inspect the actual response rather than assuming a signature mismatch.

---

## 11. Root Cause Analysis

### Incident A — Expiration

**Root cause:** The presigned URL exceeded its valid lifetime.

```text
Presigned URL Generated
         |
         v
X-Amz-Expires = 5
         |
         v
Time Passes
         |
         v
Request Sent After Expiration
         |
         v
HTTP 403 AccessDenied
```

### Incident B — Invalid Signature

**Root cause:** A signed request parameter was altered.

```text
Valid Presigned URL
         |
         v
Signature Modified
         |
         v
S3 Signature Verification
         |
         v
Expected Signature != Received Signature
         |
         v
HTTP 403 SignatureDoesNotMatch
```

### Root Cause Comparison

| Investigation | Expired URL | Modified Signature |
|---|---|---|
| Object exists | Yes | Yes |
| Bucket remains private | Yes | Yes |
| URL originally valid | Yes | Yes |
| Failure cause | Time exceeded | Signature mismatch |
| Typical HTTP status | 403 | 403 |
| Remediation | Generate fresh URL | Regenerate unmodified URL |

---

## 12. Remediate the Signature Mismatch

### Step 1 — Generate a Fresh URL

```bash
export FIXED_URL=$(aws s3 presign \
  "s3://$BUCKET/$OBJECT_KEY" \
  --expires-in 600 \
  --region "$AWS_REGION")
```

### Step 2 — Download the Object

```bash
curl -sS \
  -o recovered-signature-report.txt \
  -w "HTTP Status: %{http_code}\n" \
  "$FIXED_URL"
```

Expected:

```text
HTTP Status: 200
```

### Step 3 — Verify File Integrity

```bash
diff private-report.txt recovered-signature-report.txt
```

No output means the files match.

### Production Considerations

In a real application, also investigate:

- Incorrect signing Region
- Mismatched HTTP methods
- Modified query parameters
- Modified signed headers
- Incorrect `Content-Type` for signed uploads
- Expired temporary credentials
- Clock synchronization
- Reverse proxies altering requests

The signed request must match the request actually sent.

---

## 13. Final Security Verification

### Verify Direct Anonymous Access

```bash
curl -sS -o /dev/null \
  -w "HTTP Status: %{http_code}\n" \
  "$OBJECT_URL"
```

Expected:

```text
HTTP Status: 403
```

### Verify Block Public Access

```bash
aws s3api get-public-access-block \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

All four settings should still be enabled.

### Verify Authenticated Object Access

```bash
aws s3api head-object \
  --bucket "$BUCKET" \
  --key "$OBJECT_KEY" \
  --region "$AWS_REGION"
```

### Verification Summary

| Test | Expected Result |
|---|---|
| Anonymous object download | 403 |
| Valid presigned URL | 200 |
| Expired URL | 403 |
| Tampered URL | 403 |
| Fresh URL after expiration | 200 |
| Fresh URL after signature mismatch | 200 |
| Downloaded content | Matches original |
| Block Public Access | Enabled |

These are the expected results of a successfully completed lab.

---

## 14. Production Engineering Considerations

### Incident Investigation

When users report a presigned URL failure:

1. Identify the exact S3 error code.
2. Determine when the URL was generated.
3. Verify the configured expiration.
4. Check the validity of signing credentials.
5. Verify the bucket Region.
6. Check the URL for modifications.
7. Confirm the signing identity has required S3 permissions.
8. Inspect applicable bucket-policy conditions.
9. Generate a fresh URL.
10. Verify secure access.

### Evidence Collection

Useful evidence includes:

- Sanitized application logs
- S3 error codes
- HTTP response status
- URL creation timestamp
- Configured expiration
- Signing identity
- AWS Region
- CloudTrail S3 data events, if enabled

### Security Best Practices

- Use short expiration periods appropriate for the application.
- Prefer temporary AWS credentials.
- Treat signed URLs as sensitive bearer tokens.
- Avoid logging complete presigned URLs.
- Use HTTPS.
- Keep S3 buckets private.
- Preserve Block Public Access.
- Limit permissions of the signing identity.
- Apply bucket-policy restrictions when necessary.

### Important Security Warning

Anyone with a valid presigned URL may potentially access the signed resource until the URL becomes invalid.

Do not publish full URLs in GitHub, screenshots, README files, monitoring dashboards, or support tickets.

---

## 15. Related S3 Presigned URL Problems

| Error | Possible Cause |
|---|---|
| `AccessDenied` | Missing permissions or expired request |
| `SignatureDoesNotMatch` | Modified signed request |
| `ExpiredToken` | Signing credentials expired |
| `AuthorizationHeaderMalformed` | Signing Region mismatch |
| `NoSuchKey` | Incorrect object key |
| `InvalidAccessKeyId` | Invalid signing access key |
| HTTP 403 | Permission, signature, token, or expiration issue |

---

## 16. Interview Questions and Answers

### Q1. What is an S3 presigned URL?

A presigned URL is a temporary signed link that allows access to a specific S3 operation using the permissions of the signing identity.

### Q2. Does the recipient need AWS credentials?

No. The signed URL contains the necessary temporary request-authentication information.

### Q3. What is the maximum expiration for a SigV4 S3 presigned URL?

Seven days, although temporary credential expiration or policy restrictions may shorten the effective lifetime.

### Q4. Why does a presigned URL return 403?

Possible causes include expiration, invalid signatures, insufficient permissions, or expired temporary credentials.

### Q5. What causes SignatureDoesNotMatch?

The request received by S3 does not match the request signature. This may happen because signed parameters, headers, the HTTP method, or other signed components differ.

### Q6. Can you extend the expiration of an existing presigned URL?

No. Generate a new URL with the intended expiration.

### Q7. Does generating a presigned URL make the bucket public?

No. The bucket can remain private, and the request is authorized through its valid signature.

### Q8. Can a presigned URL stop working before its configured expiration?

Yes. For example, the signing credentials may expire, permissions may change, or a bucket policy may restrict signature age.

### Q9. How do you protect presigned URLs?

Use HTTPS, short lifetimes, least-privilege permissions, and avoid exposing complete URLs in logs or repositories.

### Q10. How would you explain this incident in an interview?

> I investigated an S3 presigned URL download failure where users received HTTP 403. I reproduced an expired URL and a signature mismatch separately, inspected the S3 error responses, and verified the root causes. I regenerated valid URLs, confirmed successful downloads, compared file contents, and verified that the S3 bucket remained private with Block Public Access enabled.

---

## 17. Cleanup

### Step 1 — Clear Presigned URL Variables

```bash
unset VALID_URL
unset SHORT_URL
unset FRESH_URL
unset ORIGINAL_URL
unset TAMPERED_URL
unset FIXED_URL
```

### Step 2 — Remove Temporary Files

```bash
rm -f downloaded-report.txt \
  recovered-expired-report.txt \
  recovered-signature-report.txt \
  expired-response.xml \
  signature-error.xml
```

### Step 3 — Confirm Lab Resources

```bash
echo "$BUCKET"
echo "$OBJECT_KEY"

aws sts get-caller-identity
```

### Step 4 — Inspect S3 Objects

```bash
aws s3 ls "s3://$BUCKET/" \
  --recursive \
  --region "$AWS_REGION"
```

Only proceed if this is your dedicated Lab 11 bucket containing the sample object.

### Step 5 — Delete Test Object

```bash
aws s3api delete-object \
  --bucket "$BUCKET" \
  --key "$OBJECT_KEY" \
  --region "$AWS_REGION"
```

### Step 6 — Delete Bucket

```bash
aws s3api delete-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

These commands assume versioning was not enabled and no unrelated objects were added.

Keep `private-report.txt` for the repository.

---

## 18. Repository Structure

```text
11-s3-presigned-url/
│
├── README.md
└── private-report.txt
```

The presigned URLs are generated dynamically during execution.

Do not store active presigned URLs or temporary credential files in this repository.

---

## 19. Lessons Learned

This lab demonstrated two common causes of Amazon S3 presigned URL failures.

An expired URL fails because it is used outside its validity period.

A modified URL fails because the signature no longer matches the signed request.

The troubleshooting process used AWS CLI, curl, and Python to reproduce both problems, inspect the responses, regenerate valid URLs, and verify successful downloads.

The main lesson is that presigned URL failures should be diagnosed using the specific error response rather than assuming every HTTP 403 is a permissions problem.

---

## 20. Skills Demonstrated

- Amazon S3 troubleshooting
- AWS Signature Version 4
- Presigned URL generation
- HTTP 403 error investigation
- Signature mismatch analysis
- Temporary access management
- AWS CLI v2
- Linux Bash
- curl
- Python 3 URL processing
- File integrity verification
- S3 Block Public Access
- Secure incident remediation
- Production-style documentation

## Final Outcome

| Item | Expected Result |
|---|---|
| Incident | INC-S3-011 |
| Service | Amazon S3 |
| Failure A | Expired presigned URL |
| Failure B | SignatureDoesNotMatch |
| Root Causes | Expiration and altered signature |
| Remediation | Generate fresh, unmodified URLs |
| Functional Verification | HTTP 200 |
| Security Verification | Anonymous access denied |
| Bucket Public Access | Blocked |
| Expected Lab Status | Resolved |

**Key Takeaway:** When an S3 presigned URL returns 403, investigate expiration, signing credentials, request parameters, and permissions independently. Preserve private S3 access while restoring the intended temporary download functionality.
