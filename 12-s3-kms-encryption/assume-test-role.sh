#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "Usage: ./assume-test-role.sh aws COMMAND..."
  exit 1
fi

unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

CREDS=$(aws sts assume-role \
  --role-arn "$ROLE_ARN" \
  --role-session-name Lab12KMSReader \
  --query Credentials \
  --output json)

export AWS_ACCESS_KEY_ID=$(python3 -c \
  'import sys,json; print(json.load(sys.stdin)["AccessKeyId"])' <<< "$CREDS")

export AWS_SECRET_ACCESS_KEY=$(python3 -c \
  'import sys,json; print(json.load(sys.stdin)["SecretAccessKey"])' <<< "$CREDS")

export AWS_SESSION_TOKEN=$(python3 -c \
  'import sys,json; print(json.load(sys.stdin)["SessionToken"])' <<< "$CREDS")

exec "$@"
