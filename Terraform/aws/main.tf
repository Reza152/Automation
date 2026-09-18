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

  ingress {
    description = "Node Exporter"
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Grafana"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Prometheus"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "cAdvisor"
    from_port   = 8080
    to_port     = 8080
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
# TERRAFORM SERVERS
# ==========================================================

resource "aws_instance" "terraform_servers" {
  for_each = {
    for name, server in var.servers :
    name => server
    if server.group == "terraform"
  }

  ami = each.value.os == "ubuntu" ? data.aws_ami.ubuntu.id : data.aws_ami.debian.id

  instance_type = each.value.instance_type

  subnet_id              = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.server.id]
  key_name               = aws_key_pair.terraform.key_name

  associate_public_ip_address = true

  credit_specification {
    cpu_credits = "standard"
  }

  tags = {
    Name = each.value.os == "ubuntu" ? "terraform-ubuntu-24" : "terraform-debian-11"
    OS   = each.value.os == "ubuntu" ? "Ubuntu 24.04" : "Debian 11"
  }
}

# ==========================================================
# ANSIBLE SERVERS
# ==========================================================

resource "aws_instance" "ansible_servers" {
  for_each = {
    for name, server in var.servers :
    name => server
    if server.group == "ansible"
  }

  ami = data.aws_ami.ubuntu.id

  instance_type = each.value.instance_type

  subnet_id              = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.server.id]
  key_name               = aws_key_pair.terraform.key_name

  associate_public_ip_address = true

  credit_specification {
    cpu_credits = "standard"
  }

  tags = {
    Name = each.key
    OS   = "Ubuntu 24.04"
    Role = "Ansible Target"
  }
}

# ==========================================================
# ELASTIC IP
# ==========================================================

resource "aws_eip" "servers" {
  for_each = var.servers

  domain = "vpc"

  tags = {
    Name = "${each.key}-eip"
  }
}

# ==========================================================
# ELASTIC IP ASSOCIATION
# ==========================================================

resource "aws_eip_association" "servers" {
  for_each = var.servers

  instance_id = each.value.group == "terraform" ? aws_instance.terraform_servers[each.key].id : aws_instance.ansible_servers[each.key].id

  allocation_id = aws_eip.servers[each.key].id
}

# ==========================================================
# EBS VOLUMES
# Only Terraform servers receive additional EBS
# ==========================================================

resource "aws_ebs_volume" "servers" {
  for_each = {
    for name, server in var.servers :
    name => server
    if server.group == "terraform" && try(server.disk_size, 0) > 0
  }

  availability_zone = "${var.aws_region}a"
  size              = each.value.disk_size
  type              = "gp3"
  encrypted         = true

  tags = {
    Name = "${each.key}-data"
  }
}

# ==========================================================
# EBS VOLUME ATTACHMENT
# ==========================================================

resource "aws_volume_attachment" "servers" {
  for_each = {
    for name, server in var.servers :
    name => server
    if server.group == "terraform" && try(server.disk_size, 0) > 0
  }

  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.servers[each.key].id
  instance_id = aws_instance.terraform_servers[each.key].id
}

# ==========================================================
# MOVED BLOCKS - EC2
# ==========================================================

moved {
  from = aws_instance.ubuntu
  to   = aws_instance.terraform_servers["terraform-ubuntu"]
}

moved {
  from = aws_instance.debian
  to   = aws_instance.terraform_servers["terraform-debian"]
}

moved {
  from = aws_instance.ansible_ubuntu_1
  to   = aws_instance.ansible_servers["ansible-ubuntu-1"]
}

moved {
  from = aws_instance.ansible_ubuntu_2
  to   = aws_instance.ansible_servers["ansible-ubuntu-2"]
}

# ==========================================================
# MOVED BLOCKS - EIP
# ==========================================================

moved {
  from = aws_eip.ubuntu
  to   = aws_eip.servers["terraform-ubuntu"]
}

moved {
  from = aws_eip.debian
  to   = aws_eip.servers["terraform-debian"]
}

moved {
  from = aws_eip.ansible_ubuntu_1
  to   = aws_eip.servers["ansible-ubuntu-1"]
}

moved {
  from = aws_eip.ansible_ubuntu_2
  to   = aws_eip.servers["ansible-ubuntu-2"]
}

# ==========================================================
# MOVED BLOCKS - EIP ASSOCIATION
# ==========================================================

moved {
  from = aws_eip_association.ubuntu
  to   = aws_eip_association.servers["terraform-ubuntu"]
}

moved {
  from = aws_eip_association.debian
  to   = aws_eip_association.servers["terraform-debian"]
}

moved {
  from = aws_eip_association.ansible_ubuntu_1
  to   = aws_eip_association.servers["ansible-ubuntu-1"]
}

moved {
  from = aws_eip_association.ansible_ubuntu_2
  to   = aws_eip_association.servers["ansible-ubuntu-2"]
}

# ==========================================================
# MOVED BLOCKS - EBS
# ==========================================================

moved {
  from = aws_ebs_volume.ubuntu
  to   = aws_ebs_volume.servers["terraform-ubuntu"]
}

moved {
  from = aws_ebs_volume.debian
  to   = aws_ebs_volume.servers["terraform-debian"]
}

# ==========================================================
# MOVED BLOCKS - EBS ATTACHMENT
# ==========================================================

moved {
  from = aws_volume_attachment.ubuntu
  to   = aws_volume_attachment.servers["terraform-ubuntu"]
}

moved {
  from = aws_volume_attachment.debian
  to   = aws_volume_attachment.servers["terraform-debian"]
}

# ==========================================================
# OUTPUT
# ==========================================================

output "ubuntu_public_ip" {
  description = "Public IP Terraform Ubuntu"
  value       = aws_eip.servers["terraform-ubuntu"].public_ip
}

output "debian_public_ip" {
  description = "Public IP Terraform Debian"
  value       = aws_eip.servers["terraform-debian"].public_ip
}

output "ansible_ubuntu_1_public_ip" {
  description = "Public IP Ansible Ubuntu 1"
  value       = aws_eip.servers["ansible-ubuntu-1"].public_ip
}

output "ansible_ubuntu_2_public_ip" {
  description = "Public IP Ansible Ubuntu 2"
  value       = aws_eip.servers["ansible-ubuntu-2"].public_ip
}