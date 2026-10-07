# Amazon DynamoDB and Amazon RDS

**Name:** Vansh Srivastava | **Enrollment No.:** 24bcs10567 | **Session:** 18, Task 2

AWS has two very different managed database families: **DynamoDB** (NoSQL, serverless, key-based access) and **RDS** (managed relational databases with SQL). The short version: use DynamoDB when I know my access patterns and need predictable speed at any scale, and RDS when I need joins, ad-hoc SQL queries and transactions across many tables.

---

# DynamoDB

## What is DynamoDB (NoSQL)

DynamoDB is a fully managed, serverless **key-value and document** database. There are no servers, versions or patches to manage: I create a table and read and write items over HTTPS. Reads and writes by key take single-digit milliseconds at any size, because data is spread across partitions automatically. Tables are replicated across three AZs in the region.

"NoSQL" here means:

- no fixed schema beyond the key attributes
- no joins: data that is read together is stored together (often in one table)
- queries go through keys and indexes, not arbitrary `WHERE` clauses

## Tables, items and attributes

| DynamoDB | Rough SQL equivalent |
|---|---|
| **Table** | table |
| **Item** | row (max **400 KB**) |
| **Attribute** | column, but each item can have different attributes |

Attribute types include scalars (`S` string, `N` number, `B` binary, `BOOL`, `NULL`), documents (`M` map, `L` list) and sets (`SS`, `NS`, `BS`). In the demo below, one order has a `coupon` attribute and the others do not. No `ALTER TABLE` is needed.

## Partition key and sort key

Every table has a **primary key**, chosen at creation and never changed:

- **Partition key** (hash key): DynamoDB hashes its value to choose the physical partition. A `GetItem` with the full key goes straight to the right place. Pick a key with many distinct, evenly used values (`customer_id`, `device_id`), otherwise one "hot" partition becomes the bottleneck.
- **Sort key** (range key), optional: items with the same partition key are stored together, ordered by the sort key. That allows range queries within one partition: `=`, `<`, `between`, `begins_with`.

A table has either a **simple** key (partition key only, which must be unique) or a **composite** key (partition + sort, where the pair must be unique). In my demo the key is `customer_id` + `order_date`, so "all orders of customer c-101 in October 2026" is a single efficient `Query`.

For other access patterns you add a **global secondary index** (GSI: a different partition/sort key, kept in sync automatically) or a **local secondary index** (LSI: same partition key, different sort key, defined at table creation).

Other features worth knowing: **on-demand** (pay per request) or **provisioned** (set read/write capacity, with optional auto scaling) capacity modes; eventually consistent reads by default with optional strongly consistent reads; **TTL** to expire items automatically; **Streams** to react to changes (e.g. with Lambda); point-in-time recovery; global tables for multi-region.

## Use cases

- User sessions, shopping carts, user profiles and preferences
- Game state and leaderboards, IoT device data, time series per device
- Serverless backends (API Gateway + Lambda + DynamoDB)
- Metadata stores and idempotency keys
- **Terraform state locking**: the S3 backend writes a `LockID` item into a DynamoDB table. I demonstrate this in Session 19.

## Hands-on: a table with a composite key on LocalStack

`awsl` is my wrapper that runs the AWS CLI against LocalStack (see the [session README](../../README.md#localstack-setup)).

Create an on-demand table with partition key `customer_id` and sort key `order_date`:

```bash
$ awsl dynamodb create-table --table-name s18-orders --attribute-definitions AttributeName=customer_id,AttributeType=S AttributeName=order_date,AttributeType=S --key-schema AttributeName=customer_id,KeyType=HASH AttributeName=order_date,KeyType=RANGE --billing-mode PAY_PER_REQUEST --query 'TableDescription.{Table:TableName,Status:TableStatus,Keys:KeySchema,Billing:BillingModeSummary.BillingMode}'
{
    "Table": "s18-orders",
    "Status": "ACTIVE",
    "Keys": [
        {
            "AttributeName": "customer_id",
            "KeyType": "HASH"
        },
        {
            "AttributeName": "order_date",
            "KeyType": "RANGE"
        }
    ],
    "Billing": "PAY_PER_REQUEST"
}
```

Only the key attributes are declared. Everything else is free-form per item:

```bash
$ awsl dynamodb put-item --table-name s18-orders --item '{"customer_id":{"S":"c-101"},"order_date":{"S":"2026-09-14#o-9001"},"total":{"N":"499"},"status":{"S":"DELIVERED"}}'
$ awsl dynamodb put-item --table-name s18-orders --item '{"customer_id":{"S":"c-101"},"order_date":{"S":"2026-10-02#o-9017"},"total":{"N":"1299"},"status":{"S":"SHIPPED"},"coupon":{"S":"DIWALI10"}}'
$ awsl dynamodb put-item --table-name s18-orders --item '{"customer_id":{"S":"c-202"},"order_date":{"S":"2026-10-05#o-9031"},"total":{"N":"89"},"status":{"S":"PLACED"}}'
```

`Query` uses the partition key plus a sort-key condition. Here: customer `c-101`, orders in October 2026 only:

```bash
$ awsl dynamodb query --table-name s18-orders --key-condition-expression 'customer_id = :c AND begins_with(order_date, :m)' --expression-attribute-values '{":c":{"S":"c-101"},":m":{"S":"2026-10"}}' --query 'Items[]'
[
    {
        "order_date": {
            "S": "2026-10-02#o-9017"
        },
        "total": {
            "N": "1299"
        },
        "customer_id": {
            "S": "c-101"
        },
        "coupon": {
            "S": "DIWALI10"
        },
        "status": {
            "S": "SHIPPED"
        }
    }
]
```

Only the October order came back. The September order of the same customer was excluded by `begins_with(order_date, "2026-10")`, and customer `c-202` was never read at all. `GetItem` with the full key fetches one item. `status` and `total` are DynamoDB reserved words, so they need `#placeholders`:

```bash
$ awsl dynamodb get-item --table-name s18-orders --key '{"customer_id":{"S":"c-202"},"order_date":{"S":"2026-10-05#o-9031"}}' --projection-expression '#s, #t' --expression-attribute-names '{"#s":"status","#t":"total"}'
{
    "Item": {
        "total": {
            "N": "89"
        },
        "status": {
            "S": "PLACED"
        }
    }
}

$ awsl dynamodb describe-table --table-name s18-orders --query 'Table.{Items:ItemCount,Status:TableStatus,Arn:TableArn}'
{
    "Items": 3,
    "Status": "ACTIVE",
    "Arn": "arn:aws:dynamodb:ap-south-1:000000000000:table/s18-orders"
}

$ awsl dynamodb delete-table --table-name s18-orders --query 'TableDescription.TableStatus'
"ACTIVE"
```

(Real DynamoDB answers a delete with `"DELETING"`. LocalStack deletes the table at once and still reports `"ACTIVE"`.)

---

# RDS (Relational Database Service)

## What is RDS (relational DB)

RDS runs a relational database engine for me. I pick the engine, version, instance size and storage. AWS handles provisioning, OS and engine patching (in a maintenance window I choose), automated backups, monitoring, failover and storage scaling. I still design the schema, write the SQL, tune queries and choose the security settings. Unlike EC2 with a database installed on it, there is no SSH access to the host.

Relational means tables with fixed columns, primary and foreign keys, **joins**, **SQL** and **ACID transactions**: the right fit when data is highly related and queries are not all known in advance.

## Engines

- **MySQL**, **PostgreSQL**, **MariaDB** (open source)
- **Oracle** and **Microsoft SQL Server** (commercial; license included or bring your own license)
- **IBM Db2**
- **Amazon Aurora** (MySQL- or PostgreSQL-compatible): AWS's own cloud-native engine. Storage is shared and replicated six ways across three AZs, it grows automatically, and it supports up to 15 low-lag replicas plus a serverless option.

## DB instances

A DB instance is one database server: an **instance class** (e.g. `db.t4g.micro`, `db.m7g.large`, `db.r7g.xlarge`, using the same family idea as EC2), **storage** (gp3 or io2 EBS, with optional storage auto scaling) and an **endpoint** DNS name that clients connect to. A DB instance is placed in a **DB subnet group**: a set of subnets in at least two AZs, normally private ones.

## Security

- **Network**: private subnets with no public access, and a security group that allows the DB port (3306 or 5432) only from the application's security group.
- **Encryption at rest** with KMS (choose it at creation; it covers storage, backups, snapshots and replicas). **In transit**: require TLS.
- **Authentication**: a master user whose password is best stored and rotated by **Secrets Manager** (`manage_master_user_password` in Terraform), plus optional **IAM database authentication** for MySQL and PostgreSQL (short-lived tokens instead of passwords).
- **Access to the RDS API** itself (creating, deleting, snapshotting) is controlled by IAM policies.
- Deletion protection, audit logs to CloudWatch Logs, and Performance Insights for monitoring.

## Backups

- **Automated backups**: a daily snapshot plus transaction logs, kept for **1-35 days**. This enables **point-in-time restore** to any second inside the retention window (typically up to about 5 minutes before now).
- **Manual snapshots**: taken on demand and kept until I delete them. Good before risky changes. They can be copied to other regions or shared with other accounts.
- A restore always creates a **new** DB instance with a new endpoint. It does not overwrite the old one.

## Multi-AZ

Multi-AZ is about **availability**, not performance:

- **Multi-AZ instance deployment**: RDS keeps a **synchronous standby** in another AZ. If the primary or its AZ fails (or during patching), RDS fails over automatically, usually within one to two minutes, and the same endpoint DNS name points to the new primary. The standby cannot serve reads.
- **Multi-AZ DB cluster** (MySQL and PostgreSQL): one writer and **two readable** standbys in three AZs, with faster failover.

## Read replicas

Read replicas are about **read scaling**:

- **Asynchronous** copies of the primary, each with its own endpoint. The application sends reads (reports, dashboards) there and writes to the primary.
- They can be in another AZ or **another region**, which also helps with disaster recovery.
- A replica can be **promoted** to a standalone writable database.
- Because replication is asynchronous, a replica can be slightly behind (replica lag), so read-after-write code should read from the primary.

| | Multi-AZ (instance) | Read replica |
|---|---|---|
| Purpose | high availability | read scaling, DR |
| Replication | synchronous | asynchronous |
| Readable | no | yes |
| Failover | automatic | manual promotion |

## Use cases

- Web and mobile app backends with users, orders, payments
- ERP, CRM and e-commerce systems where consistency and transactions matter
- Reporting with complex joins and aggregations (offloaded to read replicas)
- Lifting an existing MySQL, PostgreSQL, SQL Server or Oracle database into AWS without running it yourself

## RDS on LocalStack: not available

```bash
$ awsl rds describe-db-instances
aws: [ERROR]: An error occurred (InternalFailure) when calling the DescribeDBInstances operation: The API for service rds is either not included in your current license plan or has not yet been emulated by LocalStack.
[exit code 254]
```

RDS is not part of LocalStack Community, so I could not create a DB instance. For reference, this is how I would declare a small, private, encrypted PostgreSQL instance with Multi-AZ and backups in Terraform. **I did not run this**, so there is no output for it:

```hcl
resource "aws_db_subnet_group" "app" {
  name       = "app-db"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id] # two AZs
}

resource "aws_db_instance" "app" {
  identifier     = "app-postgres"
  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t4g.micro"

  allocated_storage     = 20
  max_allocated_storage = 100 # storage auto scaling
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name                     = "app"
  username                    = "app_admin"
  manage_master_user_password = true # password generated and rotated in Secrets Manager

  db_subnet_group_name   = aws_db_subnet_group.app.name
  vpc_security_group_ids = [aws_security_group.db.id] # 5432 only from the app SG
  publicly_accessible    = false

  multi_az                  = true
  backup_retention_period   = 7
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "app-postgres-final"
}

resource "aws_db_instance" "app_replica" {
  identifier          = "app-postgres-replica"
  replicate_source_db = aws_db_instance.app.identifier
  instance_class      = "db.t4g.micro"
}
```

---

## DynamoDB vs RDS at a glance

| | DynamoDB | RDS |
|---|---|---|
| Model | key-value / document (NoSQL) | relational tables (SQL) |
| Schema | only the key is fixed | fixed columns, migrations |
| Queries | by key and indexes, no joins | any SQL, joins, aggregations |
| Scaling | automatic, practically unlimited | bigger instance class, read replicas |
| Servers | none (serverless) | DB instances you size |
| Pricing | per request or provisioned capacity, plus storage | per instance-hour, plus storage and I/O |
| Best for | known access patterns at high scale | relational data, flexible queries, transactions |
