# ============================================================
# TERRAFORM CONFIGURATION
# Trend Store - AWS Infrastructure
#
# Creates:
#   1. VPC
#   2. Internet Gateway
#   3. Two public subnets
#   4. Public route table
#   5. Jenkins EC2 instance
#   6. Jenkins IAM role
#   7. EKS Cluster
#   8. EKS Managed Node Group
#   9. EKS IAM roles
#  10. Jenkins access to EKS
# ============================================================


# ============================================================
# TERRAFORM / PROVIDER CONFIGURATION
# ============================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  required_version = ">= 1.5.0"
}


# ============================================================
# AWS PROVIDER
# ============================================================

provider "aws" {
  region = "ap-south-1"
}


# ============================================================
# VPC
# ============================================================

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "trendstore-vpc"
  }
}


# ============================================================
# INTERNET GATEWAY
# ============================================================

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "trendstore-igw"
  }
}


# ============================================================
# PUBLIC SUBNET - AVAILABILITY ZONE 1
# ============================================================

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true

  tags = {
    Name                     = "trendstore-public-subnet"
    "kubernetes.io/role/elb" = "1"
  }
}


# ============================================================
# PUBLIC SUBNET - AVAILABILITY ZONE 2
# ============================================================

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-south-1b"
  map_public_ip_on_launch = true

  tags = {
    Name                     = "trendstore-public-subnet-2"
    "kubernetes.io/role/elb" = "1"
  }
}


# ============================================================
# PUBLIC ROUTE TABLE
# ============================================================

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


# ============================================================
# ROUTE TABLE ASSOCIATION - SUBNET 1
# ============================================================

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}


# ============================================================
# ROUTE TABLE ASSOCIATION - SUBNET 2
# ============================================================

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}


# ============================================================
# JENKINS SECURITY GROUP
# ============================================================

resource "aws_security_group" "jenkins" {
  name        = "trendstore-jenkins-sg"
  description = "Security group for Jenkins"
  vpc_id      = aws_vpc.main.id

  # ----------------------------------------------------------
  # SSH
  # ----------------------------------------------------------

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ----------------------------------------------------------
  # JENKINS WEB UI
  # ----------------------------------------------------------

  ingress {
    description = "Jenkins"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ----------------------------------------------------------
  # HTTP
  # ----------------------------------------------------------

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ----------------------------------------------------------
  # OUTBOUND
  # ----------------------------------------------------------

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


# ============================================================
# IAM ROLE FOR JENKINS EC2
# ============================================================

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


# ============================================================
# JENKINS IAM POLICY
#
# AdministratorAccess is being retained for this assignment.
# In a real production environment, least-privilege policies
# should be used instead.
# ============================================================

resource "aws_iam_role_policy_attachment" "jenkins_admin" {
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}


# ============================================================
# JENKINS INSTANCE PROFILE
# ============================================================

resource "aws_iam_instance_profile" "jenkins" {
  name = "trendstore-jenkins-profile"
  role = aws_iam_role.jenkins.name
}


# ============================================================
# JENKINS EC2 INSTANCE
#
# Existing configuration retained.
# Jenkins was manually installed on this Ubuntu instance.
# ============================================================

resource "aws_instance" "jenkins" {
  ami           = "ami-0f918f7e67a3323f0"
  instance_type = "t3.micro"

  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.jenkins.id]
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


# ============================================================
# EKS CLUSTER IAM ROLE
# ============================================================

resource "aws_iam_role" "eks_cluster" {
  name = "trendstore-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "eks.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}


# ============================================================
# EKS CLUSTER IAM POLICY
# ============================================================

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}


# ============================================================
# EKS NODE GROUP IAM ROLE
# ============================================================

resource "aws_iam_role" "eks_node" {
  name = "trendstore-eks-node-role"

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


# ============================================================
# EKS NODE - WORKER POLICY
# ============================================================

resource "aws_iam_role_policy_attachment" "eks_node_worker" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}


# ============================================================
# EKS NODE - CNI POLICY
# ============================================================

resource "aws_iam_role_policy_attachment" "eks_node_cni" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}


# ============================================================
# EKS NODE - ECR READ-ONLY POLICY
#
# Allows worker nodes to pull Docker images from ECR.
# ============================================================

resource "aws_iam_role_policy_attachment" "eks_node_ecr" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}


# ============================================================
# EKS CLUSTER
# ============================================================

resource "aws_eks_cluster" "trend" {
  name     = "trend-eks"
  role_arn = aws_iam_role.eks_cluster.arn

  # ----------------------------------------------------------
  # EKS API ACCESS
  # ----------------------------------------------------------

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  # ----------------------------------------------------------
  # NETWORK CONFIGURATION
  # ----------------------------------------------------------

  vpc_config {
    subnet_ids = [
      aws_subnet.public.id,
      aws_subnet.public_2.id
    ]

    endpoint_public_access = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]

  tags = {
    Name = "trend-eks"
  }
}


# ============================================================
# ALLOW JENKINS IAM ROLE TO ACCESS EKS
#
# This is important because Jenkins will later run:
#
# aws eks update-kubeconfig
# kubectl apply
#
# The EC2 IAM role must therefore be an EKS access entry.
# ============================================================

resource "aws_eks_access_entry" "jenkins" {
  cluster_name  = aws_eks_cluster.trend.name
  principal_arn = aws_iam_role.jenkins.arn
  type          = "STANDARD"

  depends_on = [
    aws_eks_cluster.trend
  ]
}


# ============================================================
# GIVE JENKINS CLUSTER ADMINISTRATOR ACCESS
#
# This is convenient for the assignment.
# In production, restrict this to the namespace/actions
# actually required by the deployment pipeline.
# ============================================================

resource "aws_eks_access_policy_association" "jenkins" {
  cluster_name  = aws_eks_cluster.trend.name
  principal_arn = aws_iam_role.jenkins.arn

  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [
    aws_eks_access_entry.jenkins
  ]
}


# ============================================================
# EKS MANAGED NODE GROUP
# ============================================================

resource "aws_eks_node_group" "trend" {
  cluster_name    = aws_eks_cluster.trend.name
  node_group_name = "trend-node-group"

  node_role_arn = aws_iam_role.eks_node.arn

  # ----------------------------------------------------------
  # USE BOTH AVAILABILITY ZONES
  # ----------------------------------------------------------

  subnet_ids = [
    aws_subnet.public.id,
    aws_subnet.public_2.id
  ]

  # ----------------------------------------------------------
  # EC2 INSTANCE TYPE
  #
  # t3.small is used because it is more practical for
  # running Kubernetes workloads than t3.micro.
  # ----------------------------------------------------------

  instance_types = ["t3.micro"]

  # ----------------------------------------------------------
  # NODE SCALING
  # ----------------------------------------------------------

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 2
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_worker,
    aws_iam_role_policy_attachment.eks_node_cni,
    aws_iam_role_policy_attachment.eks_node_ecr
  ]

  tags = {
    Name = "trend-eks-node"
  }
}