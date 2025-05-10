terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1" # Singapore region
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "main-vpc"
  }
}

# Web Subnet 1A (Public)
resource "aws_subnet" "web_1a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "ap-southeast-1a" # Singapore AZ
  tags = {
    Name = "web-subnet-1a"
  }
}

# Web Subnet 1B (Public)
resource "aws_subnet" "web_1b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "ap-southeast-1b" # Singapore AZ
  tags = {
    Name = "web-subnet-1b"
  }
}

# App Subnet 1A (Private)
resource "aws_subnet" "app_1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "ap-southeast-1a" # Singapore AZ
  tags = {
    Name = "app-subnet-1a"
  }
}

# App Subnet 1B (Private)
resource "aws_subnet" "app_1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "ap-southeast-1b" # Singapore AZ
  tags = {
    Name = "app-subnet-1b"
  }
}

# Database Subnet 1A (Private)
resource "aws_subnet" "database_1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.5.0/24"
  availability_zone = "ap-southeast-1a" # Singapore AZ
  tags = {
    Name = "database-subnet-1a"
  }
}

# Database Subnet 1B (Private)
resource "aws_subnet" "database_1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.6.0/24"
  availability_zone = "ap-southeast-1b" # Singapore AZ
  tags = {
    Name = "database-subnet-1b"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "main-igw"
  }
}

# Route Table for Web Subnet (Public)
resource "aws_route_table" "web" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "public-route-table"
  }
}

# Update Route Table Association for Web Subnet 1A
resource "aws_route_table_association" "web_1a" {
  subnet_id      = aws_subnet.web_1a.id
  route_table_id = aws_route_table.web.id
}

# Update Route Table Association for Web Subnet 1B
resource "aws_route_table_association" "web_1b" {
  subnet_id      = aws_subnet.web_1b.id
  route_table_id = aws_route_table.web.id
}

# Security Groups
resource "aws_security_group" "alb_sg" {
  vpc_id = aws_vpc.main.id
  ingress {
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
    Name = "alb-sg"
  }
}

resource "aws_security_group" "rds_sg" {
  vpc_id = aws_vpc.main.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "rds-sg"
  }
}

# Application Load Balancer
resource "aws_lb" "alb" {
  name               = "main-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.web_1a.id, aws_subnet.web_1b.id] # Updated reference

  tags = {
    Name = "main-alb"
  }
}

resource "aws_lb_target_group" "tg" {
  name     = "main-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# RDS Instance
resource "aws_db_instance" "rds" {
  allocated_storage      = 20
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  db_name                = "mydb"
  username               = "admin"
  password               = "Jasura$$44" # Replace with a secure password
  parameter_group_name   = "default.mysql8.0"
  publicly_accessible    = false
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  skip_final_snapshot    = true
}

resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-subnet-group"
  subnet_ids = [aws_subnet.app_1a.id, aws_subnet.app_1b.id, aws_subnet.database_1a.id, aws_subnet.database_1b.id]
  tags = {
    Name = "rds-subnet-group"
  }
}

# Launch Template
resource "aws_launch_template" "web_template" {
  name          = "web-launch-template"
  image_id      = "ami-0e8ebb0ab254bb563" # Replace with a valid Amazon Linux 2 AMI ID
  instance_type = "t2.micro"

  user_data = base64encode(file("${path.module}/script.sh")) # Path to your user data script

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.alb_sg.id]
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "web-instance"
    }
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "web_asg" {
  launch_template {
    id      = aws_launch_template.web_template.id
    version = "$Latest"
  }

  vpc_zone_identifier = [aws_subnet.web_1a.id, aws_subnet.web_1b.id]
  min_size            = 2
  max_size            = 2
  desired_capacity    = 2

  target_group_arns = [aws_lb_target_group.tg.arn] # Attach to the target group
  health_check_type = "ELB"

  tag {
    key                 = "Name"
    value               = "web-instance"
    propagate_at_launch = true
  }
}
