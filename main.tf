resource "aws_vpc" "vpc1" {
  cidr_block       = "172.31.0.0/16"
  instance_tenancy = "default"
  tags = {
    Name = "Terraform-vpc"
    env  = "dev"
    Team = "DevOps"
  }
}
resource "aws_internet_gateway" "gwy1" {
  vpc_id = aws_vpc.vpc1.id
}
# public subnet
resource "aws_subnet" "public1" {
  availability_zone       = "ca-central-1a"
  cidr_block              = "172.31.0.0/24"
  map_public_ip_on_launch = true
  vpc_id                  = aws_vpc.vpc1.id
  tags = {
     Name = "public-subnet-1"
     env  = "dev"
  }

}
resource "aws_subnet" "public2" {
  availability_zone       = "ca-central-1b"
  cidr_block              = "172.31.2.0/24"
  vpc_id                  = aws_vpc.vpc1.id
  map_public_ip_on_launch = true
  
  tags = {
    Name = "public-subnet-2"
    env  = "dev"
  }

}


#* ec2.tf

resource "aws_instance" "server1" {
  ami                    = "ami-0db8414c676722acd"
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.sg1.id]
  availability_zone      = "ca-central-1a"
  subnet_id              = aws_subnet.public1.id
  #user_data = file("code.sh")
  tags = {
    Name = "webserver-1"
  }

}
resource "aws_instance" "server2" {
  ami                    = "ami-0db8414c676722acd"
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.sg2.id]
  availability_zone      = "ca-central-1b"
  subnet_id              = aws_subnet.public2.id
  #user_data = file("code.sh")
  tags = {
    Name = "webserver-2"
  }
}

#Elastic ip and Nat gateway
resource "aws_eip" "eip" {

}
resource "aws_nat_gateway" "nat1" {
  allocation_id = aws_eip.eip.id
  subnet_id     = aws_subnet.public1.id
}
#Public route table

resource "aws_route_table" "rtpublic" {
  vpc_id = aws_vpc.vpc1.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gwy1.id
  }
}

resource "aws_route_table_association" "rta3" {
  subnet_id      = aws_subnet.public1.id
  route_table_id = aws_route_table.rtpublic.id
}
resource "aws_route_table_association" "rta4" {
  subnet_id      = aws_subnet.public2.id
  route_table_id = aws_route_table.rtpublic.id
}


resource "aws_security_group" "sg1" {
  name        = "Terraform-sg"
  description = "Allow ssh and httpd"
  vpc_id      = aws_vpc.vpc1.id


  ingress {
    description = "allow http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    #security_groups = [ aws_security_group.sg2.name ]
  }

  ingress {
    description = "allow ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "allow RDS"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # tags= {
  #   env = "Dev"
  #   created-by-terraform = "yes"
  # }

}

resource "aws_security_group" "sg2" {
  name        = "Terraform-sg-lb"
  description = "Allow ssh and httpd"
  vpc_id      = aws_vpc.vpc1.id

  ingress {
    description = "allow http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "allow ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

  }

  ingress {
    description = "allow RDS"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # tags= {
  #   env = "Dev"
  # } 
}

#* alb.tf

resource "aws_launch_configuration" "aconf" {
  name          = "webcon"
  image_id      = "ami-0db8414c676722acd"
  instance_type = "t2.micro"
}

resource "aws_autoscaling_group" "barn" {
  name                 = "terrafor"
  launch_configuration = aws_launch_configuration.aconf.name
  availability_zones    = ["ca-central-1a", "ca-central-1b"]
  min_size             = 2
  max_size             = 4

  lifecycle {
    create_before_destroy = true
  }
}
resource "aws_lb_target_group" "alb-target-group" {
  name     = "application-lb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc1.id

  health_check {
    enabled             = true
    healthy_threshold   = 3
    interval            = 10
    matcher             = 200
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 6
    unhealthy_threshold = 3
  }
}
resource "aws_lb_target_group_attachment" "attach" {
  target_group_arn = aws_lb_target_group.alb-target-group.arn
  target_id        = aws_instance.server1.id
  port             = 80
}
resource "aws_lb_target_group_attachment" "attach-app" {
  target_group_arn = aws_lb_target_group.alb-target-group.arn
  target_id        = aws_instance.server2.id
  port             = 80
}
resource "aws_lb_listener" "alb-http-listener" {
  load_balancer_arn = aws_lb.application-lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb-target-group.arn
  }
}
resource "aws_lb" "application-lb" {
  name               = "application-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.sg2.id]
  subnets            = [aws_subnet.public1.id, aws_subnet.public2.id]

  enable_deletion_protection = false

  tags = {
    Environment = "application-lb"
    Name        = "Application-lb"

  }
}


resource "aws_iam_role" "s3fullaccessrole" {
  name = "s3fullaccrole"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [{
      "Effect" : "Allow",
      "Principal" : {
        "Service" : "s3.amazonaws.com"
      },
      "Action" : "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "s3_full_access_policy" {
  name        = "s3fullaccpolicy"
  description = "Provides full access to S3 bucket"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [{
      "Effect" : "Allow",
      "Action" : ["s3:*"],
      "Resource" : "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "s3_full_access_attachment" {
  policy_arn = aws_iam_policy.s3_full_access_policy.arn
  role       = aws_iam_role.s3fullaccessrole.name
}

resource "aws_db_subnet_group" "dbgrp" {
  name       = "grpname"
  subnet_ids = [aws_subnet.public1.id, aws_subnet.public2.id]
}

resource "aws_db_instance" "defo" {
  allocated_storage    = 10
  db_name              = "grpnames"
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t3.micro"
  username             = "admin"
  password             = "admin1234"
  #parameter_group_name = aws_db_parameter_group.defo.name
  skip_final_snapshot  = true
  db_subnet_group_name = aws_db_subnet_group.dbgrp.name
}