# AWS IAM (Identity and Access Management)

**Name:** Vansh Srivastava | **Enrollment No.:** 24bcs10567 | **Session:** 18, Task 2

## What is IAM

IAM is the AWS service that decides **who** can call **which** AWS API on **which** resource. Every request to AWS (console click, CLI command, SDK call, Terraform apply) is signed with credentials. IAM checks those credentials against policies and allows or denies the request. IAM is global (not tied to a region) and costs nothing.

It has two parts:

- **Authentication**: who are you? (a user, a role session, the root user)
- **Authorization**: are you allowed to do this? (policies)

The **root user** is the email address that created the account. It can do everything, including closing the account. Turn on MFA for it, give it no access keys, and use it only for the few tasks that need it (billing settings, account closure).

## Users

An IAM user is one identity with **long-term credentials**: a console password and/or up to two access keys (`AKIA...` + secret). A user belongs to exactly one account.

Today AWS recommends IAM users only for the cases that really need fixed keys, such as an old tool that cannot use roles. People should sign in through IAM Identity Center (SSO) or a federated identity provider, and get temporary credentials.

## Groups

A group is a collection of users that share the same policies, for example `developers` or `report-readers`. Attaching a policy to a group is easier than attaching it to 20 users one by one. Groups only hold users: a group cannot contain another group, and a group cannot sign in or be named as a principal in a policy.

## Roles

A role is an identity **without** long-term credentials. Something trusted *assumes* the role and receives **temporary credentials** (access key, secret, session token) from STS that expire after 15 minutes to 12 hours.

A role has two policies:

- a **trust policy**: who may assume it (an AWS service like `ec2.amazonaws.com`, another account, a federated user, GitHub Actions through OIDC)
- **permission policies**: what the role may do once assumed

Typical roles: an EC2 instance profile (the app on the instance gets credentials from instance metadata, no keys on disk), a Lambda execution role, a cross-account read-only role, a CI/CD deploy role assumed through OIDC.

## Policies

A policy is a JSON document with one or more statements:

| Element | Meaning |
|---|---|
| `Effect` | `Allow` or `Deny` |
| `Action` | API calls, e.g. `s3:GetObject`, `ec2:*` |
| `Resource` | ARNs the statement applies to |
| `Condition` | optional extra checks (source IP, MFA present, tag values, `aws:SecureTransport`) |
| `Principal` | only in resource-based policies and trust policies: who the policy is about |

Kinds of policy:

- **Identity-based**: attached to a user, group or role. They come as **AWS managed** (ready-made, e.g. `ReadOnlyAccess`), **customer managed** (written by you, reusable, versioned) or **inline** (embedded in one identity, deleted with it).
- **Resource-based**: attached to the resource itself, e.g. an S3 bucket policy or a KMS key policy. These name a `Principal`.
- **Guardrails**: permission boundaries (the maximum a user or role can ever get) and, in AWS Organizations, SCPs (the maximum for a whole account).

## Permissions (how a request is evaluated)

1. Everything starts as **implicitly denied**.
2. If any applicable policy has an **explicit `Deny`** that matches, the request is denied. A deny always wins.
3. Otherwise, if some policy **`Allow`s** it (and no boundary or SCP blocks it), it is allowed.
4. If nothing allows it, it stays denied.

So permissions add up across the user's own policies and its groups' policies, but a single matching `Deny` overrides all of them.

## Least privilege

Least privilege means giving an identity only the actions and resources it needs for its job, and nothing more. If the credentials leak or the code has a bug, the damage stays small.

Example: a reporting job only needs to list one bucket and read its objects. Instead of `AmazonS3FullAccess` (every action on every bucket), it gets this policy (also in this folder as [`least-privilege-policy.json`](least-privilege-policy.json)):

```bash
$ cat least-privilege-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListOnlyTheReportsBucket",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::s18-reports-bucket"
    },
    {
      "Sid": "ReadObjectsInReportsBucket",
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::s18-reports-bucket/*"
    }
  ]
}
```

`s3:ListBucket` applies to the bucket ARN and `s3:GetObject` to the objects inside it (`/*`). The job cannot write, delete, touch other buckets or use any other service.

How I would get there in practice: start from a narrow policy, look at the denials in CloudTrail or use IAM Access Analyzer to generate a policy from real activity, and use "last accessed" data to remove permissions nobody uses.

## Best practices

- Lock the root user away: MFA on, no access keys.
- People sign in through IAM Identity Center or federation. No shared users, and no long-term keys on laptops where avoidable.
- Workloads use roles (instance profiles, task roles, Lambda roles, OIDC for CI) instead of access keys.
- Require MFA for humans, especially for sensitive actions.
- Grant permissions to groups or roles, not to individual users.
- Write least-privilege, customer-managed policies. Use conditions and resource ARNs instead of `*`.
- Rotate or delete any access keys that must exist. Review unused users, roles and permissions regularly.
- Use permission boundaries and SCPs as guardrails, and IAM Access Analyzer to find resources shared outside the account.
- Never commit keys to Git (this repo only contains the obviously fake `test`/`test` LocalStack values).

## Common use cases

- Team access: `developers`, `ops`, `read-only` groups or Identity Center permission sets.
- An EC2 instance reading from S3 through an instance profile. My Session 19 project does exactly this: [`../../../session-19-terraform-project/iam.tf`](../../../session-19-terraform-project/iam.tf).
- A Lambda function with an execution role that can write to one DynamoDB table.
- GitHub Actions deploying to AWS by assuming a role through OIDC, with no stored secrets.
- Cross-account access: a central security account assumes a read-only role in every other account.
- Sharing one bucket with a partner account through a bucket policy.

## Hands-on: users, groups, a least-privilege policy and a role on LocalStack

`awsl` is my wrapper that runs the official AWS CLI image against LocalStack (defined in the [session README](../../README.md#localstack-setup)). LocalStack's account ID is always `000000000000`.

Create a user and a group and put the user in the group:

```bash
$ awsl iam create-user --user-name s18-alice
{
    "User": {
        "Path": "/",
        "UserName": "s18-alice",
        "UserId": "88f1mbc67kevq1jgfnrp",
        "Arn": "arn:aws:iam::000000000000:user/s18-alice",
        "CreateDate": "2026-10-07T17:54:32.040517+00:00"
    }
}

$ awsl iam create-group --group-name s18-report-readers
{
    "Group": {
        "Path": "/",
        "GroupName": "s18-report-readers",
        "GroupId": "akho09b69fe4ehrqbp81",
        "Arn": "arn:aws:iam::000000000000:group/s18-report-readers",
        "CreateDate": "2026-10-07T17:54:32.575828+00:00"
    }
}

$ awsl iam add-user-to-group --user-name s18-alice --group-name s18-report-readers
```

Create the customer-managed policy from the JSON file and attach it to the group (not to the user):

```bash
$ awsl iam create-policy --policy-name s18-read-reports-bucket --policy-document file://least-privilege-policy.json --query 'Policy.{Name:PolicyName,Arn:Arn,Version:DefaultVersionId}'
{
    "Name": "s18-read-reports-bucket",
    "Arn": "arn:aws:iam::000000000000:policy/s18-read-reports-bucket",
    "Version": "v1"
}

$ awsl iam attach-group-policy --group-name s18-report-readers --policy-arn arn:aws:iam::000000000000:policy/s18-read-reports-bucket

$ awsl iam get-group --group-name s18-report-readers --query '{Group:Group.GroupName,Users:Users[].UserName}'
{
    "Group": "s18-report-readers",
    "Users": [
        "s18-alice"
    ]
}

$ awsl iam list-attached-group-policies --group-name s18-report-readers
{
    "AttachedPolicies": [
        {
            "PolicyName": "s18-read-reports-bucket",
            "PolicyArn": "arn:aws:iam::000000000000:policy/s18-read-reports-bucket"
        }
    ]
}
```

`s18-alice` now gets the read-only bucket permissions through her group.

A role for an application server. The trust policy ([`ec2-trust-policy.json`](ec2-trust-policy.json)) lets only the EC2 service assume it. The same permission policy is reused:

```bash
$ cat ec2-trust-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}

$ awsl iam create-role --role-name s18-app-server-role --assume-role-policy-document file://ec2-trust-policy.json --query 'Role.{Name:RoleName,Arn:Arn}'
{
    "Name": "s18-app-server-role",
    "Arn": "arn:aws:iam::000000000000:role/s18-app-server-role"
}

$ awsl iam attach-role-policy --role-name s18-app-server-role --policy-arn arn:aws:iam::000000000000:policy/s18-read-reports-bucket

$ awsl iam list-attached-role-policies --role-name s18-app-server-role
{
    "AttachedPolicies": [
        {
            "PolicyName": "s18-read-reports-bucket",
            "PolicyArn": "arn:aws:iam::000000000000:policy/s18-read-reports-bucket"
        }
    ]
}
```

### A limit of the emulator

I also asked IAM to simulate what alice may do:

```bash
$ awsl iam simulate-principal-policy --policy-source-arn arn:aws:iam::000000000000:user/s18-alice --action-names s3:GetObject s3:PutObject s3:DeleteBucket --resource-arns 'arn:aws:s3:::s18-reports-bucket/2026/q3.csv' --query 'EvaluationResults[].{Action:EvalActionName,Decision:EvalDecision}' --output table
-------------------------------------
|      SimulatePrincipalPolicy      |
+------------------+----------------+
|      Action      |   Decision     |
+------------------+----------------+
|  s3:GetObject    |  explicitDeny  |
|  s3:PutObject    |  explicitDeny  |
|  s3:DeleteBucket |  explicitDeny  |
+------------------+----------------+
```

This result is wrong. On real AWS the same simulation should show `allowed` for `s3:GetObject` (her group policy allows it) and `implicitDeny` for the other two, since nothing allows them and nothing denies them explicitly. LocalStack Community stores IAM objects but does not evaluate or enforce policies. That is a Pro feature. So LocalStack is fine for checking that IAM resources are created with the right shape, but permission behaviour has to be tested on real AWS (or with the IAM policy simulator in the console).

### Cleanup

IAM refuses to delete things that are still attached, so the order matters: detach, remove, then delete.

```bash
$ awsl iam detach-role-policy --role-name s18-app-server-role --policy-arn arn:aws:iam::000000000000:policy/s18-read-reports-bucket
$ awsl iam delete-role --role-name s18-app-server-role
$ awsl iam detach-group-policy --group-name s18-report-readers --policy-arn arn:aws:iam::000000000000:policy/s18-read-reports-bucket
$ awsl iam remove-user-from-group --user-name s18-alice --group-name s18-report-readers
$ awsl iam delete-group --group-name s18-report-readers
$ awsl iam delete-user --user-name s18-alice
$ awsl iam delete-policy --policy-arn arn:aws:iam::000000000000:policy/s18-read-reports-bucket

$ awsl iam list-users --query 'Users[?starts_with(UserName, `s18-`)].UserName'
[]
```
