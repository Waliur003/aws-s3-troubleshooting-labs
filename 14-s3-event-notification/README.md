# Lab 14 — Amazon S3 Event Notification Not Triggering

## Overview

This lab demonstrates how to troubleshoot an Amazon S3 event notification that fails to deliver object-created events to an Amazon SQS queue.

In the simulated production incident, an application successfully uploads files to an S3 bucket, but a downstream processing service does not receive the expected notifications.

The SQS destination is correctly configured, but the S3 notification rule contains an incorrect object key prefix.

- **Actual object prefix:** `uploads/`
- **Configured prefix:** `upload/`

Because the filter does not match the uploaded objects, S3 does not generate the expected notifications for those objects.

The objective is to reproduce the problem, investigate the S3-to-SQS integration, correct the filter, and verify successful event delivery.

**Troubleshooting workflow:** Baseline → Misconfiguration → Reproduce → Investigate → Root Cause → Remediate → Verify → Cleanup

---

## Lab Information

| Item | Details |
|---|---|
| AWS Services | Amazon S3 + Amazon SQS |
| Incident ID | INC-S3-014 |
| Difficulty | Intermediate |
| Error | ObjectCreated notification missing |
| Event Type | `s3:ObjectCreated:*` |
| Destination | Standard SQS queue |
| Incorrect Filter | `upload/` |
| Correct Filter | `uploads/` |
| Root Cause | Incorrect notification prefix |
| Environment | Ubuntu Linux / WSL2 |
| Tools | AWS CLI v2, Bash, Python 3 |
| Remediation | Correct the prefix filter |
| Verification | Receive and inspect an SQS event |

---

## 1. Production Incident Scenario

### Incident Description

A cloud-based application uses Amazon S3 to store uploaded documents.

Whenever a file is uploaded, Amazon S3 should publish an object-created notification to Amazon SQS.

A background processing service consumes these messages to start its processing workflow.

However, the operations team discovers that files are successfully uploaded but downstream processing never begins.

### Reported Symptoms

```text
S3 PutObject: SUCCESS

Object: uploads/report.txt

Expected Event: s3:ObjectCreated:Put

SQS Message: NOT RECEIVED

Application Processing: NOT STARTED
```

### Expected Behavior

An object uploaded under `uploads/` should generate an S3 object-created event and deliver a message to the configured SQS queue.

### Actual Behavior

The notification rule only matches object keys beginning with `upload/`.

The intended objects use `uploads/`, so they do not match.

### Potential Business Impact

- File-processing jobs may not start.
- Documents may remain unprocessed.
- Event-driven workflows may stall.
- Downstream applications may miss expected updates.
- Operations teams may need manual intervention.

---

## 2. Architecture

### Broken Architecture

```text
Application
     |
     | PutObject
     v
Amazon S3 Bucket
     |
     +-- uploads/report.txt
     |
     v
S3 Event Notification
     |
     +-- Event: s3:ObjectCreated:*
     +-- Filter: upload/
     |
     v
Prefix Does Not Match
     |
     X
No Matching ObjectCreated Event
     |
     v
Amazon SQS Queue
     |
     v
Consumer Does Not Receive Event
```

### Corrected Architecture

```text
Application
     |
     | PutObject
     v
Amazon S3 Bucket
     |
     +-- uploads/recovered-report.txt
     |
     v
S3 Event Notification
     |
     +-- Event: s3:ObjectCreated:*
     +-- Filter: uploads/
     |
     v
Prefix Matches
     |
     v
Amazon SQS Queue
     |
     v
ObjectCreated Event Received
     |
     v
Downstream Processing Can Begin
```

---

## 3. Understanding S3 Event Notifications

Amazon S3 can publish notifications when supported events occur.

Examples include:

- Object creation
- Object removal
- Object restoration
- Object tagging changes
- Lifecycle transitions
- Replication events

### Supported Destinations

- Amazon SQS
- Amazon SNS
- AWS Lambda
- Amazon EventBridge

Direct S3-to-SQS notifications require a standard SQS queue. FIFO queues require a different integration pattern, such as EventBridge.

### Important Configuration Fields

| Field | Purpose |
|---|---|
| `QueueArn` | Identifies the destination queue |
| `Events` | Specifies which S3 events trigger notifications |
| `Filter` | Restricts events to matching object keys |
| `prefix` | Matches the beginning of an object key |
| `suffix` | Matches the end of an object key |
| SQS queue policy | Permits S3 to publish messages |

### Delivery Behavior

S3 event notifications are designed for at-least-once delivery.

A consumer must be prepared for duplicate or out-of-order messages.

Notification delivery is asynchronous and may take longer than a few seconds.

---

## 4. Prerequisites

Required:

- AWS account
- AWS CLI v2
- Ubuntu Linux / WSL2
- Bash
- Python 3
- Permission to manage an isolated S3 bucket
- Permission to create and configure SQS queues
- Permission to manage S3 event notifications
- Git and GitHub

Use a personal sandbox environment.

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

export BUCKET="cloud-lab14-${ACCOUNT_ID}"

export QUEUE_NAME="cloud-lab14-s3-events-${ACCOUNT_ID}"

export OBJECT_KEY="uploads/report.txt"
```

Verify:

```bash
echo "Region: $AWS_REGION"
echo "Bucket: $BUCKET"
echo "Queue: $QUEUE_NAME"
echo "Object: $OBJECT_KEY"
```

---

## 5. Create the Private S3 Bucket

### Step 1 — Check Bucket Availability

```bash
aws s3api head-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

Only proceed with creation when the name is available and does not belong to an existing environment.

### Step 2 — Create Bucket

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

### Step 4 — Verify Public Access Settings

```bash
aws s3api get-public-access-block \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

Expected: all four Block Public Access settings are enabled.

---

## 6. Create Amazon SQS Queue

### Step 1 — Check Existing Queue

```bash
aws sqs get-queue-url \
  --queue-name "$QUEUE_NAME" \
  --region "$AWS_REGION"
```

For a new queue, a nonexistent-queue error is expected.

Do not reuse a queue belonging to another workload.

### Step 2 — Create Standard Queue

```bash
export QUEUE_URL=$(aws sqs create-queue \
  --queue-name "$QUEUE_NAME" \
  --attributes '{
    "ReceiveMessageWaitTimeSeconds": "10"
  }' \
  --query QueueUrl \
  --output text \
  --region "$AWS_REGION")
```

### Step 3 — Get Queue ARN

```bash
export QUEUE_ARN=$(aws sqs get-queue-attributes \
  --queue-url "$QUEUE_URL" \
  --attribute-names QueueArn \
  --query 'Attributes.QueueArn' \
  --output text \
  --region "$AWS_REGION")
```

Verify:

```bash
echo "$QUEUE_URL"
echo "$QUEUE_ARN"
```

---

## 7. Configure SQS Queue Permissions

S3 needs permission to publish messages to the destination SQS queue.

### Step 1 — Create Queue Policy

Create `sqs-queue-policy.json`:

```bash
cat > sqs-queue-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowS3EventNotifications",
      "Effect": "Allow",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Action": "sqs:SendMessage",
      "Resource": "$QUEUE_ARN",
      "Condition": {
        "ArnEquals": {
          "aws:SourceArn": "arn:aws:s3:::$BUCKET"
        },
        "StringEquals": {
          "aws:SourceAccount": "$ACCOUNT_ID"
        }
      }
    }
  ]
}
EOF
```

### Step 2 — Generate SQS Attributes File

```bash
python3 - <<'PY'
import json

with open("sqs-queue-policy.json") as f:
    policy = json.load(f)

with open("queue-attributes.json", "w") as f:
    json.dump({"Policy": json.dumps(policy)}, f, indent=2)
PY
```

### Step 3 — Apply Queue Policy

```bash
aws sqs set-queue-attributes \
  --queue-url "$QUEUE_URL" \
  --attributes file://queue-attributes.json \
  --region "$AWS_REGION"
```

### Step 4 — Verify Queue Policy

```bash
aws sqs get-queue-attributes \
  --queue-url "$QUEUE_URL" \
  --attribute-names Policy \
  --region "$AWS_REGION"
```

### Security Explanation

| Control | Purpose |
|---|---|
| S3 service principal | Allows Amazon S3 to send |
| `sqs:SendMessage` | Grants only message-publishing access |
| `aws:SourceArn` | Restricts publishing to the lab bucket |
| `aws:SourceAccount` | Restricts the originating AWS account |

**Important:** SQS encryption using a customer-managed KMS key can require additional KMS permissions for the S3 service principal.

---

## 8. Introduce the Broken Notification Configuration

### Step 1 — Check Existing Notifications

```bash
aws s3api get-bucket-notification-configuration \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

For a new bucket, the expected result is an empty notification configuration.

### Step 2 — Create Broken Notification Rule

Create `broken-notification.json`:

```bash
cat > broken-notification.json <<EOF
{
  "QueueConfigurations": [
    {
      "Id": "Lab14ObjectCreated",
      "QueueArn": "$QUEUE_ARN",
      "Events": [
        "s3:ObjectCreated:*"
      ],
      "Filter": {
        "Key": {
          "FilterRules": [
            {
              "Name": "prefix",
              "Value": "upload/"
            }
          ]
        }
      }
    }
  ]
}
EOF
```

### Step 3 — Identify the Intentional Error

Configured prefix:

```text
upload/
```

Actual object key:

```text
uploads/report.txt
```

The missing `s` prevents the filter from matching.

### Step 4 — Apply Broken Configuration

```bash
aws s3api put-bucket-notification-configuration \
  --bucket "$BUCKET" \
  --notification-configuration file://broken-notification.json \
  --region "$AWS_REGION"
```

### Step 5 — Verify Configuration

```bash
aws s3api get-bucket-notification-configuration \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

Expected:

```text
Event: s3:ObjectCreated:*
Prefix: upload/
Destination: Lab 14 SQS Queue
```

**Note:** If AWS reports that it cannot validate the destination configuration, inspect the queue ARN, Region, SQS policy, and KMS encryption settings.

---

## 9. Reproduce the Notification Failure

### Step 1 — Create Sample Object

Create `report.txt`:

```bash
cat > report.txt <<'EOF'
Cloud Engineering Lab 14

Application: File Processing
Event: ObjectCreated
Expected SQS Notification: Yes
EOF
```

### Step 2 — Upload to the Actual Prefix

```bash
aws s3api put-object \
  --bucket "$BUCKET" \
  --key "$OBJECT_KEY" \
  --body report.txt \
  --region "$AWS_REGION"
```

### Step 3 — Verify Object

```bash
aws s3api head-object \
  --bucket "$BUCKET" \
  --key "$OBJECT_KEY" \
  --region "$AWS_REGION"
```

### Step 4 — Poll the Queue

```bash
aws sqs receive-message \
  --queue-url "$QUEUE_URL" \
  --max-number-of-messages 10 \
  --wait-time-seconds 10 \
  --region "$AWS_REGION"
```

### Expected Observation

No `ObjectCreated` notification should be generated for `uploads/report.txt` under the broken prefix rule.

A configuration test message may appear:

```text
s3:TestEvent
```

This message indicates that S3 tested the destination. It does not prove that the uploaded object matched the rule.

**Important:** One empty SQS poll is not sufficient evidence of a notification failure. The mismatch between the configured filter and the object key is the decisive finding.

---

## 10. Troubleshooting Investigation

### Check 1 — Verify S3 Upload

```bash
aws s3api head-object \
  --bucket "$BUCKET" \
  --key "$OBJECT_KEY" \
  --region "$AWS_REGION"
```

### Check 2 — Inspect Notification Configuration

```bash
aws s3api get-bucket-notification-configuration \
  --bucket "$BUCKET" \
  --query 'QueueConfigurations[].{Id:Id,Events:Events,Filter:Filter}' \
  --output json \
  --region "$AWS_REGION"
```

### Check 3 — Inspect Object Keys

```bash
aws s3api list-objects-v2 \
  --bucket "$BUCKET" \
  --query 'Contents[].Key' \
  --output json \
  --region "$AWS_REGION"
```

Expected:

```json
[
  "uploads/report.txt"
]
```

### Check 4 — Verify Queue Policy

```bash
aws sqs get-queue-attributes \
  --queue-url "$QUEUE_URL" \
  --attribute-names Policy \
  --region "$AWS_REGION"
```

Confirm that the queue permits `sqs:SendMessage` from the intended S3 bucket.

### Check 5 — Verify Queue Region

```bash
echo "$QUEUE_ARN"
echo "$AWS_REGION"
```

The bucket and direct SQS notification destination must be in the same AWS Region.

### Investigation Findings

| Check | Finding |
|---|---|
| S3 upload | Successful |
| Object exists | Yes |
| SQS queue | Exists |
| SQS permission | Configured |
| Event type | ObjectCreated |
| Configured prefix | `upload/` |
| Actual object prefix | `uploads/` |
| Prefix match | No |
| Root cause | Incorrect filter |

---

## 11. Root Cause Analysis

### Root Cause

The S3 notification configuration uses an incorrect object key prefix.

The rule matches `upload/`, but the application stores objects under `uploads/`.

Therefore, S3 does not generate the intended event notification for those uploads.

### Root Cause Flow

```text
Application Upload
        |
        v
uploads/report.txt
        |
        v
S3 Notification Filter
        |
        v
Configured: upload/
        |
        v
Prefix Comparison
        |
        v
No Match
        |
        v
No ObjectCreated Notification
```

### Five Whys

1. **Why did the processing workflow not start?** Its expected SQS event was missing.
2. **Why was the event missing?** The uploaded object's key did not match the notification filter.
3. **Why did the filter not match?** It used `upload/` instead of `uploads/`.
4. **Why was the configuration accepted?** The rule was syntactically valid.
5. **How can this be prevented?** Validate event filters against actual object keys and test new uploads before deployment.

---

## 12. Apply Remediation

### Step 1 — Create the Corrected Rule

Create `fixed-notification.json`:

```bash
cat > fixed-notification.json <<EOF
{
  "QueueConfigurations": [
    {
      "Id": "Lab14ObjectCreated",
      "QueueArn": "$QUEUE_ARN",
      "Events": [
        "s3:ObjectCreated:*"
      ],
      "Filter": {
        "Key": {
          "FilterRules": [
            {
              "Name": "prefix",
              "Value": "uploads/"
            }
          ]
        }
      }
    }
  ]
}
EOF
```

### Step 2 — Apply the Fix

```bash
aws s3api put-bucket-notification-configuration \
  --bucket "$BUCKET" \
  --notification-configuration file://fixed-notification.json \
  --region "$AWS_REGION"
```

### Step 3 — Verify Correct Configuration

```bash
aws s3api get-bucket-notification-configuration \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

Expected:

```text
Event: s3:ObjectCreated:*
Prefix: uploads/
Destination: Lab 14 SQS queue
```

**Important:** Changing the notification rule does not retroactively generate events for objects that were uploaded earlier. A new object operation is required.

---

## 13. Verify Successful Notification Delivery

### Step 1 — Create Another Object

Create `recovered-report.txt`:

```bash
cat > recovered-report.txt <<'EOF'
Cloud Engineering Lab 14

Event Notification Recovery Test
Expected Result: SQS event delivered
Status: New Object Upload
EOF
```

### Step 2 — Upload After the Fix

```bash
aws s3api put-object \
  --bucket "$BUCKET" \
  --key "uploads/recovered-report.txt" \
  --body recovered-report.txt \
  --region "$AWS_REGION"
```

### Step 3 — Poll SQS

```bash
aws sqs receive-message \
  --queue-url "$QUEUE_URL" \
  --max-number-of-messages 10 \
  --wait-time-seconds 10 \
  --region "$AWS_REGION"
```

A successful object-created notification contains fields resembling:

```json
{
  "Records": [
    {
      "eventSource": "aws:s3",
      "eventName": "ObjectCreated:Put",
      "s3": {
        "bucket": {
          "name": "LAB_BUCKET"
        },
        "object": {
          "key": "uploads/recovered-report.txt"
        }
      }
    }
  ]
}
```

Actual S3 messages contain additional metadata and identifiers.

### Step 4 — Create an Automated Verification Script

Create `check-notification.py`:

```python
import json
import os
import subprocess
import sys
from urllib.parse import unquote_plus

queue_url = os.environ["QUEUE_URL"]
region = os.environ["AWS_REGION"]
expected_key = "uploads/recovered-report.txt"

for attempt in range(1, 7):
    result = subprocess.run(
        [
            "aws",
            "sqs",
            "receive-message",
            "--queue-url", queue_url,
            "--max-number-of-messages", "10",
            "--wait-time-seconds", "10",
            "--region", region,
            "--output", "json"
        ],
        capture_output=True,
        text=True,
        check=True
    )

    response = json.loads(result.stdout or "{}")
    messages = response.get("Messages", [])

    print(
        f"Polling attempt {attempt}: "
        f"{len(messages)} message(s)"
    )

    for message in messages:
        body = json.loads(message["Body"])

        if body.get("Event") == "s3:TestEvent":
            print("S3 configuration test event")
            continue

        for record in body.get("Records", []):
            event_name = record.get(
                "eventName", ""
            )

            object_key = unquote_plus(
                record.get("s3", {})
                .get("object", {})
                .get("key", "")
            )

            print("Event:", event_name)
            print("Object:", object_key)

            if (
                event_name.startswith("ObjectCreated:")
                and object_key == expected_key
            ):
                print(
                    "SUCCESS: Expected S3 event received"
                )
                sys.exit(0)

print("Expected notification not observed.")
print("Check S3 filters, queue policy, and delivery.")
sys.exit(1)
```

### Step 5 — Run Verification

```bash
python3 check-notification.py
```

Expected:

```text
Event: ObjectCreated:Put
Object: uploads/recovered-report.txt
SUCCESS: Expected S3 event received
```

If the script doesn't find the event, investigate further. S3 event delivery is asynchronous, and receiving messages temporarily hides them until their visibility timeout expires.

For reliable verification, avoid running multiple SQS consumers at the same time during this test.

---

## 14. Negative Test — Excluded Object Prefix

### Step 1 — Create an Unrelated File

```bash
echo "Not eligible for notification" > unrelated.txt
```

### Step 2 — Upload Outside `uploads/`

```bash
aws s3api put-object \
  --bucket "$BUCKET" \
  --key "archive/unrelated.txt" \
  --body unrelated.txt \
  --region "$AWS_REGION"
```

### Expected Behavior

The object does not match the `uploads/` notification filter.

Therefore, this notification rule should not generate an object-created event for it.

Note that previously delivered SQS messages may still be present. A queue containing messages is not proof that the unrelated upload matched the filter.

### Verification Summary

| Test | Before Fix | After Fix |
|---|---|---|
| S3 upload succeeds | Yes | Yes |
| SQS queue exists | Yes | Yes |
| SQS publishing permission | Configured | Configured |
| Prefix filter | `upload/` | `uploads/` |
| Intended object matches | No | Yes |
| ObjectCreated notification | Not generated for intended key | Expected |
| Message received | Not observed | Verified by matching event |
| Unrelated prefix | Excluded | Excluded |
| S3 public access | Blocked | Blocked |

---

## 15. Production Engineering Considerations

### Common Reasons S3 Events Are Missing

- Incorrect prefix or suffix filter
- Incorrect event type
- Missing SQS queue permissions
- SQS destination in the wrong Region
- Customer-managed KMS encryption permissions
- Notification configuration not deployed successfully
- Notification configuration changes not yet effective
- Consumer reading messages before another consumer
- Messages temporarily hidden by the visibility timeout
- Consumer incorrectly parsing S3 event records

### Production Investigation

1. Confirm the S3 object operation succeeded.
2. Verify the exact object key.
3. Inspect S3 notification configuration.
4. Verify the event type.
5. Compare prefix and suffix filters.
6. Verify the destination ARN.
7. Inspect the SQS queue policy.
8. Check the destination Region.
9. Review KMS encryption settings.
10. Generate a new test event.
11. Poll SQS and inspect the event.
12. Review downstream processing logs.

### Event Delivery Guarantees

S3 event notifications are designed for at-least-once delivery.

Applications should therefore:

- Handle duplicate messages.
- Avoid assuming strict event ordering.
- Use idempotent processing.
- Track successfully processed objects.
- Use dead-letter queues where appropriate.
- Monitor message age and processing failures.

### Security Best Practices

- Keep S3 Block Public Access enabled.
- Limit the SQS queue policy to the source bucket.
- Use `aws:SourceAccount` and `aws:SourceArn`.
- Grant only `sqs:SendMessage` for the publishing service.
- Avoid unnecessarily broad notification filters.
- Protect downstream processors with IAM least privilege.
- Use appropriate encryption settings for production queues.

---

## 16. Related Errors and Symptoms

| Problem | Possible Cause |
|---|---|
| No SQS event | Incorrect prefix |
| No SQS event | Incorrect event type |
| Destination validation fails | Invalid destination ARN or permissions |
| Destination validation fails | KMS permissions missing |
| Queue receives test event only | Object doesn't match rule |
| Events arrive late | Asynchronous delivery |
| Duplicate events | At-least-once delivery |
| Object key appears different | URL encoding in event record |
| Consumer sees no messages | Another consumer or visibility timeout |

---

## 17. Interview Questions and Answers

### Q1. What are S3 Event Notifications?

They allow Amazon S3 to publish notifications when supported operations occur on objects or buckets.

### Q2. Which services can receive S3 events?

Amazon SQS, Amazon SNS, AWS Lambda, and Amazon EventBridge.

### Q3. What permission does S3 need to publish to SQS?

The SQS queue policy must allow the S3 service principal to perform `sqs:SendMessage` for the intended source.

### Q4. Why did the notification fail in this lab?

The configured prefix was `upload/`, while the uploaded objects used `uploads/`.

### Q5. Can S3 send notifications directly to an SQS FIFO queue?

No. Direct S3 event notifications use standard SQS queues. EventBridge can be used for integration with FIFO queues.

### Q6. Does S3 guarantee that each event is delivered exactly once?

No. S3 notifications are designed for at-least-once delivery.

### Q7. Does correcting the notification rule publish events for old objects?

No. A new matching object operation is required to trigger a notification.

### Q8. What is `s3:TestEvent`?

It is a test notification used by S3 when enabling a destination configuration.

### Q9. Why might SQS contain a message even when the object filter is wrong?

The message could be an S3 configuration test event or an earlier notification. Always inspect its event type and object key.

### Q10. How would you explain this incident in an interview?

> An S3 upload succeeded, but the expected ObjectCreated notification did not arrive in an SQS queue. I verified the SQS destination permissions, event type, and S3 notification configuration. I found that the rule used the prefix upload/ while the application uploaded files under uploads/. I corrected the filter, uploaded a new test object, received its ObjectCreated event through SQS, and verified that unrelated prefixes remained excluded.

---

## 18. Cleanup

**Warning:** Perform these steps only for the isolated Lab 14 resources.

### Step 1 — Verify AWS Identity

```bash
aws sts get-caller-identity

echo "$BUCKET"
echo "$QUEUE_URL"
```

### Step 2 — Remove the S3 Notification Configuration

Create `empty-notification.json`:

```bash
cat > empty-notification.json <<'EOF'
{}
EOF
```

Apply:

```bash
aws s3api put-bucket-notification-configuration \
  --bucket "$BUCKET" \
  --notification-configuration file://empty-notification.json \
  --region "$AWS_REGION"
```

Verify:

```bash
aws s3api get-bucket-notification-configuration \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

Expected:

```json
{}
```

### Step 3 — Delete the SQS Queue

```bash
aws sqs delete-queue \
  --queue-url "$QUEUE_URL" \
  --region "$AWS_REGION"
```

This removes the lab queue and its messages.

### Step 4 — Inspect S3 Objects

```bash
aws s3 ls "s3://$BUCKET/" \
  --recursive \
  --region "$AWS_REGION"
```

Confirm the bucket contains only the lab objects.

### Step 5 — Delete Test Objects

```bash
aws s3api delete-object \
  --bucket "$BUCKET" \
  --key "uploads/report.txt" \
  --region "$AWS_REGION"
```

```bash
aws s3api delete-object \
  --bucket "$BUCKET" \
  --key "uploads/recovered-report.txt" \
  --region "$AWS_REGION"
```

```bash
aws s3api delete-object \
  --bucket "$BUCKET" \
  --key "archive/unrelated.txt" \
  --region "$AWS_REGION"
```

### Step 6 — Delete the Bucket

```bash
aws s3api delete-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION"
```

This assumes the bucket was created exclusively for this lab and versioning was not enabled.

---

## 19. Repository Structure

```text
14-s3-event-notification/
│
├── README.md
├── report.txt
├── recovered-report.txt
├── unrelated.txt
├── sqs-queue-policy.json
├── broken-notification.json
├── fixed-notification.json
└── check-notification.py
```

The source files provide a reproducible example of the broken configuration, corrected configuration, and notification verification process.

**GitHub security:** Review generated queue policies and notification configurations for account-specific identifiers. Do not commit AWS credentials, tokens, or sensitive event payloads.

---

## 20. Lessons Learned

This lab demonstrated that successful S3 uploads do not necessarily result in event notifications.

The issue was caused by a prefix mismatch in the notification configuration.

The investigation involved validating the S3 object, inspecting the event type and prefix filter, checking SQS permissions, and reviewing the destination configuration.

After correcting the prefix, a new object upload produced an event that could be verified by inspecting the SQS message.

The main lesson is to troubleshoot event filters, delivery permissions, and queue behavior separately.

---

## 21. Skills Demonstrated

- Amazon S3 troubleshooting
- Amazon SQS
- Event-driven architecture
- S3 ObjectCreated events
- Notification prefix filters
- SQS queue resource policies
- IAM-style service permissions
- AWS CLI v2
- Linux Bash
- Python 3
- SQS message polling
- Event payload inspection
- Root cause analysis
- Least-privilege security
- Production incident remediation
- Event delivery verification

## Final Outcome

| Item | Expected Result |
|---|---|
| Incident | INC-S3-014 |
| Services | Amazon S3 + Amazon SQS |
| Problem | Missing ObjectCreated notification |
| Root Cause | Incorrect prefix filter |
| Broken Prefix | `upload/` |
| Correct Prefix | `uploads/` |
| Remediation | Update notification configuration |
| Verification | Matching SQS event received |
| Unrelated Objects | Excluded |
| Bucket Security | Block Public Access preserved |
| Expected Lab Status | Resolved |

**Key Takeaway:** When an S3 event notification does not trigger, verify the exact event type, object key filters, destination permissions, and Region. A successful upload alone does not prove that a notification should have been generated.
