
terraform {
  required_version = "~> 1.5.2"
  backend "s3" {
    bucket  = "base-education-terraform-tfstate"
    key     = "yoshida.tfstate"
    region  = "ap-northeast-1"
    profile = "base-education-terraform"
  }
}

provider "aws" {
  region  = "ap-northeast-1"
  profile = "base-education-terraform"
}

variable "my_name" {
  type    = string
  default = "yoshida"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "${var.my_name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.my_name}-igw"
  }
}

resource "aws_subnet" "public_subnet" {
  cidr_block        = "10.0.1.0/24"
  vpc_id            = aws_vpc.main.id
  availability_zone = "ap-northeast-1a"

  tags = {
    Name = "${var.my_name}-public-subnet"
  }
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.my_name}-route-table-for-public-subnet"
  }
}

resource "aws_route" "public" {
  route_table_id         = aws_route_table.public.id
  gateway_id             = aws_internet_gateway.main.id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_route_table_association" "public" {
  route_table_id = aws_route_table.public.id
  subnet_id      = aws_subnet.public_subnet.id
}

resource "aws_instance" "webserver" {
  ami           = "ami-0d3bbfd074edd7acb" // Amazon Linux 2
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public_subnet.id

  user_data = <<EOT
#!/bin/bash
cd /tmp
sudo yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
sudo systemctl enable amazon-ssm-agent
sudo systemctl start amazon-ssm-agent

yum -y update
yum -y install httpd

systemctl enable httpd.service
systemctl start httpd.service
EOT

  // Instance Profile を設定
  iam_instance_profile = aws_iam_instance_profile.webserver.id

  // 追加
  vpc_security_group_ids = [
    aws_security_group.allow_http.id
  ]

  tags = {
    Name = "${var.my_name}-webserver"
  }
}

// 追加
resource "aws_security_group" "allow_http" {
  name   = "${var.my_name}-security-group"
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
}

resource "aws_eip" "eip" {
  instance = aws_instance.webserver.id
  domain   = "vpc"

  tags = {
    Name = "${var.my_name}-eip"
  }
}

# Instance Profile として割り当てるロール
resource "aws_iam_role" "webserver" {
  assume_role_policy = <<EOT
{
   "Version":"2012-10-17",
   "Statement":[
      {
         "Effect":"Allow",
         "Principal":{
            "Service":"ec2.amazonaws.com"
         },
         "Action":"sts:AssumeRole"
      }
   ]
}
EOT


  tags = {
    Name = "${var.my_name}-webserver-role"
  }
}

# Session Manager を使用するために必要な権限
data "aws_iam_policy" "systems_manager" {
  arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ポリシーをロールに割り当てる設定
resource "aws_iam_role_policy_attachment" "webserver" {
  policy_arn = data.aws_iam_policy.systems_manager.arn
  role       = aws_iam_role.webserver.id
}

# インスタンスプロファイル
resource "aws_iam_instance_profile" "webserver" {
  role = aws_iam_role.webserver.id
}
