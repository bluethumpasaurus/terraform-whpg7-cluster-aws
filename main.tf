terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = "EDBPowerUserIAM-32816034393" # Using your named SSO profile
}

# ------------------------------------------------------------------------------
# NETWORKING
# ------------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "${var.cluster_name}-vpc"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = false
  availability_zone       = "${var.aws_region}a"

  tags = {
    Name = "${var.cluster_name}-public-subnet"
  }
}

# --- ADDED: Private Subnet for servers without public IPs ---
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "${var.cluster_name}-private-subnet"
  }
}
# ----------------------------------------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# --- ADDED: EIP and NAT Gateway for private subnet internet access ---
resource "aws_eip" "nat" {
  # The 'instance' tag here is deprecated
  depends_on = [aws_internet_gateway.gw]
  tags = {
    Name = "${var.cluster_name}-nat-eip"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "${var.cluster_name}-nat-gw"
  }
}
# ---------------------------------------------------------------------

# --- ADDED: Route Table for the private subnet ---
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.cluster_name}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}
# -------------------------------------------------

# ------------------------------------------------------------------------------
# SECURITY
# ------------------------------------------------------------------------------

resource "aws_security_group" "public_access" {
  name        = "${var.cluster_name}-public-access"
  description = "Allow SSH and Ping inbound traffic"
  vpc_id      = aws_vpc.main.id

  # --- ADD THIS NEW RULE ---
  # This rule allows all inbound traffic from any instance within the VPC.
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # "-1" means all protocols
    cidr_blocks = [aws_vpc.main.cidr_block]
    description = "Allow all internal VPC traffic"
  }
  # -------------------------
  
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.jumpbox_ssh_ingress}/32"]
    description = "Allow SSH access from external IP"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    self        = true
    description = "Allow internal SSH between cluster members"
  }

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow Ping"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-public-sg"
  }
}

# ------------------------------------------------------------------------------
# COMPUTE
# ------------------------------------------------------------------------------

resource "aws_key_pair" "deployer" {
  key_name   = "${var.cluster_name}-key"
  public_key = file(pathexpand(var.public_key_path))
}

resource "aws_instance" "server" {
  count = 4

  ami                    = "ami-020c6cfb9f8b61b53"
  instance_type          = var.instance_type
  # --- MODIFIED: Conditionally assign subnets ---
  # Servers 1 & 2 go in the public subnet; Servers 3 & 4 go in the private subnet.
  subnet_id              = count.index < 2 ? aws_subnet.public.id : aws_subnet.private.id
  # ----------------------------------------------
  vpc_security_group_ids = [aws_security_group.public_access.id]
  key_name               = aws_key_pair.deployer.key_name
  user_data = templatefile("${path.module}/configure-instance.sh.tpl", {
    edb_token = var.edb_repo_token
  })

  tags = {
    Name     = "${var.cluster_name}-server-${count.index + 1}"
    Cluster  = var.cluster_name
  }
}

resource "aws_eip" "public_ip" {
  count = 2
  depends_on = [aws_instance.server]
  
  tags = {
    Name     = "${var.cluster_name}-server-${count.index + 1}"
    Cluster  = var.cluster_name
    Schedule = "emea-office-hours"
  }
}

resource "aws_eip_association" "eip_assoc" {
  count         = 2
  instance_id   = aws_instance.server[count.index].id
  allocation_id = aws_eip.public_ip[count.index].id
}