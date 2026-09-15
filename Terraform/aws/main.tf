# ==========================================================
# VPC
# ==========================================================

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "terraform-vpc"
  }
}

# ==========================================================
# PUBLIC SUBNET
# ==========================================================

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "terraform-public-subnet"
  }
}

# ==========================================================
# INTERNET GATEWAY
# ==========================================================

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "terraform-igw"
  }
}

# ==========================================================
# PUBLIC ROUTE TABLE
# ==========================================================

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

# ==========================================================
# SECURITY GROUP
# ==========================================================

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
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "terraform-server-sg"
  }
}

# ==========================================================
# SSH KEY PAIR
# ==========================================================

resource "aws_key_pair" "terraform" {
  key_name   = "terraform-reza"
  public_key = file("~/.ssh/terraform-reza.pub")

  tags = {
    Name = "terraform-reza-key"
  }
}

# ==========================================================
# UBUNTU 24.04 AMI
# ==========================================================

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# ==========================================================
# DEBIAN 11 AMI
# ==========================================================

data "aws_ami" "debian" {
  most_recent = true
  owners      = ["136693071363"]

  filter {
    name   = "name"
    values = ["debian-11-amd64-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# ==========================================================
# TERRAFORM SERVER 1
# UBUNTU 24.04
# ==========================================================

resource "aws_instance" "ubuntu" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"

  subnet_id                   = aws_subnet.main.id
  vpc_security_group_ids      = [aws_security_group.server.id]
  key_name                    = aws_key_pair.terraform.key_name
  associate_public_ip_address = true

  credit_specification {
    cpu_credits = "standard"
  }

  tags = {
    Name = "terraform-ubuntu-24"
    OS   = "Ubuntu 24.04"
  }
}

# ==========================================================
# TERRAFORM SERVER 2
# DEBIAN 11
# ==========================================================

resource "aws_instance" "debian" {
  ami           = data.aws_ami.debian.id
  instance_type = "t3.micro"

  subnet_id                   = aws_subnet.main.id
  vpc_security_group_ids      = [aws_security_group.server.id]
  key_name                    = aws_key_pair.terraform.key_name
  associate_public_ip_address = true

  credit_specification {
    cpu_credits = "standard"
  }

  tags = {
    Name = "terraform-debian-11"
    OS   = "Debian 11"
  }
}

# ==========================================================
# ELASTIC IP - TERRAFORM UBUNTU
# ==========================================================

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

# ==========================================================
# ELASTIC IP - TERRAFORM DEBIAN
# ==========================================================

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

# ==========================================================
# EBS - TERRAFORM UBUNTU
# ==========================================================

resource "aws_ebs_volume" "ubuntu" {
  availability_zone = "${var.aws_region}a"
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

# ==========================================================
# EBS - TERRAFORM DEBIAN
# ==========================================================

resource "aws_ebs_volume" "debian" {
  availability_zone = "${var.aws_region}a"
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

# ==========================================================
# ANSIBLE SERVER 1
# UBUNTU 24.04
# ==========================================================

resource "aws_instance" "ansible_ubuntu_1" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"

  subnet_id                   = aws_subnet.main.id
  vpc_security_group_ids      = [aws_security_group.server.id]
  key_name                    = aws_key_pair.terraform.key_name
  associate_public_ip_address = true

  credit_specification {
    cpu_credits = "standard"
  }

  tags = {
    Name = "ansible-ubuntu-1"
    OS   = "Ubuntu 24.04"
    Role = "Ansible Target"
  }
}

# ==========================================================
# ANSIBLE SERVER 2
# UBUNTU 24.04
# ==========================================================

resource "aws_instance" "ansible_ubuntu_2" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"

  subnet_id                   = aws_subnet.main.id
  vpc_security_group_ids      = [aws_security_group.server.id]
  key_name                    = aws_key_pair.terraform.key_name
  associate_public_ip_address = true

  credit_specification {
    cpu_credits = "standard"
  }

  tags = {
    Name = "ansible-ubuntu-2"
    OS   = "Ubuntu 24.04"
    Role = "Ansible Target"
  }
}

# ==========================================================
# ELASTIC IP - ANSIBLE UBUNTU 1
# ==========================================================

resource "aws_eip" "ansible_ubuntu_1" {
  domain = "vpc"

  tags = {
    Name = "ansible-ubuntu-1-eip"
  }
}

resource "aws_eip_association" "ansible_ubuntu_1" {
  instance_id   = aws_instance.ansible_ubuntu_1.id
  allocation_id = aws_eip.ansible_ubuntu_1.id
}

# ==========================================================
# ELASTIC IP - ANSIBLE UBUNTU 2
# ==========================================================

resource "aws_eip" "ansible_ubuntu_2" {
  domain = "vpc"

  tags = {
    Name = "ansible-ubuntu-2-eip"
  }
}

resource "aws_eip_association" "ansible_ubuntu_2" {
  instance_id   = aws_instance.ansible_ubuntu_2.id
  allocation_id = aws_eip.ansible_ubuntu_2.id
}

# ==========================================================
# OUTPUT
# ==========================================================

output "ubuntu_public_ip" {
  description = "Public IP Terraform Ubuntu"
  value       = aws_eip.ubuntu.public_ip
}

output "debian_public_ip" {
  description = "Public IP Terraform Debian"
  value       = aws_eip.debian.public_ip
}

output "ansible_ubuntu_1_public_ip" {
  description = "Public IP Ansible Ubuntu 1"
  value       = aws_eip.ansible_ubuntu_1.public_ip
}

output "ansible_ubuntu_2_public_ip" {
  description = "Public IP Ansible Ubuntu 2"
  value       = aws_eip.ansible_ubuntu_2.public_ip
}