# Creating the vpc
resource "aws_vpc" "kcvpc" {
    cidr_block = "10.0.0.0/16"
    enable_dns_support = true
    enable_dns_hostnames = true

    tags = {
      Name = "yt_Vpc"
    }
}

# creating the subnet

# public subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.kcvpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-2a" 
  map_public_ip_on_launch = true

  tags = {
    Name = "PublicSubnet"
  }
}

# private subnet
resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.kcvpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-2a"  

  tags = {
    Name = "PrivateSubnet"
  }
}

# initializing Internet Gateway
resource "aws_internet_gateway" "kcvpc_igw" {
  vpc_id = aws_vpc.kcvpc.id

  tags = {
    Name = "KCVPC-IGW"
  }
}

# Creating a Public Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.kcvpc.id

  tags = {
    Name = "PublicRouteTable"
  }
}

# Adding the route to Internet Gateway (0.0.0.0/0 -> IGW)
resource "aws_route" "public_rt_igw_route" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.kcvpc_igw.id
}

# Associated Public Subnet with the Public Route Table
resource "aws_route_table_association" "public_rt_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# Creating Private Route Table
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.kcvpc.id

  tags = {
    Name = "PrivateRouteTable"
  }
}

# Associating PrivateSubnet with the Private Route Table
resource "aws_route_table_association" "private_rt_assoc" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

# Allocating Elastic IP for NAT Gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name = "NatEIP"
  }
}

# Creating NAT Gateway in the Public Subnet
resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id

  tags = {
    Name = "NatGateway"
  }

  depends_on = [aws_internet_gateway.kcvpc_igw]  # Ensure IGW is created before NAT GW
}

# Adding route to NAT Gateway in Private Route Table
resource "aws_route" "private_route_to_nat" {
  route_table_id         = aws_route_table.private_rt.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gw.id
}

resource "aws_security_group" "web_sg" {
  name        = "WebServerSG"
  description = "Allow HTTP, HTTPS, and SSH"
  vpc_id      = aws_vpc.kcvpc.id

  # Inbound Rules
  ingress {
    description      = "Allow HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  ingress {
    description      = "Allow HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  ingress {
    description      = "Allow SSH from specific IP"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["1.2.3.4/32"]  # Replace with your actual IP
  }

  # Outbound Rule (Allow All)
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "WebServerSG"
  }
}

resource "aws_security_group" "db_sg" {
  name        = "DBServerSG"
  description = "Allow PostgreSQL traffic from public subnet"
  vpc_id      = aws_vpc.kcvpc.id

  # Inbound Rule (Allow PostgreSQL from Public Subnet)
  ingress {
    description      = "Allow PostgreSQL from Public Subnet"
    from_port        = 5432
    to_port          = 5432
    protocol         = "tcp"
    cidr_blocks      = [aws_subnet.public_subnet.cidr_block]
  }

  # Outbound Rule (Allow All)
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "DBServerSG"
  }
}

# public nacl
resource "aws_network_acl" "public_nacl" {
  vpc_id = aws_vpc.kcvpc.id
  subnet_ids = [aws_subnet.public_subnet.id]

  # Inbound Rules
  ingress {
    rule_no         = 100
    protocol        = "tcp"
    from_port       = 80
    to_port         = 80
    cidr_block      = "0.0.0.0/0"
    action          = "allow"
  }

  ingress {
    rule_no         = 110
    protocol        = "tcp"
    from_port       = 443
    to_port         = 443
    cidr_block      = "0.0.0.0/0"
    action          = "allow"
  }

  ingress {
    rule_no         = 120
    protocol        = "tcp"
    from_port       = 22
    to_port         = 22
    cidr_block      = "1.2.3.4/32"  # Replace with your actual IP
    action          = "allow"
  }

  # Allow ephemeral ports for return traffic
  ingress {
    rule_no         = 130
    protocol        = "tcp"
    from_port       = 1024
    to_port         = 65535
    cidr_block      = "0.0.0.0/0"
    action          = "allow"
  }

  # Outbound Rules
  egress {
    rule_no         = 100
    protocol        = "all"
    from_port       = 0
    to_port         = 0
    cidr_block      = "0.0.0.0/0"
    action          = "allow"
  }

  tags = {
    Name = "PublicNACL"
  }
}

# private nacl
resource "aws_network_acl" "private_nacl" {
  vpc_id = aws_vpc.kcvpc.id
  subnet_ids = [aws_subnet.private_subnet.id]

  # Allow all traffic from public subnet
  ingress {
    rule_no         = 100
    protocol        = "all"
    from_port       = 0
    to_port         = 0
    cidr_block      = aws_subnet.public_subnet.cidr_block
    action          = "allow"
  }

  # Allow ephemeral ports for return traffic
  ingress {
    rule_no         = 110
    protocol        = "tcp"
    from_port       = 1024
    to_port         = 65535
    cidr_block      = "0.0.0.0/0"
    action          = "allow"
  }

  # Outbound Rules - Allow all traffic
  egress {
    rule_no         = 100
    protocol        = "all"
    from_port       = 0
    to_port         = 0
    cidr_block      = "0.0.0.0/0"
    action          = "allow"
  }

  tags = {
    Name = "PrivateNACL"
  }
}

resource "aws_instance" "public_instance" {
  ami                    = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  key_name               = "my-keypair"  # <-- Replace this with your actual key pair name

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install nginx -y
              systemctl start nginx
              systemctl enable nginx
              EOF

  tags = {
    Name = "PublicEC2"
  }
}

resource "aws_instance" "private_instance" {
  ami                    = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private_subnet.id
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  key_name               = "my-keypair"  # <-- Replace this with your actual key pair name

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install postgresql postgresql-contrib -y
              systemctl start postgresql
              systemctl enable postgresql
              EOF

  tags = {
    Name = "PrivateEC2"
  }
}
