# Amazon EC2 (Elastic Compute Cloud)

**Name:** Vansh Srivastava | **Enrollment No.:** 24bcs10567 | **Session:** 18, Task 2

## What is EC2

EC2 rents out virtual machines, called **instances**, in AWS data centers. You choose the operating system image, the CPU/memory size, the network, the disks and the firewall rules, and pay per second while the instance runs. It is the IaaS part of AWS: AWS runs the hardware and the hypervisor, and I am responsible for the OS, patches, software and data on it.

An instance always lives in one **subnet** of a VPC, which means one Availability Zone.

## AMI (Amazon Machine Image)

An AMI is the template an instance boots from. It contains:

- a snapshot of the root volume (OS plus anything pre-installed)
- the architecture (`x86_64` or `arm64`) and boot settings
- launch permissions (who may use it)

AMIs are regional and have IDs like `ami-0ff5003538b60d5ec`. They come from AWS (Amazon Linux 2023, Windows), from vendors (Ubuntu, RHEL), from the AWS Marketplace, or you bake your own (for example with Packer) so new instances start with your app already installed. AMI IDs differ per region and change with every release, so in Terraform I look them up with a `data "aws_ami"` filter instead of hard-coding an ID.

## Instance types

The type sets vCPU, memory, network bandwidth and sometimes local disk or GPU. The name `t3.micro` reads as:

- `t`: the **family** (what it is optimised for)
- `3`: the **generation** (newer is usually cheaper per unit of performance)
- `micro`: the **size** (nano, micro, small, medium, large, xlarge, 2xlarge, ...)

A suffix adds detail: `g` = AWS Graviton (ARM), `a` = AMD, `i` = Intel, `d` = local NVMe disk, `n` = more network bandwidth (e.g. `m7g.large`, `c6in.xlarge`).

| Family | Optimised for | Typical use |
|---|---|---|
| `t` (t3, t4g) | burstable: low baseline CPU, earns CPU credits to burst | dev boxes, small web apps |
| `m` (m7g, m7i) | general purpose, balanced | app servers, backends |
| `c` (c7g, c7i) | compute | batch jobs, encoding, high-traffic APIs |
| `r`, `x` | memory | in-memory caches, large databases |
| `i`, `d` | local storage I/O | NoSQL databases, data warehouses |
| `g`, `p`, `inf`, `trn` | GPU / ML accelerators | ML training and inference, graphics |

## Key pairs

A key pair is used to log in over SSH (Linux) or to decrypt the Administrator password (Windows). AWS keeps the **public** key and puts it into `~/.ssh/authorized_keys` on first boot. The **private** key is shown to you once at creation and never stored by AWS. Lose it and you cannot use that key again. Key types are RSA and ED25519.

Instances do not need a key pair at all. With **SSM Session Manager** you get a shell through the AWS API, with no open port 22 and no keys to manage. That is what I would use in a real project.

## Security groups

A security group is a virtual firewall attached to an instance's network interface.

- Rules only **allow**. There is no deny rule; anything not allowed is dropped.
- It is **stateful**: if inbound traffic is allowed, the reply goes out automatically, and the other way round.
- A source can be a CIDR (`203.0.113.10/32`) or **another security group** ("allow port 5432 from the app servers' SG"). That is cleaner than IP lists.
- New groups allow all outbound traffic and no inbound traffic.
- One instance can have several groups, and their rules add up.

Good practice: open 80/443 to the world only on a load balancer or web server, and never open 22 or 3389 to `0.0.0.0/0`.

## EBS (Elastic Block Store)

EBS volumes are network-attached virtual disks.

- A volume lives in **one AZ** and attaches to instances in that AZ (normally one instance at a time).
- It survives stop/start. The root volume is deleted on termination by default (`DeleteOnTermination`); extra data volumes are kept by default.
- **Snapshots** are point-in-time backups stored in S3 (incremental). You can copy them to other regions and create new volumes or AMIs from them.
- Encryption with KMS covers data at rest, snapshots and the traffic between instance and volume.
- Types: `gp3` (general purpose SSD, 3,000 IOPS baseline, the default choice), `io2` (provisioned IOPS for databases), `st1` (throughput HDD for big sequential reads), `sc1` (cold HDD, cheapest).

Not to be confused with **instance store**: disks physically attached to the host. They are very fast, but the data is lost when the instance stops or fails.

## Public vs private IP

| | Private IPv4 | Public IPv4 | Elastic IP |
|---|---|---|---|
| From | the subnet's CIDR | AWS's public pool | you allocate it to your account |
| Reachable from | inside the VPC (and peered/VPN networks) | the internet, if routing and SG allow | the internet |
| Lifetime | stays for the life of the instance | **released on stop**, a new one on start | stays until you release it |

The OS only ever sees its private IP. The internet gateway translates between the public IP and the private one. AWS charges for every public IPv4 address, so private subnets plus a load balancer or NAT are common. An instance only gets a public IP if the subnet has `map_public_ip_on_launch` set or you ask for one at launch, and it is only reachable if the subnet's route table also has a route to an internet gateway.

## Instance lifecycle

```text
 launch
   |
pending ---> running ---> stopping ---> stopped ---> (start) ---> pending
   |            |   \                      |
   |            |    `--- reboot (same host, stays running)
   |            v                          v
   `-----> shutting-down -------------> terminated  (gone, not billed)
```

- **pending**: being placed on a host and booting. Not billed yet.
- **running**: billed per second (Linux, 60 s minimum). `user_data` runs on the first boot.
- **stopping / stopped**: compute is not billed, but EBS volumes (and any Elastic IP) still are. The instance may come back on different hardware and gets a new public IP.
- **hibernate**: like stop, but RAM is saved to the encrypted root volume so apps resume where they were.
- **shutting-down / terminated**: the instance is deleted. A terminated instance stays visible in the API for about an hour, then disappears.

## Use cases

- Web and application servers, alone or in an Auto Scaling group behind a load balancer
- Self-managed databases or software that needs full OS control
- Batch and HPC jobs, often on cheap Spot instances
- CI build agents, bastion hosts, VPN servers
- GPU instances for ML training and inference
- Lift-and-shift of on-premises VMs

Pricing models: On-Demand (no commitment), Savings Plans or Reserved Instances (1-3 year commitment, big discount), Spot (spare capacity, up to about 90% cheaper, can be interrupted with 2 minutes' notice).

## Hands-on: key pair, security group and an instance's lifecycle on LocalStack

`awsl` is my wrapper that runs the AWS CLI against LocalStack (see the [session README](../../README.md#localstack-setup)). LocalStack Community's EC2 is a mock: the API behaves like EC2, but no VM actually boots.

Find an Amazon Linux 2023 AMI and the default VPC:

```bash
$ awsl ec2 describe-images --owners amazon --filters 'Name=name,Values=al2023-ami-2023.*-kernel-6.1-x86_64' --query 'Images[].{ImageId:ImageId,Name:Name,Arch:Architecture,Root:RootDeviceType}' --output table
----------------------------------------------------------------
|                        DescribeImages                        |
+---------+----------------------------------------------------+
|  Arch   |  x86_64                                            |
|  ImageId|  ami-0ff5003538b60d5ec                             |
|  Name   |  al2023-ami-2023.10.20260120.4-kernel-6.1-x86_64   |
|  Root   |  ebs                                               |
+---------+----------------------------------------------------+

$ awsl ec2 describe-vpcs --filters Name=is-default,Values=true --query 'Vpcs[].{VpcId:VpcId,Cidr:CidrBlock,Default:IsDefault}' --output table
-------------------------------------------------------
|                    DescribeVpcs                     |
+----------------+----------+-------------------------+
|      Cidr      | Default  |          VpcId          |
+----------------+----------+-------------------------+
|  172.31.0.0/16 |  True    |  vpc-ef8dc367812c9f0ab  |
+----------------+----------+-------------------------+
```

Key pair (I only print the name, ID and fingerprint, not the private key) and a security group with HTTP open and SSH limited to one documentation-range IP:

```bash
$ awsl ec2 create-key-pair --key-name s18-demo-key --key-type ed25519 --query '{KeyName:KeyName,KeyPairId:KeyPairId,Fingerprint:KeyFingerprint}'
{
    "KeyName": "s18-demo-key",
    "KeyPairId": "key-888527e96e78e2fd7",
    "Fingerprint": "78:51:63:3b:4f:76:5b:e8:d7:ae:58:b4:95:b3:35:84:d0:ac:4d:11:d7:ad:ad:40:1e:b5:aa:88:17:24:6f:c8"
}

$ awsl ec2 create-security-group --group-name s18-web-sg --description 'web server: http from anywhere, ssh from one admin ip' --vpc-id vpc-ef8dc367812c9f0ab
{
    "GroupId": "sg-2d3363a0eb1a9a24b",
    "SecurityGroupArn": "arn:aws:ec2:ap-south-1:000000000000:security-group/sg-2d3363a0eb1a9a24b"
}

$ awsl ec2 authorize-security-group-ingress --group-id sg-2d3363a0eb1a9a24b --protocol tcp --port 80 --cidr 0.0.0.0/0 --query 'SecurityGroupRules[].{Port:FromPort,Cidr:CidrIpv4}'
[
    {
        "Port": 80,
        "Cidr": "0.0.0.0/0"
    }
]

$ awsl ec2 authorize-security-group-ingress --group-id sg-2d3363a0eb1a9a24b --protocol tcp --port 22 --cidr 203.0.113.10/32 --query 'SecurityGroupRules[].{Port:FromPort,Cidr:CidrIpv4}'
[
    {
        "Port": 22,
        "Cidr": "203.0.113.10/32"
    }
]
```

Launch a `t3.micro` with an encrypted 8 GiB gp3 root volume:

```bash
$ awsl ec2 run-instances --image-id ami-0ff5003538b60d5ec --instance-type t3.micro --key-name s18-demo-key --security-group-ids sg-2d3363a0eb1a9a24b --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=8,VolumeType=gp3,Encrypted=true}' --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=s18-demo}]' --query 'Instances[0].{InstanceId:InstanceId,State:State.Name,Type:InstanceType,PrivateIp:PrivateIpAddress}'
{
    "InstanceId": "i-4820af3a41d426865",
    "State": "pending",
    "Type": "t3.micro",
    "PrivateIp": "10.4.6.202"
}

$ awsl ec2 describe-instances --instance-ids i-4820af3a41d426865 --query 'Reservations[].Instances[].{Id:InstanceId,State:State.Name,PrivateIp:PrivateIpAddress,PublicIp:PublicIpAddress,Subnet:SubnetId,Key:KeyName}' --output table
-------------------------------------------
|            DescribeInstances            |
+------------+----------------------------+
|  Id        |  i-4820af3a41d426865       |
|  Key       |  s18-demo-key              |
|  PrivateIp |  10.4.6.202                |
|  PublicIp  |  54.214.89.193             |
|  State     |  running                   |
|  Subnet    |  subnet-7c1cf92ba1f2564f9  |
+------------+----------------------------+

$ awsl ec2 describe-volumes --filters Name=attachment.instance-id,Values=i-4820af3a41d426865 --query 'Volumes[].{VolumeId:VolumeId,Size:Size,Type:VolumeType,Encrypted:Encrypted,Device:Attachments[0].Device}' --output table
---------------------------------------------------------------------
|                          DescribeVolumes                          |
+-----------+------------+-------+-------+--------------------------+
|  Device   | Encrypted  | Size  | Type  |        VolumeId          |
+-----------+------------+-------+-------+--------------------------+
|  /dev/xvda|  True      |  8    |  gp3  |  vol-44374d03e485068f5   |
+-----------+------------+-------+-------+--------------------------+
```

The instance went from `pending` to `running`. It has a private IP and, because the default VPC's subnets auto-assign one, a public IP as well. The root volume is the EBS volume attached as `/dev/xvda`. One emulator quirk: the private IP `10.4.6.202` is not inside the default VPC's `172.31.0.0/16`. Real EC2 would always pick an address from the subnet's range.

Walk through the lifecycle:

```bash
$ awsl ec2 stop-instances --instance-ids i-4820af3a41d426865 --query 'StoppingInstances[].{Id:InstanceId,From:PreviousState.Name,To:CurrentState.Name}' --output table
------------------------------------------------
|                 StopInstances                |
+---------+-----------------------+------------+
|  From   |          Id           |    To      |
+---------+-----------------------+------------+
|  running|  i-4820af3a41d426865  |  stopping  |
+---------+-----------------------+------------+

$ awsl ec2 start-instances --instance-ids i-4820af3a41d426865 --query 'StartingInstances[].{Id:InstanceId,From:PreviousState.Name,To:CurrentState.Name}' --output table
-----------------------------------------------
|               StartInstances                |
+---------+-----------------------+-----------+
|  From   |          Id           |    To     |
+---------+-----------------------+-----------+
|  stopped|  i-4820af3a41d426865  |  pending  |
+---------+-----------------------+-----------+

$ awsl ec2 terminate-instances --instance-ids i-4820af3a41d426865 --query 'TerminatingInstances[].{Id:InstanceId,From:PreviousState.Name,To:CurrentState.Name}' --output table
-----------------------------------------------------
|                TerminateInstances                 |
+---------+-----------------------+-----------------+
|  From   |          Id           |       To        |
+---------+-----------------------+-----------------+
|  running|  i-4820af3a41d426865  |  shutting-down  |
+---------+-----------------------+-----------------+
```

`running -> stopping`, `stopped -> pending` and `running -> shutting-down` match the diagram above.

Cleanup:

```bash
$ awsl ec2 delete-security-group --group-id sg-2d3363a0eb1a9a24b

$ awsl ec2 delete-key-pair --key-name s18-demo-key --query Return
true
```
