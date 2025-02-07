
resource "aws_vpc" "demo" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "demo-vpc"
  }
}

# Public Subnets
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.demo.id
  cidr_block              = var.public_subnet_cidr_block_1
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name                           = "public-subnet"
    "kubernetes.io/role/elb"       = "1"
    "kubernetes.io/cluster/my-eks-cluster"   = "owned"
  }
}

resource "aws_subnet" "public_subnet2" {
  vpc_id                  = aws_vpc.demo.id
  cidr_block              = var.public_subnet_cidr_block_2
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name                           = "public-subnet2"
    "kubernetes.io/role/elb"       = "1"
    "kubernetes.io/cluster/my-eks-cluster"   = "owned"
  }
}

# Private Subnets
resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.demo.id
  cidr_block        = var.private_subnet_cidr_block_1
  availability_zone = "us-east-1a"

  tags = {
    Name                                = "private-subnet"
    "kubernetes.io/role/internal-elb"   = "1"
    "kubernetes.io/cluster/my-eks-cluster"   = "owned"
  }
}

resource "aws_subnet" "private_subnet2" {
  vpc_id            = aws_vpc.demo.id
  cidr_block        = var.private_subnet_cidr_block_2
  availability_zone = "us-east-1b"

  tags = {
    Name                                = "private-subnet2"
    "kubernetes.io/role/internal-elb"   = "1"
    "kubernetes.io/cluster/my-eks-cluster"   = "owned"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.demo.id

  tags = { Name = "demo-igw" }
}

# Public Route Table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.demo.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "public-route-table" }
}

# Associate Public Subnets with Public Route Table
resource "aws_route_table_association" "public_route_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public_route_assoc_2" {
  subnet_id      = aws_subnet.public_subnet2.id
  route_table_id = aws_route_table.public_route_table.id
}

# Create Elastic IP for NAT Gateway
resource "aws_eip" "nat_ip" {
  domain = "vpc"
}

# Create NAT Gateway
resource "aws_nat_gateway" "ngw" {
  allocation_id = aws_eip.nat_ip.id
  subnet_id     = aws_subnet.public_subnet.id

  tags = { Name = "demo-nat-gateway" }
  depends_on = [aws_internet_gateway.igw]
}

# Private Route Table
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.demo.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ngw.id
  }

  tags = { Name = "private-route-table" }
}

# Associate Private Subnets with Private Route Table
resource "aws_route_table_association" "private_route_assoc" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_route_table_association" "private_route_assoc_2" {
  subnet_id      = aws_subnet.private_subnet2.id
  route_table_id = aws_route_table.private_route_table.id
}
# Create ECR Repository
resource "aws_ecr_repository" "my_ecr_repo" {
  name = "my-ecr-repo"

  tags = { Name = "my-ecr-repo" }
}

# IAM Role for EKS Cluster
resource "aws_iam_role" "eks_cluster_role" {
  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": { "Service": "eks.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }]
  })

  tags = { Name = "eks-cluster-role" }
}

# Attach Policy to EKS Cluster Role
resource "aws_iam_role_policy_attachment" "eks_cluster_policy_attachment" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# IAM Role for EKS Nodes
resource "aws_iam_role" "eks_node_group_role" {
  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }]
  })

  tags = { Name = "eks-node-group-role" }
}

# Attach Policies to EKS Node Role
resource "aws_iam_role_policy_attachment" "eks_node_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AutoScalingFullAccess",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly", 
  ])

  role       = aws_iam_role.eks_node_group_role.name
  policy_arn = each.value
}

# Create EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = "my-eks-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids = [aws_subnet.private_subnet.id, aws_subnet.private_subnet2.id]
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy_attachment]

  tags = { Name = "my-eks-cluster" }
}

# Create EKS Node Group
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "my-node-group"
  node_role_arn   = aws_iam_role.eks_node_group_role.arn
  subnet_ids      = [aws_subnet.private_subnet.id, aws_subnet.private_subnet2.id]

  scaling_config {
    desired_size = 3
    max_size     = 4
    min_size     = 1
  }

  instance_types = ["t2.medium"]
  capacity_type  = "ON_DEMAND"

  depends_on = [aws_eks_cluster.main]
  #tags = { Name = "my-node-group" }

} 
