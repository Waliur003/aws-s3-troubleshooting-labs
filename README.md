# AWS S3 Troubleshooting Labs

## Overview

This repository contains hands-on troubleshooting labs for Amazon Simple Storage Service (S3).

The goal is to understand common AWS S3 problems that Cloud Engineers, Cloud Operations Engineers, DevOps Engineers, and Cloud Security Engineers face in real environments.

Instead of only learning how to create S3 buckets and upload objects, this repository focuses on breaking configurations, investigating error messages, finding root causes, applying fixes, and verifying the results.

## Objectives

- Understand common S3 errors and their causes.
- Learn troubleshooting using AWS CLI and AWS Console.
- Diagnose S3 bucket and object access problems.
- Troubleshoot bucket configurations and security controls.
- Investigate encryption, versioning, lifecycle, and replication problems.
- Develop systematic troubleshooting skills for cloud engineering interviews.

## Tools and Technologies

- Amazon S3
- AWS CLI
- AWS Management Console
- PowerShell / Bash
- AWS CloudTrail
- AWS CloudWatch
- AWS KMS
- Git and GitHub

## Repository Structure

```text
aws-s3-troubleshooting-labs/
│
├── README.md
├── 01-s3-bucket-not-found/
├── 02-s3-object-not-found/
├── 03-s3-upload-access-denied/
├── 04-s3-download-403/
├── 05-s3-wrong-region/
├── 06-s3-website-404/
├── 07-s3-bucket-policy/
├── 08-s3-block-public-access/
├── 09-s3-versioning-delete-marker/
├── 10-s3-cors-error/
├── 11-s3-presigned-url/
├── 12-s3-kms-encryption/
├── 13-s3-lifecycle-failure/
├── 14-s3-event-notification/
└── 15-s3-replication-failure/
```

## Lab Methodology

Every lab follows the same engineering workflow:

1. **Objective:** Understand the problem and expected outcome.
2. **Architecture:** Understand the AWS resources involved.
3. **Prerequisites:** Prepare AWS CLI and required permissions.
4. **Working Setup:** Create a functioning environment.
5. **Simulate Failure:** Deliberately introduce a configuration error.
6. **Observe Symptoms:** Capture actual error messages.
7. **Investigate:** Examine configurations, CLI output, and logs.
8. **Root Cause:** Explain exactly why the failure occurred.
9. **Remediation:** Apply the appropriate fix.
10. **Verification:** Confirm the original operation succeeds.
11. **Interview Questions:** Practice explaining the incident.
12. **Cleanup:** Remove resources and avoid unnecessary charges.

## Troubleshooting Principles

Never change random configurations without understanding the problem.

Follow this process:

```text
Observe Error
     |
Collect Evidence
     |
Identify AWS API Operation
     |
Inspect Configuration
     |
Form Hypothesis
     |
Test Hypothesis
     |
Apply Remediation
     |
Verify Solution
     |
Document Root Cause
```

## Common Troubleshooting Commands

Check AWS identity:

```bash
aws sts get-caller-identity
```

List accessible buckets:

```bash
aws s3 ls
```

List objects:

```bash
aws s3 ls s3://BUCKET_NAME
```

Inspect bucket region:

```bash
aws s3api get-bucket-location --bucket BUCKET_NAME
```

Inspect bucket versioning:

```bash
aws s3api get-bucket-versioning --bucket BUCKET_NAME
```

Inspect bucket public access settings:

```bash
aws s3api get-public-access-block --bucket BUCKET_NAME
```

Inspect bucket encryption:

```bash
aws s3api get-bucket-encryption --bucket BUCKET_NAME
```

Use detailed CLI output:

```bash
aws s3 ls --debug
```

**Note:** Debug output can include sensitive request details. Do not publish raw debug logs without reviewing them.

## Security and Cost Guidelines

- Use only AWS accounts and resources you are authorized to manage.
- Keep S3 Block Public Access enabled unless an isolated lab explicitly requires a carefully controlled exception.
- Never upload AWS access keys, passwords, or sensitive information.
- Use unique lab bucket names.
- Use small test objects.
- Clean up test resources after each lab.
- Be aware that S3 requests, storage, replication, and KMS operations can incur charges.
- Do not test destructive changes on production buckets.

## Expected Learning Outcomes

After completing these labs, I should be able to:

- Diagnose bucket and object errors.
- Investigate access failures.
- Differentiate missing objects from permission problems.
- Troubleshoot encryption and versioning.
- Identify S3 configuration issues.
- Explain S3 troubleshooting scenarios in technical interviews.
- Document incidents clearly using symptoms, root causes, fixes, and verification evidence.

## Career Relevance

These labs prepare me for troubleshooting responsibilities commonly associated with:

- Cloud Engineer
- Cloud Operations Engineer
- AWS Cloud Engineer
- DevOps Engineer
- Platform Engineer
- Cloud Security Engineer

## Completion Status

15 labs planned. Update each lab's status after completing and verifying it.

## Final Goal

Develop the ability to troubleshoot common Amazon S3 failures confidently, using real AWS commands, evidence-based investigation, safe remediation, and clear documentation.
