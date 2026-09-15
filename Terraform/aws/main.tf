resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "terraform-vpc"
  }
}

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-southeast-3a"
  map_public_ip_on_launch = true

  tags = {
    Name = "terraform-public-subnet"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "terraform-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "terraform-public-route"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "server" {
  name        = "terraform-server-sg"
  description = "Security group for Terraform servers"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
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
    Name = "terraform-server-sg"
  }
}

resource "aws_key_pair" "terraform" {
  key_name   = "terraform-reza"
  public_key = file("~/.ssh/terraform-reza.pub")

  tags = {
    Name = "terraform-reza-key"
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_ami" "debian" {
  most_recent = true
  owners      = ["136693071363"]

  filter {
    name   = "name"
    values = ["debian-11-amd64-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# =========================================
# EC2 - Ubuntu 24.04
# =========================================

resource "aws_instance" "ubuntu" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.main.id
  vpc_security_group_ids      = [aws_security_group.server.id]
  key_name                    = aws_key_pair.terraform.key_name
  associate_public_ip_address = false

  credit_specification {
    cpu_credits = "standard"
  }

  tags = {
    Name = "terraform-ubuntu-24"
    OS   = "Ubuntu 24.04"
  }
}

# =========================================
# EC2 - Debian 11
# =========================================

resource "aws_instance" "debian" {
  ami                         = data.aws_ami.debian.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.main.id
  vpc_security_group_ids      = [aws_security_group.server.id]
  key_name                    = aws_key_pair.terraform.key_name
  associate_public_ip_address = false

  credit_specification {
    cpu_credits = "standard"
  }

  tags = {
    Name = "terraform-debian-11"
    OS   = "Debian 11"
  }
}

# =========================================
# Static Public IP - Ubuntu
# =========================================

resource "aws_eip" "ubuntu" {
  domain = "vpc"

  tags = {
    Name = "terraform-ubuntu-eip"
  }
}

resource "aws_eip_association" "ubuntu" {
  instance_id   = aws_instance.ubuntu.id
  allocation_id = aws_eip.ubuntu.id
}

# =========================================
# Static Public IP - Debian
# =========================================

resource "aws_eip" "debian" {
  domain = "vpc"

  tags = {
    Name = "terraform-debian-eip"
  }
}

resource "aws_eip_association" "debian" {
  instance_id   = aws_instance.debian.id
  allocation_id = aws_eip.debian.id
}

# =========================================
# EBS - Ubuntu
# =========================================

resource "aws_ebs_volume" "ubuntu" {
  availability_zone = aws_subnet.main.availability_zone
  size              = 8
  type              = "gp3"
  encrypted         = true

  tags = {
    Name = "terraform-ubuntu-data"
  }
}

resource "aws_volume_attachment" "ubuntu" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.ubuntu.id
  instance_id = aws_instance.ubuntu.id
}

# =========================================
# EBS - Debian
# =========================================

resource "aws_ebs_volume" "debian" {
  availability_zone = aws_subnet.main.availability_zone
  size              = 8
  type              = "gp3"
  encrypted         = true

  tags = {
    Name = "terraform-debian-data"
  }
}

resource "aws_volume_attachment" "debian" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.debian.id
  instance_id = aws_instance.debian.id
}

# =========================================
# Outputs
# =========================================

output "ubuntu_public_ip" {
  description = "Static public IP Ubuntu"
  value       = aws_eip.ubuntu.public_ip
}

output "debian_public_ip" {
  description = "Static public IP Debian"
  value       = aws_eip.debian.public_ip
}