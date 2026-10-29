# Lab 10 — Amazon S3 CORS Configuration Error

## Overview

This hands-on lab demonstrates how to troubleshoot a Cross-Origin Resource Sharing (CORS) configuration error in Amazon S3.

The scenario simulates a frontend application running at `http://localhost:3000` that attempts to access an S3 object. However, the bucket's CORS configuration only allows `http://localhost:4000`.

Because the origin does not match, S3 rejects the browser-style preflight request with `403 Forbidden`.

The objective is to reproduce the failure, investigate the CORS configuration, identify the incorrect origin, apply a secure correction, and verify successful preflight requests.

**Troubleshooting workflow:**

Establish Baseline → Introduce Failure → Reproduce → Investigate → Identify Root Cause → Remediate → Verify → Cleanup

## Lab Information

| Item | Details |
|---|---|
| AWS Service | Amazon S3 |
| Incident ID | INC-S3-010 |
| Difficulty | Intermediate |
| Error | HTTP 403 — CORS Request Not Allowed |
| Feature | Cross-Origin Resource Sharing |
| Environment | Ubuntu Linux (WSL2) |
| Tools | AWS CLI v2, Bash, curl |
| Frontend Origin | `http://localhost:3000` |
| Incorrect Allowed Origin | `http://localhost:4000` |
| Root Cause | Incorrect `AllowedOrigins` configuration |
| Remediation | Configure the correct frontend origin |
| Security Requirement | Keep the S3 bucket private |

---

## 1. Production Incident Scenario

### Incident Description

A frontend development team reports that their application cannot communicate with an S3 bucket.

The application runs at:

```text
http://localhost:3000
```

The S3 bucket contains a JSON file that the application needs to access.

Although the file exists, browser requests fail because the CORS configuration does not permit the application's origin.

### Reported Error

```text
Access to fetch has been blocked by CORS policy:
No 'Access-Control-Allow-Origin' header is present.
```

A browser's developer tools may show:

```text
CORS preflight request failed
HTTP 403 Forbidden
```

### Expected Behavior

The browser's preflight request should be accepted for the application's authorized origin, method, and request headers.

### Actual Behavior

The S3 endpoint rejects the preflight request because the origin is not allowed.

### Potential Business Impact

- Frontend applications cannot complete cross-origin requests.
- File uploads or downloads may fail.
- Application features may become unavailable.
- Development and production deployments may be delayed.

---

## 2. Architecture

### Broken Configuration

```text
Frontend Application
http://localhost:3000
          |
          | OPTIONS Preflight
          v
      Amazon S3
          |
          v
    S3 CORS Rules
          |
          v
AllowedOrigins:
http://localhost:4000
          |
          v
Origin Does Not Match
          |
          v
    HTTP 403 Forbidden
          |
          v
Browser Blocks Cross-Origin Request
```

### Fixed Configuration

```text
Frontend Application
http://localhost:3000
          |
          | OPTIONS Preflight
          v
      Amazon S3
          |
          v
    S3 CORS Rules
          |
          v
AllowedOrigins:
http://localhost:3000
          |
          v
Origin, Method, Headers Match
          |
          v
       HTTP 200
          |
          v
Preflight Accepted
```

**Important:** Successful preflight authorization does not automatically grant permission to retrieve a private S3 object.

Object access is evaluated separately using applicable AWS permissions.

---

## 3. Understanding CORS

CORS stands for Cross-Origin Resource Sharing.

It allows a server to specify which website origins can access its resources through browser JavaScript.

An origin consists of:

- Protocol
- Hostname
- Port

For example:

```text
http://localhost:3000
```

and

```text
http://localhost:4000
```

are different origins.

### Important CORS Configuration Fields

| Field | Purpose |
|---|---|
| `AllowedOrigins` | Specifies permitted frontend origins |
| `AllowedMethods` | Specifies permitted request methods |
| `AllowedHeaders` | Specifies permitted preflight request headers |
| `ExposeHeaders` | Specifies response headers accessible to JavaScript |
| `MaxAgeSeconds` | Controls browser preflight caching duration |

### What Is an HTTP Preflight Request?

A browser sends an HTTP `OPTIONS` request before certain cross-origin requests.

The preflight asks whether the server allows the intended request.

Example:

```http
OPTIONS /data.json HTTP/1.1
Origin: http://localhost:3000
Access-Control-Request-Method: GET
Access-Control-Request-Headers: content-type
```

The server checks whether the origin, method, and headers match its CORS configuration.

### CORS vs IAM Permissions

| CORS | IAM / Bucket Policy |
|---|---|
| Controls browser cross-origin access to responses | Controls authorization to AWS resources |
| Evaluates HTTP origin and method | Evaluates principal, action, resource, conditions |
| Can reject a preflight request | Can deny S3 object operations |
| Does not grant S3 object permission | Grants or restricts S3 permissions |

---

## 4. Prerequisites

Required:

- AWS account
- AWS CLI v2
- Ubuntu Linux / WSL2
- Bash
- curl
- Permission to manage an isolated S3 bucket
- Permission to configure bucket CORS
- Git and GitHub

The bucket remains private throughout this exercise.

### Verify AWS CLI

```bash
aws --version
```

### Verify Identity

```bash
aws sts get-caller-identity
```

### Configure Variables

```bash
export AWS_REGION="us-east-1"

export ACCOUNT_ID=$(aws sts get-caller-identity \
  --query Account --output text)

export BUCKET="cloud-lab10-${ACCOUNT_ID}"

export FRONTEND_ORIGIN="http://localhost:3000"

export WRONG_ORIGIN="http://localhost:4000"
```

Verify:

```bash
echo "Region: $AWS_REGION"
echo "Bucket: $BUCKET"
echo "Frontend: $FRONTEND_ORIGIN"
echo "Wrong Origin: $WRONG_ORIGIN"
```

---

## 5. Create the Working Environment

### Step 1 — Create S3 Bucket

First check whether the bucket already exists:

```bash
aws s3api head-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

Only create a bucket if the name is available and it is not used by another environment.

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

### Step 3 — Create Sample Data

Create `data.json`:

```bash
cat > data.json <<'EOF'
{
  "application": "Cloud Engineering Lab 10",
  "service": "Amazon S3",
  "status": "healthy"
}
EOF
```

### Step 4 — Upload Sample Data

```bash
aws s3 cp data.json \
  "s3://$BUCKET/data.json" \
  --content-type "application/json" \
  --region "$AWS_REGION"
```

### Step 5 — Verify Object

```bash
aws s3api head-object \
  --bucket "$BUCKET" \
  --key "data.json" \
  --region "$AWS_REGION"
```

The successful upload and HEAD request establish a working authenticated baseline.

---

## 6. Introduce the CORS Misconfiguration

### Step 1 — Create Broken CORS Rules

Create `broken-cors.json`:

```bash
cat > broken-cors.json <<'EOF'
{
  "CORSRules": [
    {
      "AllowedOrigins": [
        "http://localhost:4000"
      ],
      "AllowedMethods": [
        "GET",
        "HEAD"
      ],
      "AllowedHeaders": [
        "content-type"
      ],
      "MaxAgeSeconds": 300
    }
  ]
}
EOF
```

### Step 2 — Apply Broken Configuration

```bash
aws s3api put-bucket-cors \
  --bucket "$BUCKET" \
  --cors-configuration file://broken-cors.json \
  --region "$AWS_REGION"
```

### Step 3 — Verify Configuration

```bash
aws s3api get-bucket-cors \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

Expected allowed origin:

```text
http://localhost:4000
```

### Identify the Mistake

The actual frontend uses:

```text
http://localhost:3000
```

But the bucket allows:

```text
http://localhost:4000
```

The values do not match.

---

## 7. Reproduce the CORS Failure

### Step 1 — Set the Object URL

```bash
export OBJECT_URL="https://${BUCKET}.s3.${AWS_REGION}.amazonaws.com/data.json"
```

Verify:

```bash
echo "$OBJECT_URL"
```

### Step 2 — Send a Preflight Request

```bash
curl -sS -i -X OPTIONS "$OBJECT_URL" \
  -H "Origin: $FRONTEND_ORIGIN" \
  -H "Access-Control-Request-Method: GET" \
  -H "Access-Control-Request-Headers: content-type"
```

### Expected Result

```text
HTTP/1.1 403 Forbidden
```

The response may contain:

```text
CORSResponse: This CORS request is not allowed
```

The exact response body may vary.

### Why the Request Failed

The request's origin is `http://localhost:3000`.

The S3 CORS configuration only permits `http://localhost:4000`.

Therefore, no applicable CORS rule matches the request.

---

## 8. Troubleshooting Investigation

### Check 1 — Confirm AWS Identity

```bash
aws sts get-caller-identity
```

### Check 2 — Verify Object Exists

```bash
aws s3api head-object \
  --bucket "$BUCKET" \
  --key "data.json" \
  --region "$AWS_REGION"
```

### Check 3 — Inspect CORS Rules

```bash
aws s3api get-bucket-cors \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

### Check 4 — Compare Origins

```bash
echo "Requested Origin: $FRONTEND_ORIGIN"
echo "Allowed Origin: $WRONG_ORIGIN"
```

### Check 5 — Inspect Request Method and Headers

The preflight specifies:

```text
Access-Control-Request-Method: GET
Access-Control-Request-Headers: content-type
```

The CORS rule permits:

```text
AllowedMethods: GET, HEAD
AllowedHeaders: content-type
```

These values match.

The origin is the failing component.

### Investigation Summary

| Check | Finding |
|---|---|
| S3 bucket | Exists |
| S3 object | Exists |
| Authenticated access | Works |
| Requested origin | localhost:3000 |
| Allowed origin | localhost:4000 |
| HTTP method | GET — allowed |
| Requested header | content-type — allowed |
| Root cause | Origin mismatch |

---

## 9. Root Cause Analysis

### Root Cause

The S3 CORS rule specifies an incorrect frontend origin.

### Technical Explanation

The application sends a browser-style request with:

```text
Origin: http://localhost:3000
```

The configured rule contains:

```json
"AllowedOrigins": [
  "http://localhost:4000"
]
```

S3 cannot find a matching rule for the origin, method, and headers.

The preflight therefore fails.

### Root Cause Flow

```text
Frontend Browser
       |
       v
OPTIONS Request
Origin: localhost:3000
       |
       v
S3 CORS Evaluation
       |
       v
Allowed Origin:
localhost:4000
       |
       v
No Matching Rule
       |
       v
HTTP 403 Forbidden
```

### Five Whys

1. **Why did the browser request fail?** The CORS preflight was rejected.
2. **Why was the preflight rejected?** No CORS rule matched the origin.
3. **Why did the origin not match?** The bucket allowed port 4000 instead of port 3000.
4. **Why was the wrong port configured?** The lab deliberately introduced a configuration mistake.
5. **How can this be prevented?** Validate frontend origins and test preflight requests during deployment.

---

## 10. Remediation

### Step 1 — Create Correct CORS Configuration

Create `fixed-cors.json`:

```bash
cat > fixed-cors.json <<'EOF'
{
  "CORSRules": [
    {
      "AllowedOrigins": [
        "http://localhost:3000"
      ],
      "AllowedMethods": [
        "GET",
        "HEAD"
      ],
      "AllowedHeaders": [
        "content-type"
      ],
      "MaxAgeSeconds": 300
    }
  ]
}
EOF
```

### Step 2 — Apply Corrected Configuration

```bash
aws s3api put-bucket-cors \
  --bucket "$BUCKET" \
  --cors-configuration file://fixed-cors.json \
  --region "$AWS_REGION"
```

### Step 3 — Verify Updated Rules

```bash
aws s3api get-bucket-cors \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

Expected:

```text
AllowedOrigins: http://localhost:3000
```

### Security Improvement

The rule permits only the required frontend origin.

It does not use a broad wildcard origin or grant unnecessary request methods.

---

## 11. Verify Successful Remediation

### Test 1 — Repeat Original Preflight

```bash
curl -sS -i -X OPTIONS "$OBJECT_URL" \
  -H "Origin: $FRONTEND_ORIGIN" \
  -H "Access-Control-Request-Method: GET" \
  -H "Access-Control-Request-Headers: content-type"
```

Expected:

```text
HTTP/1.1 200 OK
Access-Control-Allow-Origin: http://localhost:3000
```

The response should also include the allowed method and header information.

This verifies that the corrected CORS configuration accepts the preflight.

### Test 2 — Verify Unauthorized Origin Is Rejected

```bash
curl -sS -i -X OPTIONS "$OBJECT_URL" \
  -H "Origin: $WRONG_ORIGIN" \
  -H "Access-Control-Request-Method: GET" \
  -H "Access-Control-Request-Headers: content-type"
```

Expected:

```text
HTTP/1.1 403 Forbidden
```

This shows that the original incorrect origin remains excluded.

### Test 3 — Verify Anonymous Object Access Remains Restricted

```bash
curl -sS -o /dev/null \
  -w "HTTP Status: %{http_code}\n" \
  "$OBJECT_URL"
```

Expected for this private bucket:

```text
HTTP Status: 403
```

### Test 4 — Verify Authenticated Access

```bash
aws s3api get-object \
  --bucket "$BUCKET" \
  --key "data.json" \
  verified-data.json \
  --region "$AWS_REGION"
```

### Test 5 — Verify File Integrity

```bash
diff data.json verified-data.json
```

No output means the files match.

### Verification Summary

| Test | Expected Result |
|---|---|
| Broken preflight | 403 |
| Corrected preflight | 200 |
| Allowed Origin header | localhost:3000 |
| Incorrect origin | Rejected |
| Anonymous GetObject | 403 |
| Authenticated GetObject | Success |
| File integrity | Verified |
| S3 bucket public access | Remains blocked |

**Important:** The preflight test proves the CORS rule works. It does not prove that a real browser can download the private object without valid authorization.

A complete browser integration would require an authorized request mechanism such as a presigned URL.

---

## 12. Production Engineering Considerations

### Incident Triage

Determine:

- Which frontend application is affected?
- What is its exact origin?
- Which HTTP method is being used?
- Which request headers are included?
- Is the browser sending a preflight request?
- Does S3 have a matching CORS rule?
- Does the application also have valid S3 authorization?
- Was the CORS configuration recently changed?

### Evidence Collection

Useful tools include:

- Browser Developer Tools
- Network tab
- AWS CLI
- curl
- S3 CORS configuration
- Application logs
- Deployment configuration
- Infrastructure as Code

### Safe Remediation

A production Cloud Engineer should:

1. Inspect the exact browser request.
2. Identify the origin, HTTP method, and requested headers.
3. Compare them against the S3 CORS configuration.
4. Identify the mismatched setting.
5. Apply a minimal correction.
6. Reproduce the same request.
7. Verify the appropriate CORS response headers.
8. Confirm S3 authorization still works as intended.
9. Test that unauthorized origins remain excluded.
10. Document the incident.

### Recommended Security Practices

- Avoid wildcard origins unless specifically required.
- Permit only required HTTP methods.
- Limit allowed request headers.
- Keep S3 Block Public Access enabled.
- Use application-specific authorization mechanisms.
- Review CORS changes through CI/CD.
- Test frontend integration after deployment.

---

## 13. Related CORS Problems

| Problem | Possible Cause |
|---|---|
| CORS preflight 403 | Origin not allowed |
| CORS preflight 403 | Method not allowed |
| CORS preflight 403 | Requested header not allowed |
| Missing Allow-Origin header | No matching CORS rule |
| GET object 403 | Missing S3 authorization |
| Browser fails but curl succeeds | curl does not enforce browser CORS rules |
| CORS succeeds but download fails | S3 access permission denied |
| CORS works locally but not in production | Different frontend origin |

---

## 14. Interview Questions and Answers

### Q1. What is CORS?

CORS stands for Cross-Origin Resource Sharing. It allows a server to specify which origins may access its responses through browser JavaScript.

### Q2. What is a preflight request?

A preflight is an HTTP OPTIONS request used by browsers to check whether a cross-origin request is permitted.

### Q3. What are the main S3 CORS configuration fields?

`AllowedOrigins`, `AllowedMethods`, `AllowedHeaders`, `ExposeHeaders`, and `MaxAgeSeconds`.

### Q4. Why did the preflight fail in this lab?

The frontend used `localhost:3000`, while S3 allowed only `localhost:4000`.

### Q5. Does CORS grant S3 object permissions?

No. CORS does not replace IAM policies, bucket policies, or other AWS authorization mechanisms.

### Q6. Why can curl access a resource when browser JavaScript cannot?

curl does not enforce the browser's same-origin security policy. A browser evaluates CORS rules before exposing cross-origin responses to JavaScript.

### Q7. Does every browser GET request require a preflight?

No. Certain simple requests do not require a preflight. Custom headers and other request characteristics can trigger one.

### Q8. How do you test S3 CORS?

Use browser Developer Tools or send an OPTIONS request with Origin, Access-Control-Request-Method, and Access-Control-Request-Headers.

### Q9. Is `AllowedOrigins: ["*"]` always recommended?

No. Allowing all origins is broader than necessary for many applications. Exact origins are preferable when requirements are known.

### Q10. How would you explain this incident in an interview?

> A frontend application failed to access an S3 resource because its CORS preflight was rejected. I inspected the Origin, requested HTTP method, and request headers using curl. I compared them against the bucket's CORS configuration and identified that the allowed origin used the wrong port. I corrected AllowedOrigins, verified the preflight returned 200, tested that another origin remained rejected, and confirmed the bucket's private access controls were unchanged.

---

## 15. Cleanup

Only delete resources that belong to this isolated lab.

### Step 1 — Verify Bucket

```bash
echo "$BUCKET"

aws sts get-caller-identity
```

### Step 2 — Remove CORS Configuration

```bash
aws s3api delete-bucket-cors \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

### Step 3 — Verify CORS Removal

```bash
aws s3api get-bucket-cors \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

A `NoSuchCORSConfiguration` error is expected.

### Step 4 — Inspect Objects

```bash
aws s3 ls "s3://$BUCKET/" \
  --recursive \
  --region "$AWS_REGION"
```

### Step 5 — Delete Test Object

```bash
aws s3 rm "s3://$BUCKET/data.json" \
  --region "$AWS_REGION"
```

### Step 6 — Delete Bucket

```bash
aws s3api delete-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

These instructions assume versioning was not enabled and no unrelated objects were added.

### Step 7 — Remove Temporary Local File

```bash
rm -f verified-data.json
```

Keep the example CORS configuration and data files for GitHub.

---

## 16. Repository Structure

```text
10-s3-cors-error/
│
├── README.md
├── data.json
├── broken-cors.json
└── fixed-cors.json
```

The repository contains only the educational example files.

Do not commit AWS credentials, tokens, or sensitive application data.

---

## 17. Lessons Learned

This lab demonstrates how an incorrect S3 CORS configuration can cause a frontend application's cross-origin request to fail.

The problem was caused by a mismatch between the frontend origin and the origin permitted by S3.

The investigation used AWS CLI to inspect the CORS rules and curl to reproduce the browser-style preflight request.

After correcting AllowedOrigins, the preflight request succeeded while requests from an unauthorized origin continued to fail.

The main lesson is to troubleshoot CORS separately from AWS authorization and apply only the minimum configuration required by the application.

---

## 18. Skills Demonstrated

- Amazon S3 troubleshooting
- Cross-Origin Resource Sharing
- HTTP OPTIONS preflight investigation
- AWS CLI v2
- Linux Bash
- curl diagnostics
- HTTP status code analysis
- S3 CORS configuration
- Root cause analysis
- Secure remediation
- Verification of private access
- Cloud Engineering incident documentation

## Final Outcome

| Item | Expected Result |
|---|---|
| Incident | INC-S3-010 |
| Service | Amazon S3 |
| Error | CORS preflight 403 |
| Root Cause | Incorrect AllowedOrigins |
| Remediation | Corrected frontend origin |
| Functional Verification | Preflight 200 |
| Unauthorized Origin | Rejected |
| S3 Public Access | Remains blocked |
| Expected Status | Resolved |

**Key Takeaway:** When a frontend encounters an S3 CORS error, inspect the exact origin, requested method, and request headers. Fix the matching CORS rule without weakening S3 authorization controls.
