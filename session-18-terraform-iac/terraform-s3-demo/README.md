# Terraform S3 Demo

**Name:** Vansh Srivastava
**Enrollment No.:** 24bcs10567
**Session:** 18, Task 1

This project creates one S3 bucket with Terraform and applies the usual good-practice settings to it: versioning, default encryption, a public access block and tags. I ran it against LocalStack, a local AWS emulator in Docker, instead of a real AWS account. The same code works on real AWS once one variable is changed (see [Switching to real AWS](#switching-to-real-aws)).

## Files

```text
terraform-s3-demo/
├── provider.tf          # terraform block (version pins) + aws provider with the LocalStack/AWS switch
├── variables.tf         # input variables with types, defaults and a bucket-name validation rule
├── terraform.tfvars     # values I used (bucket name, region, use_localstack = true)
├── main.tf              # bucket, versioning, encryption, public access block
├── outputs.tf           # bucket name/ARN/region, versioning status, encryption algorithm, target
├── .terraform.lock.hcl  # provider version + checksums written by terraform init (committed)
└── README.md
```

`.terraform/`, `terraform.tfstate*` and saved plans are ignored by `../.gitignore`.

### What gets created

| Resource | Why |
|---|---|
| `aws_s3_bucket.demo` | The bucket. `force_destroy = true` so `terraform destroy` can delete it even when it still holds objects. |
| `aws_s3_bucket_versioning.demo` | Keeps old versions when an object is overwritten or deleted. |
| `aws_s3_bucket_server_side_encryption_configuration.demo` | Encrypts every new object with SSE-S3 (AES-256). |
| `aws_s3_bucket_public_access_block.demo` | Blocks public ACLs and public bucket policies. |

Since AWS provider v4, versioning, encryption and the public access block are separate resources instead of blocks inside `aws_s3_bucket`. Each one references `aws_s3_bucket.demo.id`, which gives Terraform an implicit dependency: the bucket is created first and deleted last.

Tags come from two places: `tags` on the bucket (`Name`, `Environment`) and `default_tags` in the provider (`Project`, `Owner`, `ManagedBy`). `tags_all` in the plan shows the merged set.

### Provider: LocalStack or real AWS

```hcl
provider "aws" {
  region = var.aws_region

  access_key = var.use_localstack ? "test" : null
  secret_key = var.use_localstack ? "test" : null

  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_requesting_account_id  = var.use_localstack
  s3_use_path_style           = var.use_localstack

  dynamic "endpoints" {
    for_each = var.use_localstack ? [1] : []
    content {
      s3  = var.localstack_endpoint
      sts = var.localstack_endpoint
    }
  }
  ...
}
```

- With `use_localstack = true` the provider uses the fake credentials `test`/`test`, skips the STS and EC2-metadata calls that only make sense on real AWS, and sends S3 and STS calls to `http://localhost:4566`.
- `s3_use_path_style` makes the provider call `http://localhost:4566/<bucket>` instead of `http://<bucket>.localhost:4566`, which needs no wildcard DNS.
- With `use_localstack = false` every one of those arguments becomes `null`/`false`, the `endpoints` block disappears, and the provider behaves like a plain `provider "aws" { region = ... }`, using the normal credential chain (`aws configure`, `AWS_PROFILE`, SSO, env vars).

### Switching to real AWS

1. In `terraform.tfvars` set `use_localstack = false`.
2. Change `bucket_name` to something globally unique (S3 names are shared by every AWS account).
3. Run `aws configure` (or `export AWS_PROFILE=...`) and check it with `aws sts get-caller-identity`.
4. Run the same `terraform init / plan / apply / destroy` commands as below.

You can also leave the file alone and override it on the command line: `terraform apply -var use_localstack=false -var bucket_name=<your-unique-name>`.

## Environment

macOS 26 on arm64, Docker via Colima, Terraform v1.16.4, hashicorp/aws provider v6.67.0 (constraint `~> 6.0`), LocalStack Community 4.14.0 in the container `localstack` on `127.0.0.1:4566`, AWS CLI v2.37.10 from the `amazon/aws-cli` image. The session [README](../README.md#localstack-setup) explains why I pinned LocalStack 4.14.0.

I did not install the AWS CLI on the Mac. I run the official image instead, joined to the LocalStack container's network so `localhost:4566` inside it is LocalStack:

```bash
awsl() {
  docker run --rm -i --network container:localstack -v "$PWD":/aws \
    -e AWS_ACCESS_KEY_ID=test -e AWS_SECRET_ACCESS_KEY=test -e AWS_DEFAULT_REGION=ap-south-1 \
    amazon/aws-cli:2.37.10 --endpoint-url http://localhost:4566 "$@"
}
```

Every `awsl ...` command below is that function. On real AWS it would just be `aws ...`.

```bash
$ docker ps --filter name=localstack --format '{{.Names}}  {{.Image}}  {{.Status}}  {{.Ports}}'
localstack  localstack/localstack:4.14.0  Up 5 minutes (healthy)  4510-4559/tcp, 5678/tcp, 127.0.0.1:4566->4566/tcp

$ curl -s localhost:4566/_localstack/health | jq '{edition, version, s3: .services.s3, sts: .services.sts}'
{
  "edition": "community",
  "version": "4.14.0",
  "s3": "running",
  "sts": "running"
}

$ awsl sts get-caller-identity
{
    "UserId": "AKIAIOSFODNN7EXAMPLE",
    "Account": "000000000000",
    "Arn": "arn:aws:iam::000000000000:root"
}
```

LocalStack accepts any credentials and pretends to be account `000000000000`.

## Workflow with real output

All commands were run from this folder. Output is copied from my terminal. Where it was long I cut lines and marked the cut with `...`.

### 1. terraform init

```bash
$ terraform init
Initializing the backend...

Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 6.0"...
- Installing hashicorp/aws v6.67.0...
- Installed hashicorp/aws v6.67.0 (signed by HashiCorp)

Terraform has created a lock file .terraform.lock.hcl to record the provider
selections it made above. Include this file in your version control repository
so that Terraform can guarantee to make the same selections by default when
you run "terraform init" in the future.

Terraform has been successfully initialized!

You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.

If you ever set or change modules or backend configuration for Terraform,
rerun this command to reinitialize your working directory. If you forget, other
commands will detect it and remind you to do so if necessary.
```

`init` downloaded the AWS provider matching `~> 6.0` (6.67.0 was the newest) and wrote `.terraform.lock.hcl` with its checksums. The lock file is committed so anyone who clones the repo gets exactly 6.67.0. The provider binary itself goes into `.terraform/`, which is gitignored.

### 2. terraform fmt

```bash
$ terraform fmt

$ terraform fmt -check && echo 'fmt -check: nothing left to format'
fmt -check: nothing left to format
```

No file names were printed, so every file was already in canonical format. `fmt` only prints the files it rewrites. To see it actually change something, I gave it a badly formatted file in a scratch folder:

```bash
$ terraform fmt -diff messy.tf
messy.tf
--- old/messy.tf
+++ new/messy.tf
@@ -1,6 +1,6 @@
 resource "aws_s3_bucket" "messy" {
-bucket="fmt-demo"
-    force_destroy=true
-tags={Name="fmt-demo"
-Environment="dev"}
+  bucket        = "fmt-demo"
+  force_destroy = true
+  tags = { Name = "fmt-demo"
+  Environment = "dev" }
 }
```

It fixes indentation and aligns the `=` signs. It does not restructure the inline map. That is a style choice left to me.

### 3. terraform validate

```bash
$ terraform validate
Success! The configuration is valid.
```

`validate` checks syntax, types and references without calling AWS. The `bucket_name` validation rule in `variables.tf` would also fail here if the name broke S3 naming rules.

### 4. terraform plan

I saved the plan to a file, so the apply step runs exactly what I reviewed:

```bash
$ terraform plan -out=tfplan
Terraform used the selected providers to generate the following execution
plan. Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # aws_s3_bucket.demo will be created
  + resource "aws_s3_bucket" "demo" {
      + acceleration_status         = (known after apply)
      + acl                         = (known after apply)
      + arn                         = (known after apply)
      + bucket                      = "vansh-24bcs10567-tf-s3-demo"
      + bucket_domain_name          = (known after apply)
      + bucket_namespace            = (known after apply)
      + bucket_prefix               = (known after apply)
      + bucket_region               = (known after apply)
      + bucket_regional_domain_name = (known after apply)
      + force_destroy               = true
      + hosted_zone_id              = (known after apply)
      + id                          = (known after apply)
      + object_lock_enabled         = (known after apply)
      + policy                      = (known after apply)
      + region                      = "ap-south-1"
      + request_payer               = (known after apply)
      + tags                        = {
          + "Environment" = "dev"
          + "Name"        = "vansh-24bcs10567-tf-s3-demo"
        }
      + tags_all                    = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
          + "Name"        = "vansh-24bcs10567-tf-s3-demo"
          + "Owner"       = "vansh-srivastava"
          + "Project"     = "session-18-terraform-s3-demo"
        }
      + website_domain              = (known after apply)
      + website_endpoint            = (known after apply)

      + cors_rule (known after apply)

      + grant (known after apply)

      + lifecycle_rule (known after apply)

      + logging (known after apply)

      + object_lock_configuration (known after apply)

      + replication_configuration (known after apply)

      + server_side_encryption_configuration (known after apply)

      + versioning (known after apply)

      + website (known after apply)
    }

  # aws_s3_bucket_public_access_block.demo will be created
  + resource "aws_s3_bucket_public_access_block" "demo" {
      + block_public_acls       = true
      + block_public_policy     = true
      + bucket                  = (known after apply)
      + id                      = (known after apply)
      + ignore_public_acls      = true
      + region                  = "ap-south-1"
      + restrict_public_buckets = true
    }

  # aws_s3_bucket_server_side_encryption_configuration.demo will be created
  + resource "aws_s3_bucket_server_side_encryption_configuration" "demo" {
      + bucket = (known after apply)
      + id     = (known after apply)
      + region = "ap-south-1"

      + rule {
          + blocked_encryption_types = (known after apply)
          + bucket_key_enabled       = (known after apply)

          + apply_server_side_encryption_by_default {
              + kms_master_key_id = (known after apply)
              + sse_algorithm     = "AES256"
            }
        }
    }

  # aws_s3_bucket_versioning.demo will be created
  + resource "aws_s3_bucket_versioning" "demo" {
      + bucket = (known after apply)
      + id     = (known after apply)
      + region = "ap-south-1"

      + versioning_configuration {
          + mfa_delete = (known after apply)
          + status     = "Enabled"
        }
    }

Plan: 4 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + bucket_arn           = (known after apply)
  + bucket_name          = "vansh-24bcs10567-tf-s3-demo"
  + bucket_region        = "ap-south-1"
  + encryption_algorithm = "AES256"
  + target               = "LocalStack (http://localhost:4566)"
  + versioning_status    = "Enabled"

─────────────────────────────────────────────────────────────────────────────

Saved the plan to: tfplan

To perform exactly these actions, run the following command to apply:
    terraform apply "tfplan"
```

`+` means create. Four resources will be added and nothing changed or destroyed. Values like `arn` are `(known after apply)` because only AWS (here LocalStack) can tell Terraform what they are. `tags_all` shows the bucket tags merged with the provider `default_tags`.

### 5. terraform apply

```bash
$ terraform apply tfplan
aws_s3_bucket.demo: Creating...
aws_s3_bucket.demo: Creation complete after 0s [id=vansh-24bcs10567-tf-s3-demo]
aws_s3_bucket_versioning.demo: Creating...
aws_s3_bucket_public_access_block.demo: Creating...
aws_s3_bucket_server_side_encryption_configuration.demo: Creating...
aws_s3_bucket_public_access_block.demo: Creation complete after 0s [id=vansh-24bcs10567-tf-s3-demo]
aws_s3_bucket_server_side_encryption_configuration.demo: Creation complete after 0s [id=vansh-24bcs10567-tf-s3-demo]
aws_s3_bucket_versioning.demo: Creation complete after 1s [id=vansh-24bcs10567-tf-s3-demo]

Apply complete! Resources: 4 added, 0 changed, 0 destroyed.

Outputs:

bucket_arn = "arn:aws:s3:::vansh-24bcs10567-tf-s3-demo"
bucket_name = "vansh-24bcs10567-tf-s3-demo"
bucket_region = "ap-south-1"
encryption_algorithm = "AES256"
target = "LocalStack (http://localhost:4566)"
versioning_status = "Enabled"
```

Because I passed the saved plan, Terraform did not ask for `yes`. Without a plan file, `terraform apply` prints the plan again and waits for `yes`. The order matters: the bucket was created first, then the three settings resources in parallel, because each of them references `aws_s3_bucket.demo.id`.

### 6. terraform show

```bash
$ terraform show
# aws_s3_bucket.demo:
resource "aws_s3_bucket" "demo" {
    acceleration_status         = null
    arn                         = "arn:aws:s3:::vansh-24bcs10567-tf-s3-demo"
    bucket                      = "vansh-24bcs10567-tf-s3-demo"
    bucket_domain_name          = "vansh-24bcs10567-tf-s3-demo.s3.amazonaws.com"
    bucket_namespace            = "global"
    bucket_prefix               = null
    bucket_region               = "ap-south-1"
    bucket_regional_domain_name = "vansh-24bcs10567-tf-s3-demo.s3.ap-south-1.amazonaws.com"
    force_destroy               = true
    hosted_zone_id              = "Z11RGJOFQNVJUP"
    id                          = "vansh-24bcs10567-tf-s3-demo"
    object_lock_enabled         = false
    policy                      = null
    region                      = "ap-south-1"
    request_payer               = "BucketOwner"
    tags                        = {
        "Environment" = "dev"
        "Name"        = "vansh-24bcs10567-tf-s3-demo"
    }
    tags_all                    = {
        "Environment" = "dev"
        "ManagedBy"   = "Terraform"
        "Name"        = "vansh-24bcs10567-tf-s3-demo"
        "Owner"       = "vansh-srivastava"
        "Project"     = "session-18-terraform-s3-demo"
    }

    grant {
        id          = "75aa57f09aa0c8caeab4f8c24e99d10f8e7faeebf76c078efc7c6caea54ba06a"
        permissions = [
            "FULL_CONTROL",
        ]
        type        = "CanonicalUser"
        uri         = null
    }

    server_side_encryption_configuration {
        rule {
            bucket_key_enabled = false

            apply_server_side_encryption_by_default {
                kms_master_key_id = null
                sse_algorithm     = "AES256"
            }
        }
    }

    versioning {
        enabled    = false
        mfa_delete = false
    }
}
...
# aws_s3_bucket_versioning.demo:
resource "aws_s3_bucket_versioning" "demo" {
    bucket                = "vansh-24bcs10567-tf-s3-demo"
    expected_bucket_owner = null
    id                    = "vansh-24bcs10567-tf-s3-demo"
    region                = "ap-south-1"

    versioning_configuration {
        mfa_delete = "Disabled"
        status     = "Enabled"
    }
}


Outputs:

bucket_arn = "arn:aws:s3:::vansh-24bcs10567-tf-s3-demo"
bucket_name = "vansh-24bcs10567-tf-s3-demo"
bucket_region = "ap-south-1"
encryption_algorithm = "AES256"
target = "LocalStack (http://localhost:4566)"
versioning_status = "Enabled"
```

`show` prints what is now recorded in the state file. One thing confused me at first: the bucket's own `versioning { enabled = false }`. That block is the old, read-only view of versioning, and it was read when the bucket was created, before `aws_s3_bucket_versioning` switched versioning on. The `aws_s3_bucket_versioning.demo` entry and the AWS CLI below both show `Enabled`, and after the next refresh the bucket block showed `enabled = true` too (see the destroy plan).

### 7. terraform output

```bash
$ terraform output
bucket_arn = "arn:aws:s3:::vansh-24bcs10567-tf-s3-demo"
bucket_name = "vansh-24bcs10567-tf-s3-demo"
bucket_region = "ap-south-1"
encryption_algorithm = "AES256"
target = "LocalStack (http://localhost:4566)"
versioning_status = "Enabled"

$ terraform output -raw bucket_arn; echo
arn:aws:s3:::vansh-24bcs10567-tf-s3-demo

$ terraform state list
aws_s3_bucket.demo
aws_s3_bucket_public_access_block.demo
aws_s3_bucket_server_side_encryption_configuration.demo
aws_s3_bucket_versioning.demo
```

`-raw` prints just the value without quotes, which is handy in scripts.

### 8. Check the bucket with the AWS CLI (between apply and destroy)

```bash
$ awsl s3 ls
2026-10-07 17:52:50 vansh-24bcs10567-tf-s3-demo

$ awsl s3api head-bucket --bucket vansh-24bcs10567-tf-s3-demo
{
    "BucketArn": "arn:aws:s3:::vansh-24bcs10567-tf-s3-demo",
    "BucketRegion": "ap-south-1"
}

$ awsl s3api get-bucket-versioning --bucket vansh-24bcs10567-tf-s3-demo
{
    "Status": "Enabled"
}

$ awsl s3api get-bucket-encryption --bucket vansh-24bcs10567-tf-s3-demo
{
    "ServerSideEncryptionConfiguration": {
        "Rules": [
            {
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                },
                "BucketKeyEnabled": false
            }
        ]
    }
}

$ awsl s3api get-public-access-block --bucket vansh-24bcs10567-tf-s3-demo
{
    "PublicAccessBlockConfiguration": {
        "BlockPublicAcls": true,
        "IgnorePublicAcls": true,
        "BlockPublicPolicy": true,
        "RestrictPublicBuckets": true
    }
}

$ awsl s3api get-bucket-tagging --bucket vansh-24bcs10567-tf-s3-demo
{
    "TagSet": [
        {
            "Key": "Owner",
            "Value": "vansh-srivastava"
        },
        {
            "Key": "Project",
            "Value": "session-18-terraform-s3-demo"
        },
        {
            "Key": "ManagedBy",
            "Value": "Terraform"
        },
        {
            "Key": "Name",
            "Value": "vansh-24bcs10567-tf-s3-demo"
        },
        {
            "Key": "Environment",
            "Value": "dev"
        }
    ]
}
```

The bucket exists and every setting from the Terraform code is in place, including the three tags that came from `default_tags`.

To see versioning work, I uploaded the same key twice:

```bash
$ echo 'hello from version 1' | awsl s3 cp - s3://vansh-24bcs10567-tf-s3-demo/hello.txt
$ echo 'hello from version 2' | awsl s3 cp - s3://vansh-24bcs10567-tf-s3-demo/hello.txt

$ awsl s3api list-object-versions --bucket vansh-24bcs10567-tf-s3-demo --query 'Versions[].{Key:Key,IsLatest:IsLatest,Size:Size,VersionId:VersionId}' --output table
-----------------------------------------------------------------------
|                         ListObjectVersions                          |
+----------+------------+-------+-------------------------------------+
| IsLatest |    Key     | Size  |              VersionId              |
+----------+------------+-------+-------------------------------------+
|  True    |  hello.txt |  21   |  AaEXf0VKBQL0QcxNc5jqqRj7hj3oERb_   |
|  False   |  hello.txt |  21   |  AaEXf0VJ7wVFoP8QnlDmcMHekPc1gvPb   |
+----------+------------+-------+-------------------------------------+

$ awsl s3api head-object --bucket vansh-24bcs10567-tf-s3-demo --key hello.txt --query '{SSE:ServerSideEncryption,VersionId:VersionId}'
{
    "SSE": "AES256",
    "VersionId": "AaEXf0VKBQL0QcxNc5jqqRj7hj3oERb_"
}
```

Both versions are kept and only the newest one is `IsLatest`. The object was encrypted with AES256 automatically, even though the upload did not ask for encryption.

Uploading objects did not count as drift, because Terraform manages the bucket, not its contents:

```bash
$ terraform plan
aws_s3_bucket.demo: Refreshing state... [id=vansh-24bcs10567-tf-s3-demo]
aws_s3_bucket_public_access_block.demo: Refreshing state... [id=vansh-24bcs10567-tf-s3-demo]
aws_s3_bucket_versioning.demo: Refreshing state... [id=vansh-24bcs10567-tf-s3-demo]
aws_s3_bucket_server_side_encryption_configuration.demo: Refreshing state... [id=vansh-24bcs10567-tf-s3-demo]

No changes. Your infrastructure matches the configuration.

Terraform has compared your real infrastructure against your configuration
and found no differences, so no changes are needed.
```

### 9. terraform destroy

First the destroy plan, then the destroy:

```bash
$ terraform plan -destroy
aws_s3_bucket.demo: Refreshing state... [id=vansh-24bcs10567-tf-s3-demo]
aws_s3_bucket_versioning.demo: Refreshing state... [id=vansh-24bcs10567-tf-s3-demo]
aws_s3_bucket_public_access_block.demo: Refreshing state... [id=vansh-24bcs10567-tf-s3-demo]
aws_s3_bucket_server_side_encryption_configuration.demo: Refreshing state... [id=vansh-24bcs10567-tf-s3-demo]

Terraform used the selected providers to generate the following execution
plan. Resource actions are indicated with the following symbols:
  - destroy

Terraform will perform the following actions:

  # aws_s3_bucket.demo will be destroyed
  - resource "aws_s3_bucket" "demo" {
...
      - versioning {
          - enabled    = true -> null
          - mfa_delete = false -> null
        }
...
  # aws_s3_bucket_versioning.demo will be destroyed
  - resource "aws_s3_bucket_versioning" "demo" {
      - bucket                = "vansh-24bcs10567-tf-s3-demo" -> null
      - id                    = "vansh-24bcs10567-tf-s3-demo" -> null
      - region                = "ap-south-1" -> null
        # (1 unchanged attribute hidden)

      - versioning_configuration {
          - mfa_delete = "Disabled" -> null
          - status     = "Enabled" -> null
        }
    }

Plan: 0 to add, 0 to change, 4 to destroy.

Changes to Outputs:
  - bucket_arn           = "arn:aws:s3:::vansh-24bcs10567-tf-s3-demo" -> null
  - bucket_name          = "vansh-24bcs10567-tf-s3-demo" -> null
  - bucket_region        = "ap-south-1" -> null
  - encryption_algorithm = "AES256" -> null
  - target               = "LocalStack (http://localhost:4566)" -> null
  - versioning_status    = "Enabled" -> null
...

$ terraform destroy -auto-approve
aws_s3_bucket.demo: Refreshing state... [id=vansh-24bcs10567-tf-s3-demo]
aws_s3_bucket_public_access_block.demo: Refreshing state... [id=vansh-24bcs10567-tf-s3-demo]
aws_s3_bucket_versioning.demo: Refreshing state... [id=vansh-24bcs10567-tf-s3-demo]
aws_s3_bucket_server_side_encryption_configuration.demo: Refreshing state... [id=vansh-24bcs10567-tf-s3-demo]
...
Plan: 0 to add, 0 to change, 4 to destroy.

Changes to Outputs:
  - bucket_arn           = "arn:aws:s3:::vansh-24bcs10567-tf-s3-demo" -> null
  - bucket_name          = "vansh-24bcs10567-tf-s3-demo" -> null
  - bucket_region        = "ap-south-1" -> null
  - encryption_algorithm = "AES256" -> null
  - target               = "LocalStack (http://localhost:4566)" -> null
  - versioning_status    = "Enabled" -> null
aws_s3_bucket_public_access_block.demo: Destroying... [id=vansh-24bcs10567-tf-s3-demo]
aws_s3_bucket_server_side_encryption_configuration.demo: Destroying... [id=vansh-24bcs10567-tf-s3-demo]
aws_s3_bucket_versioning.demo: Destroying... [id=vansh-24bcs10567-tf-s3-demo]
aws_s3_bucket_server_side_encryption_configuration.demo: Destruction complete after 0s
aws_s3_bucket_public_access_block.demo: Destruction complete after 0s
aws_s3_bucket_versioning.demo: Destruction complete after 0s
aws_s3_bucket.demo: Destroying... [id=vansh-24bcs10567-tf-s3-demo]
aws_s3_bucket.demo: Destruction complete after 0s

Destroy complete! Resources: 4 destroyed.
```

I used `-auto-approve` because I had just reviewed `plan -destroy`. Without it, Terraform asks `Do you really want to destroy all resources?` and only continues on `yes`. The order is the reverse of apply: the three settings resources go first and the bucket last. The bucket still held two versions of `hello.txt`. `force_destroy = true` let Terraform delete those versions before deleting the bucket. Without it, S3 refuses to delete a bucket that still holds object versions and returns `BucketNotEmpty`. I hit exactly that error with the AWS CLI in my [S3 notes](../aws-services/03-s3/README.md#deleting-a-versioned-bucket).

### 10. After destroy

```bash
$ terraform state list

$ awsl s3 ls

$ awsl s3api head-bucket --bucket vansh-24bcs10567-tf-s3-demo
aws: [ERROR]: An error occurred (404) when calling the HeadBucket operation: Not Found
[exit code 254]
```

The state is empty, `s3 ls` lists nothing and `head-bucket` returns 404, so the bucket is gone.

## Cleanup

`terraform destroy` removed everything. I also deleted the local `.terraform/`, `terraform.tfstate*` and `tfplan` files. They are gitignored, so they would not have been committed anyway.
