# Amazon VPC (Virtual Private Cloud)

**Name:** Vansh Srivastava | **Enrollment No.:** 24bcs10567 | **Session:** 18, Task 2

## What is a VPC

A VPC is my own isolated private network inside an AWS region. I choose its IP range, split it into subnets, decide how traffic is routed and which traffic is allowed. EC2 instances, RDS databases, load balancers, Lambda functions attached to a VPC and EKS nodes all get their IP addresses from a VPC.

A VPC belongs to **one region** and spans all of its Availability Zones. Each **subnet** belongs to **one AZ**. Every account has a **default VPC** (`172.31.0.0/16`) in each region with a public subnet per AZ, so you can launch quickly. Real projects create their own VPC, as I do with Terraform in Session 19.

## CIDR

CIDR notation describes an IP range as `base-address/prefix-length`. The prefix length is how many leading bits are fixed. The remaining bits are free for hosts:

| CIDR | Free bits | Addresses |
|---|---|---|
| `10.30.0.0/16` | 16 | 65,536 |
| `10.30.1.0/24` | 8 | 256 |
| `10.30.1.0/28` | 4 | 16 |

- A VPC's IPv4 block must be between `/16` and `/28`. Use a private (RFC 1918) range: `10.0.0.0/8`, `172.16.0.0/12` or `192.168.0.0/16`.
- Subnets carve non-overlapping pieces out of the VPC range.
- AWS reserves **5 addresses in every subnet**: the network address, `.1` (VPC router), `.2` (DNS), `.3` (reserved for future use) and the last address. A `/24` therefore has 256 - 5 = **251** usable IPs, which is exactly what the subnet output below shows.
- Plan ranges so they do not overlap with other VPCs or your office network, otherwise peering and VPN become impossible.

## Subnets

A subnet is a slice of the VPC's range in one AZ. Subnets let you place resources by role (public web tier, private app tier, isolated database tier) and spread them over AZs for high availability. Settings per subnet include `map_public_ip_on_launch` (auto-assign public IPs), the associated route table and the associated network ACL.

## Route tables

A route table is a list of `destination -> target` rules that decides where traffic leaving a subnet goes. The most specific matching destination wins.

- Every route table has a **`local`** route for the VPC's CIDR. It cannot be removed, so everything inside the VPC can reach everything else (security groups and NACLs still apply).
- The VPC has a **main** route table. A subnet without an explicit association uses it.
- Each subnet is associated with exactly one route table. One route table can serve many subnets.
- Typical targets: an internet gateway (`igw-`), a NAT gateway (`nat-`), a transit gateway, a peering connection, a VPC endpoint.

## Internet gateway (IGW)

An internet gateway connects a VPC to the internet. It is horizontally scaled and highly available, with nothing to size, and costs nothing by itself. One VPC has at most one IGW. It does two jobs:

1. It is the target for `0.0.0.0/0` routes in public route tables.
2. It translates between an instance's private IP and its public or Elastic IP (one-to-one NAT).

Creating and attaching an IGW alone makes nothing public. A subnet also needs a route to it, and the instance needs a public IP.

## NAT gateway

A NAT gateway lets instances in **private** subnets start connections *out* to the internet (OS updates, external APIs) while nothing on the internet can start a connection *in* to them.

- It sits in a **public** subnet and has an Elastic IP.
- The private subnets' route tables send `0.0.0.0/0` to the NAT gateway.
- It is managed and scales automatically, but it is billed **per hour and per GB processed**. Run one per AZ for high availability, because a NAT gateway in one AZ is a single point of failure for the other AZs.
- For AWS services such as S3 and DynamoDB, a free **gateway VPC endpoint** avoids sending that traffic through NAT at all.

I left NAT out of my Session 19 project because it would be the only paid component.

## Security groups

Security groups are stateful, allow-only firewalls on each network interface (instance level). The [EC2 notes](../02-ec2/README.md#security-groups) cover them in detail. Inside a VPC their most useful feature is referencing other groups: "database SG allows 5432 from the app SG".

## Network ACLs (NACLs)

A network ACL is a firewall at the **subnet** boundary:

- **Stateless**: return traffic has to be allowed explicitly. For outbound replies to inbound requests that means opening the ephemeral port range `1024-65535`.
- Rules can **allow and deny**, are numbered, and are evaluated **lowest number first**. The first match wins.
- Every NACL ends with a `*` rule that denies everything. The API shows it as rule `32767`.
- The **default** NACL allows all traffic in both directions. A **new custom** NACL denies everything until you add rules.

Most setups leave NACLs open and do the real filtering with security groups. NACLs are useful for coarse blocks, such as denying a known bad IP range for a whole subnet.

| | Security group | Network ACL |
|---|---|---|
| Applies to | network interface (instance) | subnet |
| State | stateful | stateless |
| Rules | allow only | allow and deny |
| Evaluation | all rules together | in order, first match wins |
| Default | deny in, allow out | default NACL allows all |

## Public vs private subnet

AWS has no "public" checkbox. The difference is only routing:

- **Public subnet**: its route table has `0.0.0.0/0 -> igw-...`. Instances with a public IP are reachable from the internet, subject to their security groups. Use it for load balancers, bastion hosts, NAT gateways and simple web servers.
- **Private subnet**: no route to an IGW. It may have `0.0.0.0/0 -> nat-...` for outbound-only access, or no internet route at all (an "isolated" subnet). Use it for app servers, databases and caches.

A common layout is a public and a private subnet in each of two or three AZs, with the load balancer in the public subnets and everything else private.

```text
                 Internet
                    |
             [Internet Gateway]
                    |
   +----------------+---------------- VPC 10.30.0.0/16 ----+
   |  Public subnet 10.30.1.0/24 (AZ a)                     |
   |    route: 0.0.0.0/0 -> IGW                             |
   |    [load balancer / web server]  [NAT gateway]         |
   |                                       |                |
   |  Private subnet 10.30.2.0/24 (AZ b)   |                |
   |    route: 0.0.0.0/0 -> NAT (optional) +                |
   |    [app server] [database]                             |
   +--------------------------------------------------------+
```

## Hands-on: building a small VPC by hand on LocalStack

`awsl` is my wrapper that runs the AWS CLI against LocalStack (see the [session README](../../README.md#localstack-setup)). In Session 19 I build the same thing with Terraform. Doing it once by hand showed me how many separate API objects and IDs Terraform keeps track of.

VPC and two subnets in different AZs:

```bash
$ awsl ec2 create-vpc --cidr-block 10.30.0.0/16 --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=s18-research-vpc}]' --query 'Vpc.{VpcId:VpcId,Cidr:CidrBlock,State:State}'
{
    "VpcId": "vpc-e1f11ffa6fbbbb729",
    "Cidr": "10.30.0.0/16",
    "State": "available"
}

$ awsl ec2 create-subnet --vpc-id vpc-e1f11ffa6fbbbb729 --cidr-block 10.30.1.0/24 --availability-zone ap-south-1a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=s18-public-a}]' --query 'Subnet.{SubnetId:SubnetId,Cidr:CidrBlock,AZ:AvailabilityZone,FreeIPs:AvailableIpAddressCount}'
{
    "SubnetId": "subnet-7fb8fce853e44d446",
    "Cidr": "10.30.1.0/24",
    "AZ": "ap-south-1a",
    "FreeIPs": 251
}

$ awsl ec2 create-subnet --vpc-id vpc-e1f11ffa6fbbbb729 --cidr-block 10.30.2.0/24 --availability-zone ap-south-1b --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=s18-private-b}]' --query 'Subnet.{SubnetId:SubnetId,Cidr:CidrBlock,AZ:AvailabilityZone,FreeIPs:AvailableIpAddressCount}'
{
    "SubnetId": "subnet-99160176675981fe2",
    "Cidr": "10.30.2.0/24",
    "AZ": "ap-south-1b",
    "FreeIPs": 251
}
```

`FreeIPs: 251` in each `/24`, because of the 5 reserved addresses.

Internet gateway, a route table with a default route to it, and the association that turns `s18-public-a` into a public subnet:

```bash
$ awsl ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text
igw-7243a2528dc39253f

$ awsl ec2 attach-internet-gateway --internet-gateway-id igw-7243a2528dc39253f --vpc-id vpc-e1f11ffa6fbbbb729

$ awsl ec2 create-route-table --vpc-id vpc-e1f11ffa6fbbbb729 --query 'RouteTable.RouteTableId' --output text
rtb-2416d35dbcadb42c3

$ awsl ec2 create-route --route-table-id rtb-2416d35dbcadb42c3 --destination-cidr-block 0.0.0.0/0 --gateway-id igw-7243a2528dc39253f
{
    "Return": true
}

$ awsl ec2 associate-route-table --route-table-id rtb-2416d35dbcadb42c3 --subnet-id subnet-7fb8fce853e44d446 --query AssociationId --output text
rtbassoc-88edae44d5aa6933c

$ awsl ec2 describe-route-tables --filters Name=vpc-id,Values=vpc-e1f11ffa6fbbbb729 --query 'RouteTables[].{RouteTable:RouteTableId,Main:Associations[0].Main,Subnets:join(`,`, Associations[?SubnetId].SubnetId),Routes:Routes[].join(`" -> "`, [DestinationCidrBlock, GatewayId])}' --output json
[
    {
        "RouteTable": "rtb-e85b61c882c5abbdc",
        "Main": true,
        "Subnets": "",
        "Routes": [
            "10.30.0.0/16 -> local"
        ]
    },
    {
        "RouteTable": "rtb-2416d35dbcadb42c3",
        "Main": false,
        "Subnets": "subnet-7fb8fce853e44d446",
        "Routes": [
            "10.30.0.0/16 -> local",
            "0.0.0.0/0 -> igw-7243a2528dc39253f"
        ]
    }
]
```

The **main** route table (created with the VPC) only has the `local` route. The private subnet uses it implicitly, so it has no way out. My custom table adds `0.0.0.0/0 -> igw-...` and is associated with the public subnet.

The VPC's default network ACL:

```bash
$ awsl ec2 describe-network-acls --filters Name=vpc-id,Values=vpc-e1f11ffa6fbbbb729 --query 'NetworkAcls[].Entries[].{Rule:RuleNumber,Egress:Egress,Protocol:Protocol,Cidr:CidrBlock,Action:RuleAction}' --output table
--------------------------------------------------------
|                  DescribeNetworkAcls                 |
+--------+------------+---------+------------+---------+
| Action |   Cidr     | Egress  | Protocol   |  Rule   |
+--------+------------+---------+------------+---------+
|  allow |  0.0.0.0/0 |  True   |  -1        |  100    |
|  deny  |  0.0.0.0/0 |  True   |  -1        |  32767  |
|  allow |  0.0.0.0/0 |  False  |  -1        |  100    |
|  deny  |  0.0.0.0/0 |  False  |  -1        |  32767  |
+--------+------------+---------+------------+---------+
```

Rule `100` allows all traffic in each direction and rule `32767` (the `*` rule) denies whatever is left, so the default NACL lets everything through.

Cleanup has to go in reverse dependency order. AWS refuses to delete a VPC that still has subnets, gateways or route tables in it, which is exactly the ordering Terraform works out by itself during `destroy`:

```bash
$ awsl ec2 disassociate-route-table --association-id rtbassoc-88edae44d5aa6933c
$ awsl ec2 delete-route-table --route-table-id rtb-2416d35dbcadb42c3
$ awsl ec2 detach-internet-gateway --internet-gateway-id igw-7243a2528dc39253f --vpc-id vpc-e1f11ffa6fbbbb729
$ awsl ec2 delete-internet-gateway --internet-gateway-id igw-7243a2528dc39253f
$ awsl ec2 delete-subnet --subnet-id subnet-7fb8fce853e44d446
$ awsl ec2 delete-subnet --subnet-id subnet-99160176675981fe2
$ awsl ec2 delete-vpc --vpc-id vpc-e1f11ffa6fbbbb729

$ awsl ec2 describe-vpcs --filters Name=tag:Name,Values=s18-research-vpc --query 'Vpcs[].VpcId'
[]
```
