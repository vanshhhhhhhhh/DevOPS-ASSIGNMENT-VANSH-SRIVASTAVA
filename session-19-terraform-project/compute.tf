resource "aws_instance" "web" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.web.name

  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    bucket = aws_s3_bucket.site.bucket
    region = var.aws_region
  })
  user_data_replace_on_change = true

  # IMDSv2 only (blocks the old token-less metadata calls).
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  # Encrypted gp3 root disk. 8 GiB = size of the AL2023 AMI snapshot (the minimum allowed).
  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = "${local.name}-web" }

  # Explicit dependency. Nothing above references these two resources, but the
  # user_data script needs them at first boot:
  #  - the public route to the internet gateway, to reach the package repo and S3
  #  - the index.html object, which it downloads from the bucket
  # Without depends_on Terraform could start the instance before either exists.
  depends_on = [
    aws_route_table_association.public,
    aws_s3_object.index,
  ]
}
