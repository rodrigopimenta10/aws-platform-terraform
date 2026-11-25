# Permissions for the AWS Load Balancer Controller, written out from the upstream project's reference policy
# (kubernetes-sigs/aws-load-balancer-controller, docs/install/iam_policy.json). The controller turns
# Kubernetes Ingress and Service objects into Application and Network Load Balancers, so it must create and
# delete load balancers, target groups, listeners, rules and security groups.
#
# Least privilege is done by tag, not by name. The controller tags everything it makes with
# elbv2.k8s.aws/cluster or ingress.k8s.aws/cluster, and the mutating statements only match resources that carry
# the tag, so it can change what it created and nothing else in the account. Describe calls have no
# resource-level permissions in IAM, which is the one reason "Resource": "*" appears below.

locals {
  lb_tag_cluster_present = { Null = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false" } }
  lb_tag_cluster_absent  = { Null = { "aws:RequestTag/elbv2.k8s.aws/cluster" = "false" } }

  lb_controller_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CreateServiceLinkedRole"
        Effect   = "Allow"
        Action   = ["iam:CreateServiceLinkedRole"]
        Resource = "*"
        Condition = {
          StringEquals = { "iam:AWSServiceName" = "elasticloadbalancing.amazonaws.com" }
        }
      },
      {
        Sid    = "Describe"
        Effect = "Allow"
        Action = [
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeAddresses",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeVpcs",
          "ec2:DescribeVpcPeeringConnections",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeTags",
          "ec2:GetCoipPoolUsage",
          "ec2:DescribeCoipPools",
          "ec2:GetSecurityGroupsForVpc",
          "ec2:DescribeIpamPools",
          "ec2:DescribeRouteTables",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeListenerCertificates",
          "elasticloadbalancing:DescribeSSLPolicies",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeTags",
          "elasticloadbalancing:DescribeTrustStores",
          "elasticloadbalancing:DescribeListenerAttributes",
          "elasticloadbalancing:DescribeCapacityReservation",
        ]
        Resource = "*"
      },
      {
        Sid    = "ReadCertificatesAndEdgeServices"
        Effect = "Allow"
        Action = [
          "cognito-idp:DescribeUserPoolClient",
          "acm:ListCertificates",
          "acm:DescribeCertificate",
          "iam:ListServerCertificates",
          "iam:GetServerCertificate",
          "waf-regional:GetWebACL",
          "waf-regional:GetWebACLForResource",
          "waf-regional:AssociateWebACL",
          "waf-regional:DisassociateWebACL",
          "wafv2:GetWebACL",
          "wafv2:GetWebACLForResource",
          "wafv2:AssociateWebACL",
          "wafv2:DisassociateWebACL",
          "shield:GetSubscriptionState",
          "shield:DescribeProtection",
          "shield:CreateProtection",
          "shield:DeleteProtection",
        ]
        Resource = "*"
      },
      {
        Sid      = "EditSecurityGroupRules"
        Effect   = "Allow"
        Action   = ["ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress"]
        Resource = "*"
      },
      {
        Sid      = "CreateSecurityGroup"
        Effect   = "Allow"
        Action   = ["ec2:CreateSecurityGroup"]
        Resource = "*"
      },
      {
        Sid      = "TagSecurityGroupOnCreate"
        Effect   = "Allow"
        Action   = ["ec2:CreateTags"]
        Resource = "arn:${local.partition}:ec2:*:*:security-group/*"
        Condition = {
          StringEquals = { "ec2:CreateAction" = "CreateSecurityGroup" }
          Null         = { "aws:RequestTag/elbv2.k8s.aws/cluster" = "false" }
        }
      },
      {
        Sid      = "TagOwnSecurityGroups"
        Effect   = "Allow"
        Action   = ["ec2:CreateTags", "ec2:DeleteTags"]
        Resource = "arn:${local.partition}:ec2:*:*:security-group/*"
        Condition = {
          Null = {
            "aws:RequestTag/elbv2.k8s.aws/cluster"  = "true"
            "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Sid       = "ChangeOwnSecurityGroups"
        Effect    = "Allow"
        Action    = ["ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress", "ec2:DeleteSecurityGroup"]
        Resource  = "*"
        Condition = local.lb_tag_cluster_present
      },
      {
        Sid       = "CreateLoadBalancersAndTargetGroups"
        Effect    = "Allow"
        Action    = ["elasticloadbalancing:CreateLoadBalancer", "elasticloadbalancing:CreateTargetGroup"]
        Resource  = "*"
        Condition = local.lb_tag_cluster_absent
      },
      {
        Sid    = "ManageListenersAndRules"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:CreateRule",
          "elasticloadbalancing:DeleteRule",
        ]
        Resource = "*"
      },
      {
        Sid    = "TagOwnLoadBalancerResources"
        Effect = "Allow"
        Action = ["elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags"]
        Resource = [
          "arn:${local.partition}:elasticloadbalancing:*:*:targetgroup/*/*",
          "arn:${local.partition}:elasticloadbalancing:*:*:loadbalancer/net/*/*",
          "arn:${local.partition}:elasticloadbalancing:*:*:loadbalancer/app/*/*",
        ]
        Condition = {
          Null = {
            "aws:RequestTag/elbv2.k8s.aws/cluster"  = "true"
            "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Sid    = "TagListenersAndRules"
        Effect = "Allow"
        Action = ["elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags"]
        Resource = [
          "arn:${local.partition}:elasticloadbalancing:*:*:listener/net/*/*/*",
          "arn:${local.partition}:elasticloadbalancing:*:*:listener/app/*/*/*",
          "arn:${local.partition}:elasticloadbalancing:*:*:listener-rule/net/*/*/*",
          "arn:${local.partition}:elasticloadbalancing:*:*:listener-rule/app/*/*/*",
        ]
      },
      {
        Sid    = "TagOnCreate"
        Effect = "Allow"
        Action = ["elasticloadbalancing:AddTags"]
        Resource = [
          "arn:${local.partition}:elasticloadbalancing:*:*:targetgroup/*/*",
          "arn:${local.partition}:elasticloadbalancing:*:*:loadbalancer/net/*/*",
          "arn:${local.partition}:elasticloadbalancing:*:*:loadbalancer/app/*/*",
        ]
        Condition = {
          StringEquals = { "elasticloadbalancing:CreateAction" = ["CreateTargetGroup", "CreateLoadBalancer"] }
          Null         = { "aws:RequestTag/elbv2.k8s.aws/cluster" = "false" }
        }
      },
      {
        Sid    = "ChangeOwnLoadBalancers"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:SetIpAddressType",
          "elasticloadbalancing:SetSecurityGroups",
          "elasticloadbalancing:SetSubnets",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:ModifyListenerAttributes",
          "elasticloadbalancing:ModifyCapacityReservation",
        ]
        Resource  = "*"
        Condition = local.lb_tag_cluster_present
      },
      {
        Sid      = "RegisterTargets"
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:RegisterTargets", "elasticloadbalancing:DeregisterTargets"]
        Resource = "arn:${local.partition}:elasticloadbalancing:*:*:targetgroup/*/*"
      },
      {
        Sid    = "ChangeListeners"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:SetWebAcl",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:AddListenerCertificates",
          "elasticloadbalancing:RemoveListenerCertificates",
          "elasticloadbalancing:ModifyRule",
          "elasticloadbalancing:SetRulePriorities",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_policy" "lb_controller" {
  #checkov:skip=CKV_AWS_290:Describe, listener and rule calls have no resource-level permissions in IAM; every mutating statement is limited by the controller's cluster tag where IAM supports it.
  #checkov:skip=CKV_AWS_355:Same reason: the reference policy for the controller needs "*" for Describe and for resources that do not exist yet at create time.
  #checkov:skip=CKV_AWS_289:The controller creates and deletes security groups and load balancers, which is permissions management by design; it is scoped by tag.
  #checkov:skip=CKV2_AWS_40:Not an admin policy; the "*" appears only on service-scoped actions.
  count = var.create_lb_controller_policy ? 1 : 0

  name        = module.labels.names["lb-controller"]
  description = "AWS Load Balancer Controller on ${var.cluster_name}: manages ALBs, NLBs, target groups and their security groups"
  policy      = local.lb_controller_policy

  tags = merge(module.labels.tags, var.tags, { Name = module.labels.names["lb-controller"] })
}
