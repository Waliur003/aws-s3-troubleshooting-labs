# Lab 09 — Amazon S3 Versioning and Delete Marker Troubleshooting

## Overview

This hands-on lab demonstrates how to investigate and recover an Amazon S3 object that appears to have been deleted.

The incident simulates a cleanup script accidentally deleting an important report from a versioning-enabled S3 bucket.

Although ordinary requests return `404 Not Found`, the object's previous versions remain stored in S3.

The goal is to identify the current delete marker, recover the object without losing historical versions, verify successful restoration, and safely clean up the lab resources.

**Troubleshooting workflow:**

Establish Baseline → Reproduce Failure → Inspect Versions → Identify Root Cause → Recover → Verify → Cleanup

## Lab Information

| Item | Details |
|---|---|
| AWS Service | Amazon S3 |
| Incident ID | INC-S3-009 |
| Difficulty | Intermediate |
| Error | `404 Not Found` / `NoSuchKey` |
| Feature | S3 Versioning |
| Root Cause | Current delete marker hides the object |
| Environment | Ubuntu Linux (WSL2) |
| Tools | AWS CLI v2, Bash |
| Recovery Method | Remove the verified delete marker |
| Objective | Restore object without deleting historical versions |

---

## 1. Production Incident Scenario

### Incident Description

A Data Operations team reports that an application can no longer retrieve an important financial report stored in Amazon S3.

The file was previously accessible, but a scheduled cleanup script executed a delete operation.

The application now returns:

```text
An error occurred (404) when calling
the HeadObject operation: Not Found
```

The team is concerned that the report has been permanently lost.

### Expected Behavior

The application should retrieve the latest financial report:

```text
s3://LAB_BUCKET/reports/financial-report.txt
```

### Actual Behavior

The object does not appear in normal S3 listings, and requests without a version ID return 404.

### Potential Business Impact

- Data processing jobs may fail.
- Applications may lose access to critical files.
- Recovery operations may be delayed.
- Business reporting can be interrupted.

### Investigation Objective

Determine whether the object was permanently deleted or temporarily hidden by an S3 delete marker.

---

## 2. Architecture

### Before Accidental Deletion

```text
Application
    |
    | GetObject
    v
Amazon S3 Bucket
Versioning: Enabled
    |
    v
reports/financial-report.txt
    |
    +-- Version 2 (Current)
    |       |
    |       v
    |   Updated Report
    |
    +-- Version 1 (Previous)

HTTP 200 OK
```

### After Accidental Deletion

```text
Cleanup Script
    |
    | DeleteObject
    | No VersionId
    v
Amazon S3 Bucket
    |
    +-- Delete Marker (Current)
    |
    +-- Version 2 (Previous)
    |
    +-- Version 1 (Previous)
    |
    v
Application GetObject
    |
    v
HTTP 404 Not Found
```

### After Recovery

```text
Cloud Engineer
    |
    | DeleteObject
    | VersionId = Delete Marker ID
    v
Delete Marker Removed
    |
    v
Version 2 Becomes Current
    |
    v
Application GetObject
    |
    v
HTTP 200 OK
```

---

## 3. Important S3 Versioning Concepts

### Object Version

When S3 Versioning is enabled, uploading an object to an existing key creates a new version.

Each version receives a unique version ID.

### Current Version

The most recent version or delete marker associated with an object key.

### Noncurrent Version

An older version retained after another version becomes current.

### Delete Marker

A special S3 object version that makes an object appear deleted.

It does not contain the original object's data.

### Permanent Deletion

Deleting a specific object version using its version ID permanently removes that version.

### Main Difference

| Operation | Behavior in a versioning-enabled bucket |
|---|---|
| PUT object | Creates a new version |
| GET object | Retrieves current version |
| GET with version ID | Retrieves specified version |
| DELETE without version ID | Creates delete marker |
| DELETE with version ID | Permanently removes that specific version or marker |
| ListObjectVersions | Displays versions and delete markers |

**Critical concept:** A delete marker hides an object from ordinary requests but does not automatically remove historical versions.

---

## 4. Prerequisites

Required:

- AWS account
- AWS CLI v2
- Ubuntu Linux / WSL2
- Bash
- Permissions to create and manage a dedicated S3 bucket
- Permission to list object versions
- Permission to delete object versions
- Git and GitHub

Use only disposable test data.

Never perform version deletion against production objects without appropriate approval and verification.

### Verify AWS CLI

```bash
aws --version
```

### Verify AWS Identity

```bash
aws sts get-caller-identity
```

### Set Environment Variables

```bash
export AWS_REGION="us-east-1"

export ACCOUNT_ID=$(aws sts get-caller-identity \
  --query Account --output text)

export BUCKET="cloud-lab09-${ACCOUNT_ID}"

export OBJECT_KEY="reports/financial-report.txt"
```

Verify:

```bash
echo "Region: $AWS_REGION"
echo "Bucket: $BUCKET"
echo "Object Key: $OBJECT_KEY"
```

---

## 5. Create the Working Environment

### Step 1 — Create the Bucket

First confirm that the proposed bucket is not already used by another environment.

```bash
aws s3api head-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

If the name is available:

```bash
aws s3api create-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

### Step 2 — Verify the Bucket

```bash
aws s3api head-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

### Step 3 — Enable Versioning

```bash
aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled \
  --region "$AWS_REGION"
```

### Step 4 — Verify Versioning

```bash
aws s3api get-bucket-versioning \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

Expected:

```json
{
  "Status": "Enabled"
}
```

**Note:** AWS recommends allowing time for propagation after initially enabling versioning. For newly enabled buckets, the propagation period can take up to approximately 15 minutes.

---

## 6. Create Multiple Object Versions

### Step 1 — Create Version 1

```bash
cat > financial-report.txt <<'EOF'
Financial Report - Version 1

Revenue: 10000
Expenses: 4000
Status: Initial Report
EOF
```

Upload:

```bash
aws s3api put-object \
  --bucket "$BUCKET" \
  --key "$OBJECT_KEY" \
  --body financial-report.txt \
  --region "$AWS_REGION"
```

S3 should return a generated `VersionId`.

### Step 2 — Create Version 2

Update the local file:

```bash
cat > financial-report.txt <<'EOF'
Financial Report - Version 2

Revenue: 15000
Expenses: 5000
Status: Updated Report
EOF
```

Upload again:

```bash
aws s3api put-object \
  --bucket "$BUCKET" \
  --key "$OBJECT_KEY" \
  --body financial-report.txt \
  --region "$AWS_REGION"
```

The same object key now has two versions.

### Step 3 — Inspect Versions

```bash
aws s3api list-object-versions \
  --bucket "$BUCKET" \
  --prefix "$OBJECT_KEY" \
  --query 'Versions[].{VersionId:VersionId,Latest:IsLatest,Modified:LastModified}' \
  --output table \
  --region "$AWS_REGION"
```

Expected:

- Version 1 exists.
- Version 2 exists.
- Version 2 has `IsLatest=true`.

The version IDs are generated by AWS and differ between environments.

---

## 7. Establish a Working Baseline

Download the current version:

```bash
aws s3api get-object \
  --bucket "$BUCKET" \
  --key "$OBJECT_KEY" \
  current-report.txt \
  --region "$AWS_REGION"
```

Verify:

```bash
cat current-report.txt
```

Expected:

```text
Financial Report - Version 2

Revenue: 15000
Expenses: 5000
Status: Updated Report
```

The application can successfully access the report before the simulated incident.

---

## 8. Introduce the Failure

### Step 1 — Simulate Accidental Deletion

```bash
aws s3api delete-object \
  --bucket "$BUCKET" \
  --key "$OBJECT_KEY" \
  --region "$AWS_REGION"
```

Because versioning is enabled, S3 inserts a delete marker.

Expected response fields include:

```json
{
  "DeleteMarker": true,
  "VersionId": "AWS_GENERATED_DELETE_MARKER_ID"
}
```

### Step 2 — Reproduce the 404 Error

```bash
aws s3api head-object \
  --bucket "$BUCKET" \
  --key "$OBJECT_KEY" \
  --region "$AWS_REGION"
```

Expected:

```text
An error occurred (404) when calling
the HeadObject operation: Not Found
```

### Step 3 — Attempt Object Download

```bash
aws s3api get-object \
  --bucket "$BUCKET" \
  --key "$OBJECT_KEY" \
  missing-report.txt \
  --region "$AWS_REGION"
```

Expected:

```text
NoSuchKey
The specified key does not exist.
```

The object appears missing even though older versions remain stored.

---

## 9. Troubleshooting Investigation

### Check 1 — Verify Bucket Versioning

```bash
aws s3api get-bucket-versioning \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

Expected:

```text
Enabled
```

### Check 2 — List Current Objects

```bash
aws s3 ls "s3://$BUCKET/reports/" \
  --region "$AWS_REGION"
```

The report should not appear in a normal object listing.

### Check 3 — List Historical Versions

```bash
aws s3api list-object-versions \
  --bucket "$BUCKET" \
  --prefix "$OBJECT_KEY" \
  --output json \
  --region "$AWS_REGION"
```

Inspect the `Versions` and `DeleteMarkers` collections.

### Check 4 — Display Relevant Version Details

```bash
aws s3api list-object-versions \
  --bucket "$BUCKET" \
  --prefix "$OBJECT_KEY" \
  --query '{Versions:Versions[].{Key:Key,VersionId:VersionId,Latest:IsLatest},DeleteMarkers:DeleteMarkers[].{Key:Key,VersionId:VersionId,Latest:IsLatest}}' \
  --output json \
  --region "$AWS_REGION"
```

Expected structure:

```json
{
  "Versions": [
    {
      "Key": "reports/financial-report.txt",
      "VersionId": "VERSION_2_ID",
      "Latest": false
    },
    {
      "Key": "reports/financial-report.txt",
      "VersionId": "VERSION_1_ID",
      "Latest": false
    }
  ],
  "DeleteMarkers": [
    {
      "Key": "reports/financial-report.txt",
      "VersionId": "DELETE_MARKER_ID",
      "Latest": true
    }
  ]
}
```

### Investigation Findings

| Check | Expected Finding |
|---|---|
| Bucket exists | Yes |
| Versioning | Enabled |
| Current object listing | Object missing |
| Previous versions | Available |
| Current version | Delete marker |
| Root cause | Accidental delete marker insertion |

---

## 10. Root Cause Analysis

### Root Cause

A cleanup script issued a `DeleteObject` request without a version ID against an object in a versioning-enabled S3 bucket.

S3 inserted a delete marker, which became the current version.

Consequently, ordinary requests behaved as if the report no longer existed.

### Root Cause Flow

```text
Cleanup Script
      |
      v
DeleteObject Without VersionId
      |
      v
S3 Creates Delete Marker
      |
      v
Delete Marker Becomes Current
      |
      v
Normal GetObject / HeadObject
      |
      v
404 Not Found
```

### Five Whys

1. **Why did the application return 404?** The current version was a delete marker.
2. **Why was the delete marker created?** A delete operation was issued.
3. **Why did the delete not erase the historical versions?** S3 Versioning was enabled.
4. **Why did the application fail to retrieve an older version?** Its ordinary request did not specify a version ID.
5. **How can this be prevented?** Protect deletion operations, enforce least privilege, and monitor unexpected object deletions.

---

## 11. Recovery Method 1 — Retrieve a Previous Version

Before removing anything, an engineer can inspect and retrieve a known previous version.

### Step 1 — List Available Version IDs

```bash
aws s3api list-object-versions \
  --bucket "$BUCKET" \
  --prefix "$OBJECT_KEY" \
  --query 'Versions[].{VersionId:VersionId,Latest:IsLatest}' \
  --output table \
  --region "$AWS_REGION"
```

### Step 2 — Select a Previous Version

Set the version ID to the actual value returned by AWS:

```bash
export PREVIOUS_VERSION_ID="PASTE_ACTUAL_OBJECT_VERSION_ID"
```

### Step 3 — Download That Version

```bash
aws s3api get-object \
  --bucket "$BUCKET" \
  --key "$OBJECT_KEY" \
  --version-id "$PREVIOUS_VERSION_ID" \
  previous-report.txt \
  --region "$AWS_REGION"
```

Verify:

```bash
cat previous-report.txt
```

This recovers the selected historical version locally without changing the S3 version history.

**Important:** Retrieving a specific historical version requires appropriate permissions, including `s3:GetObjectVersion`.

---

## 12. Recovery Method 2 — Remove the Delete Marker

This method restores ordinary access to the most recent retained object version.

### Step 1 — Identify the Current Delete Marker

```bash
export DELETE_MARKER_ID=$(aws s3api list-object-versions \
  --bucket "$BUCKET" \
  --prefix "$OBJECT_KEY" \
  --query "DeleteMarkers[?Key=='${OBJECT_KEY}' && IsLatest==\`true\`].VersionId | [0]" \
  --output text \
  --region "$AWS_REGION")
```

Verify:

```bash
echo "$DELETE_MARKER_ID"
```

Never proceed if the value is empty or `None`.

### Step 2 — Independently Verify the Marker

```bash
aws s3api list-object-versions \
  --bucket "$BUCKET" \
  --prefix "$OBJECT_KEY" \
  --query "DeleteMarkers[?Key=='${OBJECT_KEY}' && IsLatest==\`true\`]" \
  --output json \
  --region "$AWS_REGION"
```

Confirm that the version ID matches the current delete marker for the exact object key.

### Step 3 — Remove Only the Verified Marker

```bash
if [[ -n "$DELETE_MARKER_ID" && "$DELETE_MARKER_ID" != "None" ]]; then
  aws s3api delete-object \
    --bucket "$BUCKET" \
    --key "$OBJECT_KEY" \
    --version-id "$DELETE_MARKER_ID" \
    --region "$AWS_REGION"
else
  echo "No verified delete marker found. Stopping."
fi
```

This permanently removes the selected delete marker.

It does not delete the previous object versions when the ID correctly identifies the marker.

**Warning:** Passing an actual object version ID instead of the marker ID would permanently delete that object version.

---

## 13. Verify Successful Recovery

### Step 1 — Verify Object Metadata

```bash
aws s3api head-object \
  --bucket "$BUCKET" \
  --key "$OBJECT_KEY" \
  --region "$AWS_REGION"
```

Expected: successful metadata response.

### Step 2 — Download Current Object

```bash
aws s3api get-object \
  --bucket "$BUCKET" \
  --key "$OBJECT_KEY" \
  recovered-report.txt \
  --region "$AWS_REGION"
```

### Step 3 — Verify Content

```bash
cat recovered-report.txt
```

Expected:

```text
Financial Report - Version 2

Revenue: 15000
Expenses: 5000
Status: Updated Report
```

### Step 4 — Compare Files

```bash
diff current-report.txt recovered-report.txt
```

No output means the files are identical.

### Step 5 — Inspect Version History

```bash
aws s3api list-object-versions \
  --bucket "$BUCKET" \
  --prefix "$OBJECT_KEY" \
  --output table \
  --region "$AWS_REGION"
```

Expected:

- Delete marker removed.
- Version 2 becomes current.
- Version 1 remains available.

### Verification Summary

| Verification | Expected Result |
|---|---|
| Initial access | Successful |
| Accidental deletion | Delete marker created |
| Normal request after deletion | 404 |
| Historical versions | Preserved |
| Specific version retrieval | Successful |
| Delete marker removal | Successful |
| Normal access restored | 200 |
| Recovered data | Matches baseline |
| Version history | Preserved |

---

## 14. Production Engineering Considerations

### Incident Triage

Investigate:

- Which S3 bucket and object key are affected?
- Is versioning enabled?
- When did the failure begin?
- Which application or identity performed the delete?
- Is the current version a delete marker?
- Do historical versions still exist?
- Are S3 Object Lock or retention controls enabled?

### Evidence Collection

Useful evidence includes:

- `ListObjectVersions` output
- Object version IDs
- Delete marker information
- Application error logs
- S3 data events in CloudTrail, if configured
- Deployment or cleanup script execution records
- S3 versioning settings

### Important Production Safety Rule

Never permanently delete object versions based only on an assumed version ID.

Always confirm:

1. The correct AWS account.
2. The correct S3 bucket.
3. The exact object key.
4. The version ID.
5. Whether the target is a delete marker or actual object data.
6. Authorization to perform the recovery.

### Prevention

- Enable versioning for important S3 datasets.
- Use least-privilege delete permissions.
- Restrict `s3:DeleteObjectVersion` where appropriate.
- Configure S3 Object Lock for immutable data when required.
- Review cleanup scripts before deployment.
- Monitor unexpected object deletions.
- Use CloudTrail S3 data events for relevant audit coverage.
- Test recovery procedures regularly.
- Implement retention and lifecycle rules carefully.

---

## 15. Related S3 Errors

| Problem | Possible Explanation |
|---|---|
| `404 Not Found` | Current version is a delete marker |
| `NoSuchKey` | Object missing or hidden by marker |
| `AccessDenied` | Insufficient permission |
| `NoSuchVersion` | Requested version ID doesn't exist |
| `MethodNotAllowed` | GET request targets a delete marker version |
| `AccessDenied` during version deletion | Missing permission or Object Lock restrictions |
| Bucket deletion fails | Historical versions or markers remain |

---

## 16. Interview Questions and Answers

### Q1. What is S3 Versioning?

S3 Versioning is a feature that preserves multiple versions of an object under the same key.

### Q2. What happens when you delete an object in a versioning-enabled bucket?

A normal delete request without a version ID creates a delete marker, rather than permanently removing existing versions.

### Q3. What is an S3 delete marker?

A delete marker is a special version that makes an object appear deleted to normal requests.

### Q4. Why does GetObject return 404 when a delete marker is current?

Because S3 treats the object as deleted when the current version is a delete marker.

### Q5. How can you find deleted object versions?

Use:

```bash
aws s3api list-object-versions \
  --bucket BUCKET_NAME
```

### Q6. How do you recover an object hidden by a delete marker?

Identify the current delete marker's version ID and delete that specific marker, provided the action is authorized and the previous version is the desired one.

### Q7. What is the difference between deleting an object and deleting a version?

Deleting without a version ID normally inserts a delete marker in a versioning-enabled bucket.

Deleting with a specific version ID permanently removes that version.

### Q8. Can you retrieve an older object version without removing the delete marker?

Yes. Specify the historical version ID in a `GetObject` request, assuming the identity has the required permission.

### Q9. How do you protect critical objects against accidental deletion?

Use S3 Versioning, least-privilege permissions, appropriate Object Lock retention, monitoring, and tested recovery procedures.

### Q10. How would you explain this incident in an interview?

> An application received 404 when attempting to retrieve an S3 report. I verified the bucket's versioning status and inspected the object's version history. I found that an accidental deletion created a current delete marker while previous versions remained intact. I identified and removed the correct delete marker, verified normal object access was restored, and confirmed the historical versions were preserved.

---

## 17. Cleanup

**Warning:** This section permanently deletes the lab's historical object versions.

Run only against your isolated Lab 09 bucket after confirming that it contains no unrelated data.

### Step 1 — Verify Bucket and Object

```bash
echo "$BUCKET"
echo "$OBJECT_KEY"
aws sts get-caller-identity
```

### Step 2 — List Object Versions and Delete Markers

```bash
aws s3api list-object-versions \
  --bucket "$BUCKET" \
  --output json \
  --region "$AWS_REGION"
```

Inspect all returned keys and versions.

### Step 3 — List Historical Version IDs

```bash
aws s3api list-object-versions \
  --bucket "$BUCKET" \
  --prefix "$OBJECT_KEY" \
  --query "Versions[?Key=='${OBJECT_KEY}'].VersionId" \
  --output text \
  --region "$AWS_REGION"
```

For each verified Lab 09 version ID, run:

```bash
aws s3api delete-object \
  --bucket "$BUCKET" \
  --key "$OBJECT_KEY" \
  --version-id "PASTE_ACTUAL_VERSION_ID" \
  --region "$AWS_REGION"
```

Repeat for all historical object versions you intentionally created.

### Step 4 — Remove Remaining Delete Markers

Inspect:

```bash
aws s3api list-object-versions \
  --bucket "$BUCKET" \
  --prefix "$OBJECT_KEY" \
  --query "DeleteMarkers[?Key=='${OBJECT_KEY}']" \
  --output json \
  --region "$AWS_REGION"
```

If any lab-only delete markers remain, delete each using its verified version ID:

```bash
aws s3api delete-object \
  --bucket "$BUCKET" \
  --key "$OBJECT_KEY" \
  --version-id "PASTE_ACTUAL_MARKER_ID" \
  --region "$AWS_REGION"
```

### Step 5 — Verify Bucket Is Empty

```bash
aws s3api list-object-versions \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

Confirm that no object versions or delete markers remain.

### Step 6 — Delete Lab Bucket

```bash
aws s3api delete-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

### Step 7 — Remove Local Temporary Files

```bash
rm -f current-report.txt \
  recovered-report.txt \
  previous-report.txt \
  missing-report.txt
```

Keep `financial-report.txt` as a sample file for GitHub.

---

## 18. Repository Structure

```text
09-s3-versioning-delete-marker/
│
├── README.md
└── financial-report.txt
```

The README contains the commands needed to create multiple object versions and reproduce the incident.

Do not commit AWS credentials, temporary response files, or sensitive production data.

---

## 19. Lessons Learned

This lab demonstrates that an S3 object returning 404 does not always mean its data has been permanently lost.

In a versioning-enabled bucket, an accidental delete can create a delete marker that hides previous object versions.

The investigation involved checking the bucket's versioning status, inspecting historical versions, identifying the current delete marker, recovering the object, and verifying that previous versions remained intact.

The most important lesson is to understand S3 version history before performing destructive recovery operations.

---

## 20. Skills Demonstrated

- Amazon S3 troubleshooting
- S3 Versioning
- Delete marker investigation
- AWS CLI v2
- Linux Bash
- Version ID inspection
- Incident root cause analysis
- Object recovery
- Data integrity verification
- Safe cleanup of versioned objects
- Disaster recovery fundamentals
- Cloud security and least privilege
- Production incident documentation

## Final Outcome

| Item | Expected Result |
|---|---|
| Incident | INC-S3-009 |
| AWS Service | Amazon S3 |
| Error | 404 Not Found / NoSuchKey |
| Root Cause | Current delete marker |
| Historical Versions | Preserved |
| Recovery | Remove verified delete marker |
| Verification | Object download succeeds |
| Data Integrity | Matches baseline |
| Expected Lab Status | Resolved |

**Key Takeaway:** In a versioning-enabled S3 bucket, an object hidden by a delete marker can often be recovered without losing its historical versions. Always inspect version history before permanently deleting any version.
