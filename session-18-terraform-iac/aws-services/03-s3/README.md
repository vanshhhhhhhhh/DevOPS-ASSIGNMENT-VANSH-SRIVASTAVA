# Amazon S3 (Simple Storage Service)

**Name:** Vansh Srivastava | **Enrollment No.:** 24bcs10567 | **Session:** 18, Task 2

## What is S3

S3 is object storage: you store whole files ("objects") under a name and fetch them back over HTTPS. There are no disks to size or servers to run. You pay for the GB stored per month, for requests and for data transferred out. AWS stores every object redundantly across several Availability Zones (except the One Zone classes) and designs for 99.999999999% (11 nines) durability.

S3 is not a file system. You cannot edit part of an object in place or mount it like a disk. You always replace the whole object.

## Buckets

A bucket is the container for objects.

- **Names are global** across all AWS accounts: 3-63 characters, lowercase letters, digits, dots and hyphens. That is why my bucket names include my enrollment number.
- A bucket is created in **one region** and its data stays there unless you replicate it.
- Settings such as versioning, encryption, lifecycle rules, the bucket policy, Block Public Access, logging and replication are set per bucket.
- Since April 2023, new buckets have Block Public Access turned on and ACLs disabled by default.

## Objects

An object is:

- a **key**, its full name, e.g. `reports/2026/q3.csv`
- the **data** (any bytes)
- **metadata**: system metadata like `Content-Type` and `ETag`, plus your own `x-amz-meta-*` headers
- optional **tags**, and a **version ID** when versioning is on

There are no real folders. `reports/` is just a key prefix that the console shows as a folder. A single PUT can upload up to 5 GB; bigger files use **multipart upload**, which sends parts in parallel and can retry only the failed parts.

## Storage classes

Pick a class by how often the data is read and how fast you need it back. Cheaper storage means higher per-GB retrieval cost, or slower retrieval.

| Class | Access pattern | Retrieval | Notes |
|---|---|---|---|
| S3 Standard | frequent | milliseconds | default |
| S3 Intelligent-Tiering | unknown or changing | milliseconds (optional archive tiers are slower) | moves objects between tiers automatically for a small monitoring fee |
| S3 Standard-IA | infrequent, but needs fast access | milliseconds, per-GB retrieval fee | 30-day minimum storage charge |
| S3 One Zone-IA | infrequent, easy to recreate | milliseconds | stored in one AZ only |
| S3 Express One Zone | very hot, latency-sensitive | single-digit ms | special "directory" buckets in one AZ |
| S3 Glacier Instant Retrieval | archive read about once a quarter | milliseconds | 90-day minimum |
| S3 Glacier Flexible Retrieval | archive | minutes to hours | 90-day minimum |
| S3 Glacier Deep Archive | long-term compliance archive | within 12 hours (bulk up to 48) | cheapest, 180-day minimum |

## Versioning

With versioning **enabled**, S3 keeps every version of an object:

- Overwriting a key creates a new version. The old one stays and can be restored.
- A plain delete only adds a **delete marker** on top. The data is still there until you delete the specific version IDs.
- Once enabled, versioning can only be **suspended**, never fully turned off.
- MFA Delete can additionally require an MFA code to delete versions.

It protects against accidental overwrites, deletes and ransomware-style changes, and it is required for replication. The cost is that you pay for every stored version, so it is normally combined with a lifecycle rule that expires old versions.

## Lifecycle policies

Lifecycle rules make S3 move or delete objects by age, for a whole bucket or for a prefix or tag filter:

- **Transition** actions: Standard -> Standard-IA after 30 days -> Glacier after 90 days, and so on.
- **Expiration** actions: delete current objects after N days, delete **noncurrent versions** N days after they are replaced, and remove expired delete markers.
- **Abort incomplete multipart uploads** after N days, so you stop paying for half-uploaded parts.

Typical use: application logs that are hot for a month, kept cheaply for a year, then deleted.

## Encryption

- **At rest**: since January 2023 every new object is encrypted by default with **SSE-S3** (AES-256, keys managed by S3). Other options are **SSE-KMS** (keys in AWS KMS, with separate key permissions and an audit trail in CloudTrail; S3 Bucket Keys reduce the KMS cost), **DSSE-KMS** (two layers) and **SSE-C** (you send the key with each request). Client-side encryption is also possible.
- **In transit**: use HTTPS. A bucket policy can deny any request that is not over TLS (example below).
- The bucket's *default encryption* setting decides what happens when an upload does not ask for anything specific.

## Bucket policies

A bucket policy is a **resource-based** IAM policy attached to the bucket. Unlike identity policies, it has a `Principal` element, so it can grant access to other accounts, AWS services or (if Block Public Access allows it) everyone. Common uses:

- deny non-TLS requests or uploads without encryption
- allow a CloudFront distribution (through Origin Access Control) to read a private bucket
- give another AWS account read access
- restrict access to a VPC endpoint or to the organisation

The policy I used below ([`bucket-policy.json`](bucket-policy.json)) denies every request made over plain HTTP:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyPlainHttp",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::s18-research-bucket",
        "arn:aws:s3:::s18-research-bucket/*"
      ],
      "Condition": { "Bool": { "aws:SecureTransport": "false" } }
    }
  ]
}
```

Access is allowed only when some identity or bucket policy allows it and no policy denies it. Block Public Access sits on top of both and overrides anything that would make data public.

## Use cases

- Static website assets and media behind CloudFront
- Backups and disaster-recovery copies (with versioning, Object Lock and cross-region replication)
- Data lakes for analytics (Athena, EMR, Redshift Spectrum)
- Log archives (CloudTrail, VPC Flow Logs, load balancer and application logs)
- Build artifacts and deployment packages, Terraform remote state (see my Session 19 README)
- User uploads in web and mobile apps, often through pre-signed URLs

## Hands-on: versioning, storage classes, lifecycle and a bucket policy on LocalStack

`awsl` is my wrapper that runs the AWS CLI against LocalStack (see the [session README](../../README.md#localstack-setup)).

Create a bucket in `ap-south-1`, turn on versioning and upload two objects, one of them straight into Standard-IA:

```bash
$ awsl s3api create-bucket --bucket s18-research-bucket --create-bucket-configuration LocationConstraint=ap-south-1
{
    "Location": "http://s18-research-bucket.s3.localhost.localstack.cloud:4566/",
    "BucketArn": "arn:aws:s3:::s18-research-bucket"
}

$ awsl s3api put-bucket-versioning --bucket s18-research-bucket --versioning-configuration Status=Enabled

$ echo 'app log line' | awsl s3 cp - s3://s18-research-bucket/logs/app.log

$ echo 'quarterly numbers' | awsl s3 cp - s3://s18-research-bucket/reports/q3.csv --storage-class STANDARD_IA

$ awsl s3api list-objects-v2 --bucket s18-research-bucket --query 'Contents[].{Key:Key,Size:Size,StorageClass:StorageClass}' --output table
--------------------------------------------
|               ListObjectsV2              |
+-----------------+-------+----------------+
|       Key       | Size  | StorageClass   |
+-----------------+-------+----------------+
|  logs/app.log   |  13   |  STANDARD      |
|  reports/q3.csv |  18   |  STANDARD_IA   |
+-----------------+-------+----------------+

$ awsl s3api head-object --bucket s18-research-bucket --key reports/q3.csv --query '{SSE:ServerSideEncryption,StorageClass:StorageClass,VersionId:VersionId}'
{
    "SSE": "AES256",
    "StorageClass": "STANDARD_IA",
    "VersionId": "AaEXf0VQo2Glj0jlAUjtVmhiYrZxCJlJ"
}
```

`q3.csv` is in `STANDARD_IA` as requested. It is encrypted with AES256 (SSE-S3) by default and has a version ID because versioning is on.

Lifecycle rule from [`lifecycle.json`](lifecycle.json): objects under `logs/` move to Standard-IA after 30 days and to Glacier after 90, are deleted after 365 days, and old versions are removed 30 days after being replaced:

```bash
$ awsl s3api put-bucket-lifecycle-configuration --bucket s18-research-bucket --lifecycle-configuration file://lifecycle.json
{
    "TransitionDefaultMinimumObjectSize": "all_storage_classes_128K"
}

$ awsl s3api get-bucket-lifecycle-configuration --bucket s18-research-bucket --query 'Rules[].{ID:ID,Prefix:Filter.Prefix,Transitions:Transitions,ExpireDays:Expiration.Days}'
[
    {
        "ID": "logs-tiering-and-cleanup",
        "Prefix": "logs/",
        "Transitions": [
            {
                "Days": 30,
                "StorageClass": "STANDARD_IA"
            },
            {
                "Days": 90,
                "StorageClass": "GLACIER"
            }
        ],
        "ExpireDays": 365
    }
]
```

LocalStack stores and returns the rule, but it does not actually move objects between classes as time passes. Only real S3 does that.

Bucket policy that denies plain HTTP:

```bash
$ awsl s3api put-bucket-policy --bucket s18-research-bucket --policy file://bucket-policy.json

$ awsl s3api get-bucket-policy --bucket s18-research-bucket --query Policy --output text | jq '.Statement[0] | {Sid, Effect, Condition}'
{
  "Sid": "DenyPlainHttp",
  "Effect": "Deny",
  "Condition": {
    "Bool": {
      "aws:SecureTransport": "false"
    }
  }
}
```

### Deleting a versioned bucket

This part surprised me, so I kept it in. `rb --force` deletes the objects and then the bucket, but on a versioned bucket it fails:

```bash
$ awsl s3 rb s3://s18-research-bucket --force
delete: s3://s18-research-bucket/logs/app.log
delete: s3://s18-research-bucket/reports/q3.csv
remove_bucket failed: s3://s18-research-bucket An error occurred (BucketNotEmpty) when calling the DeleteBucket operation: The bucket you tried to delete is not empty. You must delete all versions in the bucket.
[exit code 1]

$ awsl s3api list-object-versions --bucket s18-research-bucket --query '{Versions: Versions[].[Key, VersionId, IsLatest], DeleteMarkers: DeleteMarkers[].[Key, VersionId, IsLatest]}' --output json
{
    "Versions": [
        [
            "logs/app.log",
            "AaEXf0VPsO4dB.LZ51Bw48z8M2JuG36J",
            false
        ],
        [
            "reports/q3.csv",
            "AaEXf0VQo2Glj0jlAUjtVmhiYrZxCJlJ",
            false
        ]
    ],
    "DeleteMarkers": [
        [
            "logs/app.log",
            "AaEXf0VR4scIszQsI79nmuKNEZ2ZbKAZ",
            true
        ],
        [
            "reports/q3.csv",
            "AaEXf0VSnNjktWZoj1tQj8V_IQs08KIJ",
            true
        ]
    ]
}
```

The "deletes" only added delete markers (`IsLatest: true`). The real versions were still there, so the bucket was not empty. Every version and every marker has to be deleted by version ID first:

```bash
$ awsl s3api delete-objects --bucket s18-research-bucket --delete "$(awsl s3api list-object-versions --bucket s18-research-bucket --query '{Objects: [Versions, DeleteMarkers][].{Key: Key, VersionId: VersionId}}' --output json)" --query 'Deleted[].{Key:Key,VersionId:VersionId,DeleteMarker:DeleteMarker}' --output table
------------------------------------------------------------------------
|                             DeleteObjects                            |
+--------------+------------------+------------------------------------+
| DeleteMarker |       Key        |             VersionId              |
+--------------+------------------+------------------------------------+
|  None        |  logs/app.log    |  AaEXf0VPsO4dB.LZ51Bw48z8M2JuG36J  |
|  None        |  reports/q3.csv  |  AaEXf0VQo2Glj0jlAUjtVmhiYrZxCJlJ  |
|  True        |  logs/app.log    |  AaEXf0VR4scIszQsI79nmuKNEZ2ZbKAZ  |
|  True        |  reports/q3.csv  |  AaEXf0VSnNjktWZoj1tQj8V_IQs08KIJ  |
+--------------+------------------+------------------------------------+

$ awsl s3api delete-bucket --bucket s18-research-bucket

$ awsl s3 ls
```

This is also why the Terraform buckets in Task 1 and Session 19 use `force_destroy = true`: it makes Terraform delete all versions before it deletes the bucket.
