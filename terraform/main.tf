
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  required_version = ">= 1.5.0"
}

provider "aws" {
  region = "ap-south-1"
}

# -------------------------
# VPC
# -------------------------

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "trendstore-vpc"
  }
}

# -------------------------
# Internet Gateway
# -------------------------

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "trendstore-igw"
  }
}

# -------------------------
# Public Subnet
# -------------------------

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "trendstore-public-subnet"
  }
}

# -------------------------
# Route Table
# -------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "trendstore-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# -------------------------
# Jenkins Security Group
# -------------------------

resource "aws_security_group" "jenkins" {
  name        = "trendstore-jenkins-sg"
  description = "Security group for Jenkins"
  vpc_id      = aws_vpc.main.id

  # SSH
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Jenkins
  ingress {
    description = "Jenkins"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "trendstore-jenkins-sg"
  }
}

# -------------------------
# IAM Role for Jenkins EC2
# -------------------------

resource "aws_iam_role" "jenkins" {
  name = "trendstore-jenkins-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Allow Jenkins EC2 to work with AWS resources
resource "aws_iam_role_policy_attachment" "jenkins_admin" {
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_instance_profile" "jenkins" {
  name = "trendstore-jenkins-profile"
  role = aws_iam_role.jenkins.name
}

# -------------------------
# Jenkins EC2
# -------------------------

resource "aws_instance" "jenkins" {
  ami           = "ami-0f918f7e67a3323f0"
  instance_type = "t3.micro"

  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids     = [aws_security_group.jenkins.id]
  associate_public_ip_address = true

  iam_instance_profile = aws_iam_instance_profile.jenkins.name

  user_data = <<-EOF
              #!/bin/bash

              yum update -y

              amazon-linux-extras install java-openjdk11 -y || true

              yum install -y git docker

              systemctl enable docker
              systemctl start docker

              curl -fsSL https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key \
                -o /etc/pki/rpm-gpg/jenkins.io-2023.key

              rpm --import /etc/pki/rpm-gpg/jenkins.io-2023.key

              wget -O /etc/yum.repos.d/jenkins.repo \
                https://pkg.jenkins.io/redhat-stable/jenkins.repo

              yum install -y jenkins

              systemctl enable jenkins
              systemctl start jenkins

              usermod -aG docker jenkins

              systemctl restart jenkins
              EOF

  tags = {
    Name = "trendstore-jenkins"
  }
}