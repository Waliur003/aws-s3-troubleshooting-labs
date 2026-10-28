# Lab 06 — Amazon S3 Static Website Returns 404 Not Found

## Overview

This lab demonstrates how to troubleshoot an Amazon S3 static website that returns `404 Not Found` because of an incorrectly configured index document.

In this scenario, static website hosting is enabled, and the website file exists in the S3 bucket. However, the uploaded filename is `Index.html`, while the website configuration expects `index.html`.

Amazon S3 object keys are case-sensitive, so these names refer to different objects.

The lab follows a production-inspired troubleshooting process:

**Establish Baseline → Reproduce Failure → Collect Evidence → Identify Root Cause → Remediate → Verify → Cleanup**

## Lab Information

| Item | Details |
|---|---|
| AWS Service | Amazon S3 |
| Incident ID | INC-S3-006 |
| Difficulty | Beginner–Intermediate |
| Error | HTTP 404 Not Found |
| Feature | S3 Static Website Hosting |
| Environment | Ubuntu Linux (WSL2) |
| Tools | AWS CLI v2, Bash, curl, grep |
| Root Cause | Case-sensitive index document mismatch |
| Remediation | Upload the correct `index.html` |
| Expected Result | HTTP 200 OK |

---

## 1. Production Incident Scenario

### Incident Description

An application support team reports that users cannot access a static website hosted on Amazon S3.

The S3 bucket exists, and static website hosting has been enabled.

However, users receive:

```text
HTTP/1.1 404 Not Found
```

### Expected Behavior

When users open the S3 website endpoint, the homepage should load.

```text
http://BUCKET_NAME.s3-website-us-east-1.amazonaws.com/
```

### Actual Behavior

The browser receives a `404 Not Found` response instead of the homepage.

### Potential Business Impact

- Users cannot open the website.
- Application documentation or static content becomes unavailable.
- Customer-facing links may fail.
- Downstream integrations depending on the website may stop working.

The severity of a real incident depends on the business importance of the affected website.

---

## 2. Architecture

### Broken Website Architecture

```text
User / Browser / curl
         |
         | HTTP GET /
         v
   S3 Website Endpoint
         |
         v
 Website Configuration
 IndexDocument: index.html
         |
         v
    S3 Bucket
         |
         v
 Object: Index.html
         |
         X
 Exact Object Key Missing
         |
         v
   HTTP 404 Not Found
```

### Working Website Architecture

```text
User / Browser / curl
         |
         | HTTP GET /
         v
   S3 Website Endpoint
         |
         v
 Website Configuration
 IndexDocument: index.html
         |
         v
    S3 Bucket
         |
         v
 Object: index.html
         |
         v
     HTTP 200 OK
         |
         v
   Website Displayed
```

### Root Cause Comparison

| Component | Configured Value | Actual Value |
|---|---|---|
| Website index document | `index.html` | — |
| Uploaded object | — | `Index.html` |
| Case-sensitive match | Required | No |
| Result | — | 404 Not Found |

---

## 3. Prerequisites

Required tools:

- AWS account with permission to manage an isolated S3 bucket
- AWS CLI v2
- Ubuntu Linux / WSL2
- Bash terminal
- curl
- Git and GitHub

The direct S3 website endpoint requires public read access to serve anonymous users.

For this lab, use an isolated disposable bucket containing only harmless test HTML. Do not weaken account-wide or organization-wide public access restrictions.

For production environments, the preferred architecture is generally a private S3 bucket behind Amazon CloudFront with Origin Access Control and HTTPS.

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

export BUCKET="cloud-lab06-${ACCOUNT_ID}"
```

Verify:

```bash
echo "Region: $AWS_REGION"
echo "Bucket: $BUCKET"
```

---

## 4. Create the Working Environment

### Step 1 — Create S3 Bucket

```bash
aws s3api create-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

For `us-east-1`, the creation request does not require a `LocationConstraint`.

If the name is unavailable, choose another unique lab bucket name. Never reuse a shared or production bucket.

### Step 2 — Verify the Bucket

```bash
aws s3api head-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

A successful response normally produces no output.

### Step 3 — Create the HTML Document

Create a file called `Index.html`:

```bash
cat > Index.html <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Cloud Engineering Lab 06</title>
</head>
<body>
  <h1>Welcome to S3 Troubleshooting Lab 06</h1>
  <p>Testing S3 static website hosting.</p>
</body>
</html>
EOF
```

Verify:

```bash
cat Index.html
```

### Step 4 — Upload the HTML File

```bash
aws s3 cp Index.html \
  "s3://$BUCKET/Index.html" \
  --content-type "text/html" \
  --region "$AWS_REGION"
```

Verify:

```bash
aws s3 ls "s3://$BUCKET/" \
  --region "$AWS_REGION"
```

Expected key:

```text
Index.html
```

---

## 5. Configure Static Website Hosting

### Step 1 — Create Website Configuration

Create `website-config.json`:

```bash
cat > website-config.json <<'EOF'
{
  "IndexDocument": {
    "Suffix": "index.html"
  },
  "ErrorDocument": {
    "Key": "error.html"
  }
}
EOF
```

The `error.html` file is not uploaded in this lab. It is optional for understanding the index-document failure, and a missing custom error document can affect the appearance of the error response.

### Step 2 — Enable Website Hosting

```bash
aws s3api put-bucket-website \
  --bucket "$BUCKET" \
  --website-configuration file://website-config.json \
  --region "$AWS_REGION"
```

### Step 3 — Verify Configuration

```bash
aws s3api get-bucket-website \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

Expected index document:

```json
{
  "IndexDocument": {
    "Suffix": "index.html"
  }
}
```

The website configuration expects lowercase `index.html`, but the actual object is uppercase `Index.html`.

---

## 6. Configure Temporary Website Read Access

### Security Warning

S3 website endpoints serve content over HTTP and need public read access for anonymous visitors.

Only perform this exercise using an isolated lab bucket containing non-sensitive test content.

Do not disable account-wide or organization-wide public access protections.

### Step 1 — Inspect Public Access Settings

```bash
aws s3api get-public-access-block \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

Check account-level protection:

```bash
aws s3control get-public-access-block \
  --account-id "$ACCOUNT_ID" \
  --region "$AWS_REGION"
```

If higher-level restrictions prevent public website hosting, do not override them. Use a private S3 bucket with CloudFront OAC for a production-style alternative.

### Step 2 — Check Existing Bucket Policy

```bash
aws s3api get-bucket-policy \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

A new bucket without a policy may return `NoSuchBucketPolicy`.

Proceed only when no existing policy needs to be preserved.

### Step 3 — Configure Bucket-Level Settings

```bash
aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=false,RestrictPublicBuckets=false" \
  --region "$AWS_REGION"
```

This modifies only the isolated bucket's settings, not account-level protections.

### Step 4 — Create a Scoped Bucket Policy

Create `website-policy.json`:

```bash
cat > website-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Lab06PublicIndexRead",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": [
        "arn:aws:s3:::$BUCKET/Index.html",
        "arn:aws:s3:::$BUCKET/index.html"
      ]
    }
  ]
}
EOF
```

This permits anonymous reads of only the two specified HTML object keys.

### Step 5 — Apply Bucket Policy

```bash
aws s3api put-bucket-policy \
  --bucket "$BUCKET" \
  --policy file://website-policy.json \
  --region "$AWS_REGION"
```

If the operation is rejected by security restrictions, stop and preserve those restrictions.

---

## 7. Reproduce the 404 Incident

### Step 1 — Configure Website URL

```bash
export WEBSITE_URL="http://${BUCKET}.s3-website-${AWS_REGION}.amazonaws.com"
```

Verify:

```bash
echo "$WEBSITE_URL"
```

### Step 2 — Send HTTP Request

```bash
curl -sS \
  -D response-headers.txt \
  -o response-body.html \
  -w "HTTP Status: %{http_code}\n" \
  "$WEBSITE_URL/"
```

### Expected Result

```text
HTTP Status: 404
```

### Step 3 — Inspect HTTP Headers

```bash
cat response-headers.txt
```

### Step 4 — Inspect Response Body

```bash
cat response-body.html
```

Depending on error-document configuration, the response may contain an S3 error message or an error page.

**Troubleshooting note:** If you receive `403` instead of `404`, investigate the public-read policy, applicable Block Public Access settings, and object permissions before diagnosing a missing index document.

---

## 8. Troubleshooting Investigation

### Check 1 — Verify AWS Identity

```bash
aws sts get-caller-identity
```

### Check 2 — Verify Uploaded Objects

```bash
aws s3 ls "s3://$BUCKET/" \
  --region "$AWS_REGION"
```

Expected:

```text
Index.html
```

### Check 3 — Inspect Website Configuration

```bash
aws s3api get-bucket-website \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

Expected:

```text
IndexDocument: index.html
```

### Check 4 — Verify Actual Object

```bash
aws s3api head-object \
  --bucket "$BUCKET" \
  --key "Index.html" \
  --region "$AWS_REGION"
```

This should return object metadata.

### Check 5 — Verify Expected Index Document

```bash
aws s3api head-object \
  --bucket "$BUCKET" \
  --key "index.html" \
  --region "$AWS_REGION"
```

Before remediation, the expected object does not exist.

With sufficient permissions, the request can return `404 Not Found`.

### Check 6 — Compare Names

```text
Configured: index.html
Uploaded:   Index.html
```

### Investigation Finding

S3 object keys are case-sensitive.

The website is configured to look for a lowercase filename, but the uploaded filename begins with an uppercase letter.

The requested index object therefore does not exist.

---

## 9. Root Cause Analysis

### Root Cause

The index document specified in the S3 website configuration does not exactly match the uploaded object key.

### Technical Explanation

The configured index document is:

```text
index.html
```

The actual object key is:

```text
Index.html
```

Because S3 treats these as different keys, the website endpoint cannot locate the configured homepage.

### Root Cause Flow

```text
HTTP GET /
     |
     v
S3 Website Endpoint
     |
     v
Configured Index: index.html
     |
     v
S3 Object Lookup
     |
     v
Only Index.html Exists
     |
     v
HTTP 404 Not Found
```

### Five Whys

1. **Why did the website return 404?** The configured index document could not be found.
2. **Why was the index document missing?** The object key did not exactly match the configured name.
3. **Why did the names differ?** The uploaded filename used uppercase `I`.
4. **Why was the incorrect filename present?** The lab deliberately introduced the mismatch.
5. **How can this be prevented?** Validate artifact filenames and website configuration during deployment.

---

## 10. Remediation

### Step 1 — Create the Correct Index File

```bash
cp Index.html index.html
```

Verify:

```bash
ls -l *.html
```

Both files should appear.

### Step 2 — Upload Corrected File

```bash
aws s3 cp index.html \
  "s3://$BUCKET/index.html" \
  --content-type "text/html" \
  --region "$AWS_REGION"
```

### Step 3 — Verify Object Exists

```bash
aws s3api head-object \
  --bucket "$BUCKET" \
  --key "index.html" \
  --region "$AWS_REGION"
```

### Step 4 — List Objects

```bash
aws s3 ls "s3://$BUCKET/" \
  --region "$AWS_REGION"
```

The bucket should now contain:

```text
Index.html
index.html
```

---

## 11. Verify Website Recovery

### Step 1 — Retry the Original Request

```bash
curl -sS \
  -D fixed-headers.txt \
  -o fixed-response.html \
  -w "HTTP Status: %{http_code}\n" \
  "$WEBSITE_URL/"
```

### Expected Result

```text
HTTP Status: 200
```

### Step 2 — Inspect Response

```bash
cat fixed-headers.txt
```

### Step 3 — Verify Website Content

```bash
grep "Welcome to S3 Troubleshooting Lab 06" \
  fixed-response.html
```

Expected content:

```html
<h1>Welcome to S3 Troubleshooting Lab 06</h1>
```

### Step 4 — Verify Response Status

```bash
curl -sS -o /dev/null \
  -w "%{http_code}\n" \
  "$WEBSITE_URL/"
```

Expected:

```text
200
```

### Final Verification Summary

| Check | Expected Result |
|---|---|
| Website hosting enabled | Pass |
| Incorrect index document reproduced | 404 |
| Actual object key identified | `Index.html` |
| Configured index document | `index.html` |
| Corrected object uploaded | Pass |
| Website HTTP response | 200 |
| Homepage content verified | Pass |

The incident is resolved when the same website endpoint successfully serves the intended homepage.

---

## 12. Production Engineering Considerations

### Incident Triage

Investigate:

- Is the issue affecting all website visitors?
- Is the S3 website endpoint correct?
- Is static website hosting enabled?
- What HTTP status is returned?
- Does the configured index document exist?
- Are object names case-sensitive matches?
- Did a recent deployment change filenames?

### Evidence Collection

Useful tools include:

- AWS CLI
- curl
- Application or deployment logs
- S3 website configuration
- S3 object metadata
- Bucket policy inspection
- Infrastructure as Code configuration

### Important Difference: 403 vs 404

| Error | Investigation |
|---|---|
| 403 Forbidden | Public access, identity/resource policies, authorization |
| 404 Not Found | Missing object, index configuration, wrong key |
| 301 Redirect | Endpoint or request routing |
| 200 OK | Request succeeded |

A `403` may also occur when S3 does not disclose that an object is missing. Always interpret the result in context.

### Production Security Design

For a production website, consider:

```text
Users
   |
   v
HTTPS
   |
   v
Amazon CloudFront
   |
   v
Origin Access Control
   |
   v
Private S3 Bucket
```

This architecture avoids exposing the origin bucket publicly and supports HTTPS through CloudFront.

### Preventive Controls

- Validate filenames during CI/CD.
- Check that the configured index document exists.
- Use consistent lowercase filenames.
- Add HTTP health checks.
- Test website endpoints after deployment.
- Monitor unexpected 4xx responses.
- Use Infrastructure as Code for website configuration.
- Apply least-privilege permissions.

---

## 13. Related S3 Website Errors

| Error | Possible Cause |
|---|---|
| `404 Not Found` | Missing index or object key |
| `403 AccessDenied` | Public-read permission missing or denied |
| `NoSuchBucket` | Incorrect bucket name |
| `PermanentRedirect` | Endpoint or Region mismatch |
| Incorrect content rendering | Incorrect `Content-Type` |
| HTTPS connection failure | Direct S3 website endpoints do not support HTTPS |
| Custom domain not resolving | DNS configuration issue |

---

## 14. Interview Questions and Answers

### Q1. Why does an S3 static website return 404?

A common cause is a missing object or an index document whose configured filename does not match the uploaded object key.

### Q2. Are S3 object filenames case-sensitive?

Yes. `Index.html` and `index.html` are two different S3 object keys.

### Q3. What is the difference between S3 website 403 and 404?

A 403 usually indicates that the request is not authorized.

A 404 usually indicates that the requested website object could not be found.

Permission settings can affect which response is returned, so both the configuration and the actual HTTP response must be checked.

### Q4. How can you check S3 website configuration?

Use:

```bash
aws s3api get-bucket-website --bucket BUCKET_NAME
```

### Q5. How can you inspect a website's HTTP response?

Use:

```bash
curl -I http://WEBSITE_ENDPOINT
```

Or capture the complete headers and body using `curl -D` and `-o`.

### Q6. Does enabling static website hosting automatically make objects public?

No. Website hosting configuration does not automatically grant anonymous read permissions.

### Q7. Does an S3 website endpoint support HTTPS?

No. Direct S3 website endpoints support HTTP. CloudFront can provide HTTPS in front of S3.

### Q8. Should a production S3 bucket be publicly accessible?

Generally, private S3 with CloudFront OAC is preferred for production static website delivery.

### Q9. What should you do if an account-level Block Public Access setting prevents the lab?

Do not weaken organization or account security restrictions. Use an approved testing environment or a private bucket with CloudFront OAC.

### Q10. How would you prevent this incident?

I would validate index filenames, automate checks in deployment pipelines, test website endpoints after deployment, and manage configuration through reviewed infrastructure changes.

---

## 15. Cleanup and Security Restoration

### Step 1 — Remove Lab Public-Read Policy

```bash
aws s3api delete-bucket-policy \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

Only do this because the entire policy was created exclusively for this isolated exercise.

### Step 2 — Restore Bucket Public Access Protection

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

All four settings should be `true`.

### Step 3 — Verify Lab Bucket Contents

```bash
echo "$BUCKET"

aws s3 ls "s3://$BUCKET/" \
  --recursive \
  --region "$AWS_REGION"
```

Confirm the bucket contains only the test files.

### Step 4 — Remove S3 Objects

```bash
aws s3 rm "s3://$BUCKET/" \
  --recursive \
  --region "$AWS_REGION"
```

### Step 5 — Delete Website Configuration

```bash
aws s3api delete-bucket-website \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

### Step 6 — Delete Bucket

```bash
aws s3api delete-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

These cleanup steps assume no versioned objects, unrelated data, or other dependencies remain.

### Step 7 — Remove Temporary Local Files

```bash
rm -f response-headers.txt \
  response-body.html \
  fixed-headers.txt \
  fixed-response.html
```

Keep the HTML and JSON configuration examples for GitHub documentation.

---

## 16. Repository Structure

```text
06-s3-website-404/
│
├── README.md
├── Index.html
├── index.html
├── website-config.json
└── website-policy.json
```

No AWS credentials, temporary debug logs, or sensitive data should be committed.

The website policy is provided for a controlled educational exercise. It must not be deployed to a production bucket without appropriate security review.

---

## 17. Lessons Learned

This lab demonstrates that an S3 static website can return `404 Not Found` even when the bucket exists and website hosting is correctly enabled.

The failure was caused by a mismatch between the configured index document and the actual uploaded object key.

The troubleshooting process included inspecting website configuration, verifying S3 object keys, checking HTTP responses, applying the correct filename, and confirming successful website recovery.

It also demonstrated the security considerations of S3 static website hosting and the importance of restoring public access protections after testing.

---

## 18. Skills Demonstrated

- Amazon S3 troubleshooting
- Static website hosting
- Linux Bash
- AWS CLI v2
- HTTP status analysis
- curl diagnostics
- S3 object key validation
- Bucket policy troubleshooting
- Root cause analysis
- Safe remediation
- Website availability verification
- Cloud security awareness
- Production incident documentation

---

## Final Outcome

| Item | Result |
|---|---|
| Incident | INC-S3-006 |
| Service | Amazon S3 |
| Issue | Static website returned HTTP 404 |
| Root Cause | `Index.html` / `index.html` mismatch |
| Remediation | Uploaded correct `index.html` |
| Verification | HTTP 200 and expected HTML content |
| Security Cleanup | Public-read policy removed and protections restored |
| Expected Lab Status | Resolved |

**Key Takeaway:** When an S3 static website returns 404, verify the website configuration and exact index document key before changing permissions or rebuilding infrastructure.
