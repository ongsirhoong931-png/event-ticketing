# 1. Custom VPC
resource "aws_vpc" "tarumt_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "TARUMT-Ticketing-VPC" }
}

# 2. Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.tarumt_vpc.id
  tags   = { Name = "TARUMT-IGW" }
}

# 3. Subnets (Multi-AZ)
resource "aws_subnet" "public_1a" {
  vpc_id                  = aws_vpc.tarumt_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags                    = { Name = "Public-Subnet-1a" }
}

resource "aws_subnet" "public_1b" {
  vpc_id                  = aws_vpc.tarumt_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags                    = { Name = "Public-Subnet-1b" }
}

resource "aws_subnet" "private_app_1a" {
  vpc_id            = aws_vpc.tarumt_vpc.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = "us-east-1a"
  tags              = { Name = "Private-App-1a" }
}

resource "aws_subnet" "private_app_1b" {
  vpc_id            = aws_vpc.tarumt_vpc.id
  cidr_block        = "10.0.20.0/24"
  availability_zone = "us-east-1b"
  tags              = { Name = "Private-App-1b" }
}

resource "aws_subnet" "private_db_1a" {
  vpc_id            = aws_vpc.tarumt_vpc.id
  cidr_block        = "10.0.30.0/24"
  availability_zone = "us-east-1a"
  tags              = { Name = "Private-DB-1a" }
}

resource "aws_subnet" "private_db_1b" {
  vpc_id            = aws_vpc.tarumt_vpc.id
  cidr_block        = "10.0.40.0/24"
  availability_zone = "us-east-1b"
  tags              = { Name = "Private-DB-1b" }
}

# 4. Public Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.tarumt_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "TARUMT-Public-RT" }
}

resource "aws_route_table_association" "pub_a" {
  subnet_id      = aws_subnet.public_1a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "pub_b" {
  subnet_id      = aws_subnet.public_1b.id
  route_table_id = aws_route_table.public_rt.id
}

# 5. Security Groups
resource "aws_security_group" "alb_sg" {
  name        = "tarumt-alb-sg"
  description = "Public inbound HTTP only"
  vpc_id      = aws_vpc.tarumt_vpc.id

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
}

resource "aws_security_group" "ec2_app_sg" {
  name        = "tarumt-ec2-app-sg"
  description = "Inbound HTTP only from ALB"
  vpc_id      = aws_vpc.tarumt_vpc.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "tarumt-rds-sg"
  description = "Inbound MySQL only from EC2 SG"
  vpc_id      = aws_vpc.tarumt_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_app_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 6. S3 Bucket for Media Uploads
resource "aws_s3_bucket" "assets" {
  bucket_prefix = "tarumt-event-ticketing-"
  force_destroy = true
}

# 7. RDS MySQL Instance
resource "aws_db_subnet_group" "rds_subnets" {
  name       = "tarumt-rds-subnets"
  subnet_ids = [aws_subnet.private_db_1a.id, aws_subnet.private_db_1b.id]
}

resource "aws_db_instance" "mysql" {
  allocated_storage      = 20
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  db_name                = "event_ticketing"
  username               = "admin"
  password               = "TARUMTSecure2026!"
  db_subnet_group_name   = aws_db_subnet_group.rds_subnets.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
}

# 8. AWS Secrets Manager
resource "aws_secretsmanager_secret" "db_secret" {
  name                    = "prod/tarumt/db_credentials"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db_secret_val" {
  secret_id     = aws_secretsmanager_secret.db_secret.id
  secret_string = jsonencode({
    host     = aws_db_instance.mysql.address
    port     = 3306
    username = "admin"
    password = "TARUMTSecure2026!"
    dbname   = "event_ticketing"
  })
}

# 9. Application Load Balancer
resource "aws_lb" "tarumt_alb" {
  name               = "tarumt-ticketing-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_1a.id, aws_subnet.public_1b.id]
}

resource "aws_lb_target_group" "tg" {
  name     = "tarumt-app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.tarumt_vpc.id

  health_check {
    path                = "/healthz.php"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 15
    matcher             = "200"
  }
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.tarumt_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# 10. Launch Template & Auto Scaling Group
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_launch_template" "app_lt" {
  name_prefix   = "tarumt-app-"
  image_id      = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.micro"

  iam_instance_profile {
    name = "LabInstanceProfile"
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.ec2_app_sg.id]
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y httpd php php-mysqlnd php-json php-mbstring php-xml git composer
              systemctl start httpd
              systemctl enable httpd
              cd /var/www/html
              git clone https://github.com/<YOUR_GITHUB_USERNAME>/<YOUR_REPO_NAME>.git .
              composer require aws/aws-sdk-php
              chown -R apache:apache /var/www/html
              chmod -R 755 /var/www/html
              EOF
  )
}

resource "aws_autoscaling_group" "asg" {
  name                = "tarumt-web-asg"
  vpc_zone_identifier = [aws_subnet.private_app_1a.id, aws_subnet.private_app_1b.id]
  target_group_arns   = [aws_lb_target_group.tg.arn]
  min_size            = 2
  desired_capacity    = 2
  max_size            = 4

  launch_template {
    id      = aws_launch_template.app_lt.id
    version = "$Latest"
  }
}

resource "aws_autoscaling_policy" "cpu_tracking" {
  name                   = "cpu-target-tracking-60"
  autoscaling_group_name = aws_autoscaling_group.asg.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60.0
  }
}