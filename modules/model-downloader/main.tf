# modules/model-downloader/main.tf
# Creates an EC2 instance to download Hugging Face models to S3

data "aws_ami" "ubuntu_arm64" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-22.04-arm64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

data "aws_region" "current" {}

# Security group for the downloader instance
resource "aws_security_group" "model_downloader" {
  name        = "${var.instance_name}-sg"
  description = "Security group for model downloader instance"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    {
      Name = "${var.instance_name}-sg"
    },
    var.tags
  )
}

# IAM role for the downloader instance
resource "aws_iam_role" "model_downloader" {
  name = "${var.instance_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# IAM instance profile
resource "aws_iam_instance_profile" "model_downloader" {
  name = "${var.instance_name}-profile"
  role = aws_iam_role.model_downloader.name
}

# Attach the S3 upload policy
resource "aws_iam_role_policy_attachment" "s3_uploader" {
  role       = aws_iam_role.model_downloader.name
  policy_arn = var.iam_policy_arn
}

# Allow SSM access for management
resource "aws_iam_role_policy_attachment" "ssm_access" {
  role       = aws_iam_role.model_downloader.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Model downloader instance
resource "aws_instance" "model_downloader" {
  ami                  = data.aws_ami.ubuntu_arm64.id
  instance_type        = var.instance_type
  subnet_id            = var.subnet_id
  security_groups      = [aws_security_group.model_downloader.id]
  iam_instance_profile = aws_iam_instance_profile.model_downloader.name

  user_data = templatefile("${path.module}/scripts/model_downloader.sh.tpl", {
    models     = jsonencode(var.models)
    s3_bucket  = var.s3_bucket_name
    aws_region = data.aws_region.current.name
  })

  root_block_device {
    volume_size = 100 # Large enough for model downloads
    volume_type = "gp3"
  }

  tags = merge(
    {
      Name = var.instance_name
    },
    var.tags
  )

  # This instance is temporary and can be destroyed after models are uploaded
  lifecycle {
    create_before_destroy = true
  }
}


