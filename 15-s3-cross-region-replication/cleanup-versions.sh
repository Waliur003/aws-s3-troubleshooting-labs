#!/usr/bin/env bash
set -euo pipefail

BUCKET="$1"
REGION="$2"
KEY="reports/replication-report.txt"

echo "Target bucket: $BUCKET"
echo "Target region: $REGION"
echo "Target key: $KEY"

if [[ "$BUCKET" != cloud-lab15-* ]]; then
  echo "Unexpected bucket name. Aborting."
  exit 1
fi

aws s3api list-object-versions \
  --bucket "$BUCKET" \
  --prefix "$KEY" \
  --region "$REGION" \
  --output json |
python3 -c '
import json, sys

data = json.load(sys.stdin)
key = "reports/replication-report.txt"

for field in ("Versions", "DeleteMarkers"):
    for item in data.get(field, []):
        if item["Key"] == key:
            print(item["VersionId"])
' |
while IFS= read -r VERSION_ID; do
  [[ -z "$VERSION_ID" ]] && continue

  aws s3api delete-object \
    --bucket "$BUCKET" \
    --key "$KEY" \
    --version-id "$VERSION_ID" \
    --region "$REGION"
done
