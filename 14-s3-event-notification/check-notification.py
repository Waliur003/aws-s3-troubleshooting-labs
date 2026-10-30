import json
import os
import subprocess
import sys

queue_url = os.environ["QUEUE_URL"]
region = os.environ["AWS_REGION"]
expected_key = "uploads/recovered-report.txt"

for attempt in range(1, 7):
    result = subprocess.run(
        [
            "aws", "sqs", "receive-message",
            "--queue-url", queue_url,
            "--max-number-of-messages", "10",
            "--wait-time-seconds", "10",
            "--region", region,
            "--output", "json",
        ],
        capture_output=True,
        text=True,
        check=True,
    )

    response = json.loads(result.stdout or "{}")
    messages = response.get("Messages", [])

    print(f"Polling attempt {attempt}: {len(messages)} message(s)")

    for message in messages:
        body = json.loads(message["Body"])

        if body.get("Event") == "s3:TestEvent":
            print("Received S3 configuration test event")
            continue

        for record in body.get("Records", []):
            event_name = record.get("eventName", "")
            object_key = record.get("s3", {}).get("object", {}).get("key", "")

            from urllib.parse import unquote_plus
            object_key = unquote_plus(object_key)

            print(f"Event: {event_name}")
            print(f"Object: {object_key}")

            if (
                event_name.startswith("ObjectCreated:")
                and object_key == expected_key
            ):
                print("SUCCESS: Expected S3 event received")
                sys.exit(0)

print("Expected notification not observed.")
print("Recheck the filter, queue policy, and delivery status.")
sys.exit(1)