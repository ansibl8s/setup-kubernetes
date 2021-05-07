resource "aws_vpc" "cluster-vpc" {
  cidr_block = var.aws_vpc_cidr_block

  #DNS Related Entries
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.default_tags, tomap({
    Name = "kubernetes-${var.aws_cluster_name}-vpc"
  }))
}

resource "aws_eip" "cluster-nat-eip" {
  count = length(var.aws_cidr_subnets_public)
  vpc   = true
}

resource "aws_internet_gateway" "cluster-vpc-internetgw" {
  vpc_id = aws_vpc.cluster-vpc.id

  tags = merge(var.default_tags, tomap({
    Name = "kubernetes-${var.aws_cluster_name}-internetgw"
  }))
}

resource "aws_subnet" "cluster-vpc-subnets-public" {
  vpc_id            = aws_vpc.cluster-vpc.id
  count             = length(var.aws_avail_zones)
  availability_zone = element(var.aws_avail_zones, count.index)
  cidr_block        = element(var.aws_cidr_subnets_public, count.index)

  tags = merge(var.default_tags, tomap({
    Name = "kubernetes-${var.aws_cluster_name}-${element(var.aws_avail_zones, count.index)}-public"
    "kubernetes.io/cluster/${var.aws_cluster_name}" = "member"
  }))
}

resource "aws_nat_gateway" "cluster-nat-gateway" {
  count         = length(var.aws_cidr_subnets_public)
  allocation_id = element(aws_eip.cluster-nat-eip.*.id, count.index)
  subnet_id     = element(aws_subnet.cluster-vpc-subnets-public.*.id, count.index)
}

resource "aws_subnet" "cluster-vpc-subnets-private" {
  vpc_id            = aws_vpc.cluster-vpc.id
  count             = length(var.aws_avail_zones)
  availability_zone = element(var.aws_avail_zones, count.index)
  cidr_block        = element(var.aws_cidr_subnets_private, count.index)

  tags = merge(var.default_tags, tomap({
    Name = "kubernetes-${var.aws_cluster_name}-${element(var.aws_avail_zones, count.index)}-private"
  }))
}

#Routing in VPC

#TODO: Do we need two routing tables for each subnet for redundancy or is one enough?

resource "aws_route_table" "kubernetes-public" {
  vpc_id = aws_vpc.cluster-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.cluster-vpc-internetgw.id
  }

  tags = merge(var.default_tags, tomap({
    Name = "kubernetes-${var.aws_cluster_name}-routetable-public"
  }))
}

resource "aws_route_table" "kubernetes-private" {
  count  = length(var.aws_cidr_subnets_private)
  vpc_id = aws_vpc.cluster-vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = element(aws_nat_gateway.cluster-nat-gateway.*.id, count.index)
  }

  tags = merge(var.default_tags, tomap({
    Name = "kubernetes-${var.aws_cluster_name}-routetable-private-${count.index}"
  }))
}

resource "aws_route_table_association" "kubernetes-public" {
  count          = length(var.aws_cidr_subnets_public)
  subnet_id      = element(aws_subnet.cluster-vpc-subnets-public.*.id, count.index)
  route_table_id = aws_route_table.kubernetes-public.id
}

resource "aws_route_table_association" "kubernetes-private" {
  count          = length(var.aws_cidr_subnets_private)
  subnet_id      = element(aws_subnet.cluster-vpc-subnets-private.*.id, count.index)
  route_table_id = element(aws_route_table.kubernetes-private.*.id, count.index)
}

#Kubernetes Security Groups

resource "aws_security_group" "kubernetes" {
  name   = "kubernetes-${var.aws_cluster_name}-securitygroup"
  vpc_id = aws_vpc.cluster-vpc.id

  tags = merge(var.default_tags, tomap({
    Name = "kubernetes-${var.aws_cluster_name}-securitygroup"
  }))
}

resource "aws_security_group_rule" "allow-all-ingress" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  cidr_blocks       = [var.aws_vpc_cidr_block]
  security_group_id = aws_security_group.kubernetes.id
}

resource "aws_security_group_rule" "allow-all-egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.kubernetes.id
}

resource "aws_security_group_rule" "allow-ssh-connections" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "TCP"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.kubernetes.id
}
