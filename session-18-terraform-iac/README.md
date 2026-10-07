# Session 18: Terraform & Infrastructure as Code

**Name:** Vansh Srivastava
**Enrollment No.:** 24bcs10567
**Session:** 18

This session is about Infrastructure as Code with Terraform: describing cloud resources in `.tf` files and letting Terraform create, change and delete them through the provider's API. For Task 1 I built a Terraform project that creates a versioned, encrypted, tagged S3 bucket and took it through the whole `init -> fmt -> validate -> plan -> apply -> show -> output -> destroy` cycle, checking the bucket with the AWS CLI in between. For Task 2 I wrote notes on five core AWS services (IAM, EC2, S3, VPC, DynamoDB/RDS) and backed most of them with commands run against LocalStack, a local AWS emulator, instead of a real AWS account.

## Folder structure

```text
session-18-terraform-iac/
├── README.md                          # this file
├── .gitignore                         # ignores .terraform/, *.tfstate*, plan files
├── terraform-s3-demo/                 # Task 1
│   ├── provider.tf                    # version pins + aws provider (LocalStack/AWS switch)
│   ├── variables.tf                   # typed inputs, bucket-name validation
│   ├── terraform.tfvars               # my values (use_localstack = true)
│   ├── main.tf                        # bucket + versioning + encryption + public access block
│   ├── outputs.tf                     # name, ARN, region, versioning, encryption, target
│   ├── .terraform.lock.hcl            # provider checksums from terraform init (committed)
│   └── README.md                      # full walkthrough with every command's real output
└── aws-services/                      # Task 2
    ├── 01-iam/
    │   ├── README.md                  # users, groups, roles, policies, least privilege
    │   ├── least-privilege-policy.json
    │   └── ec2-trust-policy.json
    ├── 02-ec2/README.md               # AMI, instance types, key pairs, SGs, EBS, IPs, lifecycle
    ├── 03-s3/
    │   ├── README.md                  # buckets, objects, classes, versioning, lifecycle, encryption, policies
    │   ├── lifecycle.json
    │   └── bucket-policy.json
    ├── 04-vpc/README.md               # CIDR, subnets, route tables, IGW, NAT, SG vs NACL
    └── 05-dynamodb-rds/README.md      # DynamoDB keys and items, RDS engines, backups, Multi-AZ, replicas
```

## Environment

```text
macOS 26 (arm64), Docker via Colima
Terraform v1.16.4, provider hashicorp/aws v6.67.0 (constraint ~> 6.0)
LocalStack Community 4.14.0 (Docker container "localstack", 127.0.0.1:4566)
AWS CLI v2.37.10 (amazon/aws-cli image, run through Docker)
Region: ap-south-1 (Mumbai)
```

### LocalStack setup

I do not use a real AWS account for this course, so every AWS API call goes to [LocalStack](https://github.com/localstack/localstack), which emulates AWS services on `localhost:4566`.

**Which image.** The brief asked me to check whether the current `localstack/localstack:latest` still starts without an account. It does not. Since March 2026 LocalStack ships one unified image that needs a `LOCALSTACK_AUTH_TOKEN`:

```bash
$ docker run --rm --name s18-19-ls-latest-check localstack/localstack:latest
LocalStack version: 2026.9.1
LocalStack build date: 2026-10-07
LocalStack build git hash: f6d6999e

Localstack returning with exit code 55. Reason: 
===============================================
...

Reason: No credentials were found in the environment. Please set the LOCALSTACK_AUTH_TOKEN variable to a valid auth token. Alternatively, run `lstk login` and start LocalStack with the lstk CLI, which configures the credentials for you.

Due to this error, Localstack has quit. LocalStack pro features can only be used with a valid license.

- Please check that your credentials are set up correctly and that you have an active license.
  You can find your credentials in our webapp at https://app.localstack.cloud.

[exit code 55]
```

(I cut one line from the log above. It contained only emoji.)

Image metadata shows where the change happened: `4.14.0` (February 2026) is the last "LocalStack Docker image" (Community), and from `2026.3.0` on every tag is the "LocalStack Pro Docker image":

```bash
$ for t in 4.14.0 2026.3.0 latest; do echo "== $t"; docker buildx imagetools inspect localstack/localstack:$t --format '{{json .Image}}' | jq -r '."linux/arm64".config | .Labels.description, (.Env[] | select(startswith("LOCALSTACK_BUILD_VERSION")))'; done
== 4.14.0
LocalStack Docker image
LOCALSTACK_BUILD_VERSION=4.14.0
== 2026.3.0
LocalStack Pro Docker image
LOCALSTACK_BUILD_VERSION=2026.3.0
== latest
LocalStack Pro Docker image
LOCALSTACK_BUILD_VERSION=2026.9.1
```

So I pinned **`localstack/localstack:4.14.0`**, the newest tag that still runs without a token. I did not need the `motoserver/moto` fallback. I started the shared container like this:

```bash
docker run -d --name localstack --restart unless-stopped \
  -p 127.0.0.1:4566:4566 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  localstack/localstack:4.14.0
```

- `127.0.0.1:4566` publishes the API only on my machine, not on the network.
- The Docker socket is the standard LocalStack setup. It is only needed for services that start their own containers (such as Lambda), which the final project may use. S3, EC2, IAM, STS and DynamoDB do not need it.
- `--restart unless-stopped` keeps it available across Colima restarts. The final project uses the same container.

```bash
$ docker inspect localstack --format 'image={{.Config.Image}} restart={{.HostConfig.RestartPolicy.Name}} ports={{json .HostConfig.PortBindings}} mounts={{range .Mounts}}{{.Source}}->{{.Destination}} {{end}}'
image=localstack/localstack:4.14.0 restart=unless-stopped ports={"4566/tcp":[{"HostIp":"127.0.0.1","HostPort":"4566"}]} mounts=/var/run/docker.sock->/var/run/docker.sock /var/lib/docker/volumes/0ff2d5c354b4683603573ad904b54ec0d03e66950742e10a5cf8c0ee67ec1edb/_data->/var/lib/localstack 

$ docker logs localstack 2>&1 | head -12
WARNING
================================================================================
  You are starting the LocalStack Community Docker image.
  We move towards a unified LocalStack for AWS image in March 2026.
  Go to this page for more infos: https://localstack.cloud/2026-updates
================================================================================


LocalStack version: 4.14.0
LocalStack build date: 2026-02-26
LocalStack build git hash: 3d5a0c70e

$ docker ps --filter name=localstack --format '{{.Names}}  {{.Image}}  {{.Status}}  {{.Ports}}'
localstack  localstack/localstack:4.14.0  Up 27 minutes (healthy)  4510-4559/tcp, 5678/tcp, 127.0.0.1:4566->4566/tcp

$ curl -s localhost:4566/_localstack/health | jq -c '{edition, version}'
{"edition":"community","version":"4.14.0"}
```

The second mount in `docker inspect` is an anonymous volume that the image's own `VOLUME /var/lib/localstack` creates. I did not add it.

All the images came from Docker Hub without rate-limit errors. If Docker Hub answers `429 Too Many Requests`, the same tags are published on ECR Public: `public.ecr.aws/localstack/localstack:4.14.0` and `public.ecr.aws/aws-cli/aws-cli:2.37.10` (I checked that both tags exist).

**AWS CLI.** Instead of installing the AWS CLI, I run the official image and join it to the LocalStack container's network namespace, so `localhost:4566` inside it reaches LocalStack. The current folder is mounted at `/aws`, so `file://policy.json` arguments work:

```bash
awsl() {
  docker run --rm -i --network container:localstack -v "$PWD":/aws \
    -e AWS_ACCESS_KEY_ID=test -e AWS_SECRET_ACCESS_KEY=test -e AWS_DEFAULT_REGION=ap-south-1 \
    amazon/aws-cli:2.37.10 --endpoint-url http://localhost:4566 "$@"
}
```

Every `awsl ...` command in this session is this function. On a real account it would just be `aws ...`. `test`/`test` are LocalStack's dummy credentials, not secrets.

**What LocalStack Community cannot show** (noted where it matters): it does not enforce IAM policies, EC2 instances are API mocks that never boot, lifecycle rules are stored but never run, and RDS is not included.

## Task 1: Terraform S3 Demo

Project: [`terraform-s3-demo/`](terraform-s3-demo/). It has the files the brief asks for: `main.tf`, `variables.tf`, `outputs.tf`, `provider.tf`, `terraform.tfvars` and `README.md`. The project README has **the full output of every command**. Here is the summary.

**What it creates** (4 resources): `aws_s3_bucket` with tags and `force_destroy`, `aws_s3_bucket_versioning` (Enabled), `aws_s3_bucket_server_side_encryption_configuration` (SSE-S3 / AES256) and `aws_s3_bucket_public_access_block` (all four blocks on). Provider-level `default_tags` add `Project`, `Owner` and `ManagedBy` to everything.

**LocalStack vs real AWS.** The provider block reads `var.use_localstack`. When it is `true`, the provider gets the fake credentials, `skip_credentials_validation`, `skip_metadata_api_check`, `skip_requesting_account_id`, `s3_use_path_style` and an `endpoints` block (s3 and sts pointing to `http://localhost:4566`). When it is `false`, all of those become `null`/`false` and the endpoints block is not rendered, so it is a normal AWS provider using `aws configure` credentials. Switching to a real account means one line in `terraform.tfvars` (plus a globally unique bucket name).

**Commands I ran** (from `terraform-s3-demo/`):

```text
terraform init
terraform fmt
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
terraform show
terraform output
awsl s3 ls / s3api head-bucket / get-bucket-versioning / get-bucket-encryption / get-public-access-block / get-bucket-tagging
terraform plan -destroy
terraform destroy -auto-approve
awsl s3 ls / s3api head-bucket          # bucket gone
```

Key moments from the real output:

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
...
```

```bash
$ terraform plan -out=tfplan
...
Plan: 4 to add, 0 to change, 0 to destroy.
...
```

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

Bucket verified with the AWS CLI between apply and destroy:

```bash
$ awsl s3 ls
2026-10-07 17:52:50 vansh-24bcs10567-tf-s3-demo

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

$ awsl s3api list-object-versions --bucket vansh-24bcs10567-tf-s3-demo --query 'Versions[].{Key:Key,IsLatest:IsLatest,Size:Size,VersionId:VersionId}' --output table
-----------------------------------------------------------------------
|                         ListObjectVersions                          |
+----------+------------+-------+-------------------------------------+
| IsLatest |    Key     | Size  |              VersionId              |
+----------+------------+-------+-------------------------------------+
|  True    |  hello.txt |  21   |  AaEXf0VKBQL0QcxNc5jqqRj7hj3oERb_   |
|  False   |  hello.txt |  21   |  AaEXf0VJ7wVFoP8QnlDmcMHekPc1gvPb   |
+----------+------------+-------+-------------------------------------+
```

Destroy, and proof that the bucket is gone:

```bash
$ terraform destroy -auto-approve
...
aws_s3_bucket_public_access_block.demo: Destroying... [id=vansh-24bcs10567-tf-s3-demo]
aws_s3_bucket_server_side_encryption_configuration.demo: Destroying... [id=vansh-24bcs10567-tf-s3-demo]
aws_s3_bucket_versioning.demo: Destroying... [id=vansh-24bcs10567-tf-s3-demo]
aws_s3_bucket_server_side_encryption_configuration.demo: Destruction complete after 0s
aws_s3_bucket_public_access_block.demo: Destruction complete after 0s
aws_s3_bucket_versioning.demo: Destruction complete after 0s
aws_s3_bucket.demo: Destroying... [id=vansh-24bcs10567-tf-s3-demo]
aws_s3_bucket.demo: Destruction complete after 0s

Destroy complete! Resources: 4 destroyed.

$ awsl s3 ls

$ awsl s3api head-bucket --bucket vansh-24bcs10567-tf-s3-demo
aws: [ERROR]: An error occurred (404) when calling the HeadBucket operation: Not Found
[exit code 254]
```

**What I observed**

- `init` created `.terraform.lock.hcl` pinning hashicorp/aws 6.67.0. I commit it so everyone gets the same provider build. `.terraform/` and the state files are gitignored.
- `fmt` printed nothing because my files were already formatted. On a deliberately messy file it re-indented and aligned the `=` signs (shown in the project README).
- Apply order follows the references: bucket first, then versioning, encryption and the public access block in parallel. Destroy runs in exactly the reverse order.
- A second `terraform plan` after uploading objects said "No changes": Terraform tracks the bucket and its settings, not the objects inside it.
- `force_destroy = true` was needed, because the bucket still held two versions of a test object when I destroyed it.

## Task 2: AWS Services Research

Each folder has a README in my own words covering every topic from the brief, with small JSON/HCL/CLI examples. Where it was cheap, I ran the example against LocalStack and pasted the real output. Every LocalStack resource was deleted again afterwards.

| Service | Notes | Run on LocalStack |
|---|---|---|
| IAM | [01-iam/README.md](aws-services/01-iam/README.md): users, groups, roles, policies, evaluation logic, least privilege, best practices, use cases | user + group + least-privilege customer-managed policy, EC2 role with trust policy. Also shows that LocalStack's policy simulator gives wrong results |
| EC2 | [02-ec2/README.md](aws-services/02-ec2/README.md): AMI, instance types, key pairs, security groups, EBS, public/private/Elastic IP, lifecycle, use cases | AMI lookup, key pair, security group rules, `t3.micro` with encrypted gp3 root volume, stop/start/terminate |
| S3 | [03-s3/README.md](aws-services/03-s3/README.md): buckets, objects, storage classes, versioning, lifecycle, encryption, bucket policies, use cases | versioned bucket, Standard-IA upload, lifecycle rule, deny-HTTP bucket policy, deleting a versioned bucket |
| VPC | [04-vpc/README.md](aws-services/04-vpc/README.md): CIDR, subnets, route tables, IGW, NAT gateway, security groups vs NACLs, public vs private subnets | VPC, public and private subnets, IGW, route table and association, default NACL rules |
| DynamoDB & RDS | [05-dynamodb-rds/README.md](aws-services/05-dynamodb-rds/README.md): tables, items, attributes, partition/sort keys, use cases; RDS engines, instances, security, backups, Multi-AZ, read replicas | DynamoDB table with composite key, put/query/get. RDS is **not** in LocalStack Community (error shown), so the RDS Terraform example is documented only |

## What I learned

- Terraform is declarative: I describe the end state, and the dependency graph built from references decides the order of API calls for both apply and destroy.
- The lock file pins provider versions and checksums and belongs in Git. State and `.terraform/` do not.
- One provider block can target both an emulator and real AWS if the emulator-specific arguments are driven by a variable and collapse to `null` otherwise.
- S3 best practice is several resources (versioning, encryption, public access block), not one, and versioning changes how deletes work (delete markers, `BucketNotEmpty`).
- An emulator is great for practising the workflow and API shapes, but it does not enforce IAM, boot instances or run lifecycle rules, so some behaviour can only be verified on real AWS.
- The newest "latest" image is not always usable: pinning an exact tag (`4.14.0`) and recording why makes the setup reproducible.
