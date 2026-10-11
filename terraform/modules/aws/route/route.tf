locals {
  routes = { for item in concat(flatten([ for cidr in var.private_cidrs: 
      [ for subnet in var.private_subnets: 
          {
            subnet_id = subnet.id
            rt_id     = subnet.rt_id
            cidr      = cidr
            ngw_id    = element(var.ngw, index([for subnet in var.private_subnets: subnet], subnet))
          } 
      ]
    ]),
    flatten([ for cidr in var.public_cidrs: 
      [ for subnet in var.public_subnets: 
          {
            subnet_id = subnet.id
            rt_id     = subnet.rt_id
            cidr      = cidr
            igw_id    = var.igw
          } 
      ]
    ])) : "${item.subnet_id}-${item.rt_id}" => item
  }
}

resource "aws_route" "r" {
  for_each = local.routes

  route_table_id            = each.value.rt_id
  destination_cidr_block    = each.value.cidr
  gateway_id                = lookup(each.value, "igw_id", null)  
  nat_gateway_id            = lookup(each.value, "ngw_id", null)
}

