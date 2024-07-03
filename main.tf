terraform {
  required_providers {
    aws = {
        source = "hashicorp/aws",
        version = "~> 5.5"
    }
    tls = {
      source = "hashicorp/tls"
      version = "4.0.4"
    }
    ansible = {
      source = "ansible/ansible"
      version = "1.3.0"
    }
  }
}

provider "aws" {
    region = "us-east-1"
}

resource "aws_vpc" "test_vpc" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "test_subnet" {
    vpc_id = aws_vpc.test_vpc.id
    cidr_block = "10.0.0.0/16"
}

resource "aws_internet_gateway" "test_igw" {
  vpc_id = aws_vpc.test_vpc.id

  tags = { 
    Name = "Upwork cient Internet GW"
  }

}

resource "aws_route_table" "test_routetable" {
  vpc_id = aws_vpc.test_vpc.id

  route { 
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.test_igw.id
  }

  tags = {
    Name = "Upwork client IGW route table"
  }

}

resource "aws_route_table_association" "test_route_association" {
  subnet_id = aws_subnet.test_subnet.id
  route_table_id = aws_route_table.test_routetable.id
}

resource "aws_security_group" "test_security_group" {
    name_prefix = "test_security_group"
    vpc_id      = aws_vpc.test_vpc.id

    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["45.164.0.0/16"]
    }
   
    ingress {
        from_port = 5900
        to_port = 5902
        protocol = "tcp"
        cidr_blocks = ["45.164.0.0/16"]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "tls_private_key" "test_private_key" {
  
  algorithm = "RSA"
  rsa_bits  = 4096

  provisioner "local-exec" {
    command = "echo '${self.public_key_pem}' > ./pubkey.pem"
  }
}

resource "aws_key_pair" "test_key_pair" {
  key_name = var.keypair_name
  public_key = tls_private_key.test_private_key.public_key_openssh

  provisioner "local-exec" {
    command = "echo '${tls_private_key.test_private_key.private_key_pem}' > ./private-key.pem"
  }
  
}

resource "aws_instance" "test_machine" {
  ami           = "ami-04b70fa74e45c3917"
  instance_type = "t2.medium"
  key_name = aws_key_pair.test_key_pair.key_name
  associate_public_ip_address = true
  subnet_id     = aws_subnet.test_subnet.id
  vpc_security_group_ids = [aws_security_group.test_security_group.id]
  root_block_device {
    volume_type = "gp2"
    volume_size = 14
  }

  tags = {
    Name = "test_machine"
  }

  provisioner "local-exec" {
    command = "echo 'master ${self.public_ip}' >> ./files/hosts"
  }
}

resource "ansible_host" "test_ansible_host" {
  depends_on = [
    aws_instance.test_machine
  ]
  name = "test_machine"
  groups = ["master"]
  variables = {
    ansible_user = "ubuntu"
    ansible_host = aws_instance.test_machine.public_ip
    ansible_ssh_private_key_file = "./private-key.pem"
    node_hostname = "master"
  }
}

output "test_machine_ip" {
  value = aws_instance.test_machine.public_ip
}
