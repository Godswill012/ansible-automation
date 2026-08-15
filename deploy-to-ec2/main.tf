provider "aws" {
  region = "us-east-2"
}

variable vpc_cidr_block {}
variable subnet_cidr_block {}
variable avail_zone {}
variable env_prefix {}
variable my_ip {}
variable public_key_location {}
variable ssh_key_private {}
variable "servers" {
  type = map(object({
    instance_type = string
    env           = string
  }))
}

resource "aws_vpc" "myapp-vpc" {
  cidr_block = var.vpc_cidr_block
  enable_dns_hostnames = true
  tags = {
    Name: "${var.env_prefix}-vpc"
  }
}

resource "aws_subnet" "myapp-subnet-1" {
  vpc_id = aws_vpc.myapp-vpc.id
  cidr_block = var.subnet_cidr_block
  availability_zone = var.avail_zone
    tags = {
    Name: "${var.env_prefix}-subnet-1"
  }
}

resource "aws_internet_gateway" "myapp-igw" {
  vpc_id = aws_vpc.myapp-vpc.id
  tags = {
    Name: "${var.env_prefix}-igw"
  }
}

resource "aws_default_route_table" "main-rtb" {
  default_route_table_id = aws_vpc.myapp-vpc.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.myapp-igw.id
  }
  tags = {
    Name: "${var.env_prefix}-main-rtb"
  }
}

resource "aws_default_security_group" "default-sg" {
  vpc_id = aws_vpc.myapp-vpc.id

  ingress {
    from_port = 22
    to_port = 22
    protocol = "TCP"
    cidr_blocks = [var.my_ip]
  }

  ingress {
    from_port = 8080
    to_port = 8080
    protocol = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    prefix_list_ids = []
  }

  tags = {
    Name: "${var.env_prefix}-default-sg"
  }
}

data "aws_ami" "latest-amazon-linux-image" {
  most_recent = true
  owners = ["amazon"]
  filter {
    name = "name" 
    values = ["al2023-ami-2023.*-x86_64"]
  }
  filter {
    name = "virtualization-type"
    values = ["hvm"]
  }
}

output "aws-ami_id" {
  value = data.aws_ami.latest-amazon-linux-image.id
}

output "ec2_public_ips" {
  value = {
    for name, server in aws_instance.myapp-server :
    name => server.public_ip
  }
}



resource "aws_key_pair" "ssh-key" {
  key_name = "server-key"
  public_key = file(var.public_key_location)
}

resource "aws_instance" "myapp-server" {
  for_each = var.servers

  ami           = data.aws_ami.latest-amazon-linux-image.id
  instance_type = each.value.instance_type

  subnet_id              = aws_subnet.myapp-subnet-1.id
  vpc_security_group_ids = [aws_default_security_group.default-sg.id]
  availability_zone      = var.avail_zone

  associate_public_ip_address = true
  key_name                    = aws_key_pair.ssh-key.key_name

  tags = {
    Name        = "${var.env_prefix}-${each.key}"
    Environment = each.value.env
  }
}
  
# Previous implementation
#
# Initially, Ansible was triggered directly after EC2 provisioning using
# Terraform's local-exec provisioner. The newly created EC2 public IP was
# passed directly to Ansible as an inline inventory.
#
# This approach was later replaced as the project evolved toward a more
# decoupled workflow using AWS dynamic inventory and Jenkins orchestration.
#
# The original implementation is retained below to document the evolution
# of the automation.

# provisioner "local-exec" {
#   working_dir = path.module
#   command = "ansible-playbook --inventory ${self.public_ip}, --private-key ${var.ssh_key_private} --user ec2-user deploy-docker-new-user.yaml"
# }


# Intermediate implementation
#
# To reduce coupling between EC2 resource creation and configuration,
# the Ansible execution was later separated into a null_resource.
#
# This kept infrastructure provisioning and post-provisioning configuration
# as separate concerns.
#
# The workflow later evolved further toward Jenkins orchestration and
# AWS dynamic inventory.

# resource "null_resource" "configure_servers" {
#   depends_on = [
#     aws_instance.myapp-server
#   ]
#
#   provisioner "local-exec" {
#     command = "ansible-playbook ..."
#   }
# }