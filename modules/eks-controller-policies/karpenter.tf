# Permissions for the Karpenter controller (v1 policy, from the project's reference CloudFormation template).
# Karpenter watches for pods that cannot be scheduled, then launches EC2 instances that fit them and joins
# them to the cluster. It is powerful (it creates and terminates instances), so every mutating statement
# is bound to this cluster in one of two ways:
#   - the resource must carry the tag kubernetes.io/cluster/<name> = owned, which Karpenter itself puts on what
#     it creates, so it cannot terminate a machine it did not start;
#   - or the request must set that tag, so everything new is born owned by this cluster.
# iam:PassRole is limited to one node role and to EC2, so Karpenter cannot hand a more powerful role to
# an instance it launches (the classic privilege escalation through a launch).

locals {
  karpenter_create = var.create_karpenter_policy

  owned_resource = {
    "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
  owned_request = {
    "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
    "aws:RequestTag/eks:eks-cluster-name"                      = var.cluster_name
  }
  ec2_arn = "arn:${local.partition}:ec2:${var.region}"

  karpenter_policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid    = "AllowScopedEC2InstanceAccessActions"
          Effect = "Allow"
          Action = ["ec2:RunInstances", "ec2:CreateFleet"]
          Resource = [
            "${local.ec2_arn}::image/*",
            "${local.ec2_arn}::snapshot/*",
            "${local.ec2_arn}:*:security-group/*",
            "${local.ec2_arn}:*:subnet/*",
            "${local.ec2_arn}:*:capacity-reservation/*",
          ]
        },
        {
          Sid      = "AllowScopedEC2LaunchTemplateAccessActions"
          Effect   = "Allow"
          Action   = ["ec2:RunInstances", "ec2:CreateFleet"]
          Resource = "${local.ec2_arn}:*:launch-template/*"
          Condition = {
            StringEquals = local.owned_resource
            StringLike   = { "aws:ResourceTag/karpenter.sh/nodepool" = "*" }
          }
        },
        {
          Sid    = "AllowScopedEC2InstanceActionsWithTags"
          Effect = "Allow"
          Action = ["ec2:RunInstances", "ec2:CreateFleet", "ec2:CreateLaunchTemplate"]
          Resource = [
            "${local.ec2_arn}:*:fleet/*",
            "${local.ec2_arn}:*:instance/*",
            "${local.ec2_arn}:*:volume/*",
            "${local.ec2_arn}:*:network-interface/*",
            "${local.ec2_arn}:*:launch-template/*",
            "${local.ec2_arn}:*:spot-instances-request/*",
          ]
          Condition = {
            StringEquals = local.owned_request
            StringLike   = { "aws:RequestTag/karpenter.sh/nodepool" = "*" }
          }
        },
        {
          Sid    = "AllowScopedResourceCreationTagging"
          Effect = "Allow"
          Action = ["ec2:CreateTags"]
          Resource = [
            "${local.ec2_arn}:*:fleet/*",
            "${local.ec2_arn}:*:instance/*",
            "${local.ec2_arn}:*:volume/*",
            "${local.ec2_arn}:*:network-interface/*",
            "${local.ec2_arn}:*:launch-template/*",
            "${local.ec2_arn}:*:spot-instances-request/*",
          ]
          Condition = {
            StringEquals = merge(local.owned_request, {
              "ec2:CreateAction" = ["RunInstances", "CreateFleet", "CreateLaunchTemplate"]
            })
            StringLike = { "aws:RequestTag/karpenter.sh/nodepool" = "*" }
          }
        },
        {
          Sid      = "AllowScopedResourceTagging"
          Effect   = "Allow"
          Action   = ["ec2:CreateTags"]
          Resource = "${local.ec2_arn}:*:instance/*"
          Condition = {
            StringEquals                = local.owned_resource
            StringLike                  = { "aws:ResourceTag/karpenter.sh/nodepool" = "*" }
            "ForAllValues:StringEquals" = { "aws:TagKeys" = ["eks:eks-cluster-name", "karpenter.sh/nodeclaim", "Name"] }
          }
        },
        {
          Sid    = "AllowScopedDeletion"
          Effect = "Allow"
          Action = ["ec2:TerminateInstances", "ec2:DeleteLaunchTemplate"]
          Resource = [
            "${local.ec2_arn}:*:instance/*",
            "${local.ec2_arn}:*:launch-template/*",
          ]
          Condition = {
            StringEquals = local.owned_resource
            StringLike   = { "aws:ResourceTag/karpenter.sh/nodepool" = "*" }
          }
        },
        {
          Sid    = "AllowRegionalReadActions"
          Effect = "Allow"
          Action = [
            "ec2:DescribeCapacityReservations",
            "ec2:DescribeImages",
            "ec2:DescribeInstances",
            "ec2:DescribeInstanceTypeOfferings",
            "ec2:DescribeInstanceTypes",
            "ec2:DescribeLaunchTemplates",
            "ec2:DescribeSecurityGroups",
            "ec2:DescribeSpotPriceHistory",
            "ec2:DescribeSubnets",
          ]
          Resource  = "*"
          Condition = { StringEquals = { "aws:RequestedRegion" = var.region } }
        },
        {
          Sid      = "AllowSSMReadActions"
          Effect   = "Allow"
          Action   = ["ssm:GetParameter"]
          Resource = "arn:${local.partition}:ssm:${var.region}::parameter/aws/service/*"
        },
        {
          Sid      = "AllowPricingReadActions"
          Effect   = "Allow"
          Action   = ["pricing:GetProducts"]
          Resource = "*"
        },
        {
          Sid      = "AllowAPIServerEndpointDiscovery"
          Effect   = "Allow"
          Action   = ["eks:DescribeCluster"]
          Resource = "arn:${local.partition}:eks:${var.region}:${local.account_id}:cluster/${var.cluster_name}"
        },
        {
          Sid      = "AllowScopedInstanceProfileCreationActions"
          Effect   = "Allow"
          Action   = ["iam:CreateInstanceProfile"]
          Resource = "arn:${local.partition}:iam::${local.account_id}:instance-profile/*"
          Condition = {
            StringEquals = merge(local.owned_request, { "aws:RequestTag/topology.kubernetes.io/region" = var.region })
            StringLike   = { "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass" = "*" }
          }
        },
        {
          Sid      = "AllowScopedInstanceProfileTagActions"
          Effect   = "Allow"
          Action   = ["iam:TagInstanceProfile"]
          Resource = "arn:${local.partition}:iam::${local.account_id}:instance-profile/*"
          Condition = {
            StringEquals = merge(local.owned_resource, local.owned_request, {
              "aws:ResourceTag/topology.kubernetes.io/region" = var.region
              "aws:RequestTag/topology.kubernetes.io/region"  = var.region
            })
            StringLike = {
              "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass" = "*"
              "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass"  = "*"
            }
          }
        },
        {
          Sid      = "AllowScopedInstanceProfileActions"
          Effect   = "Allow"
          Action   = ["iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile", "iam:DeleteInstanceProfile"]
          Resource = "arn:${local.partition}:iam::${local.account_id}:instance-profile/*"
          Condition = {
            StringEquals = merge(local.owned_resource, { "aws:ResourceTag/topology.kubernetes.io/region" = var.region })
            StringLike   = { "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass" = "*" }
          }
        },
        {
          Sid      = "AllowInstanceProfileReadActions"
          Effect   = "Allow"
          Action   = ["iam:GetInstanceProfile"]
          Resource = "arn:${local.partition}:iam::${local.account_id}:instance-profile/*"
        },
      ],
      var.karpenter_node_role_arn == null ? [] : [{
        Sid       = "AllowPassingInstanceRole"
        Effect    = "Allow"
        Action    = ["iam:PassRole"]
        Resource  = var.karpenter_node_role_arn
        Condition = { StringEquals = { "iam:PassedToService" = ["ec2.amazonaws.com"] } }
      }],
      var.karpenter_interruption_queue_arn == null ? [] : [{
        Sid      = "AllowInterruptionQueueActions"
        Effect   = "Allow"
        Action   = ["sqs:DeleteMessage", "sqs:GetQueueUrl", "sqs:ReceiveMessage"]
        Resource = var.karpenter_interruption_queue_arn
      }],
    )
  })
}

resource "aws_iam_policy" "karpenter" {
  #checkov:skip=CKV_AWS_290:EC2 Describe and pricing calls have no resource-level permissions; every mutating statement is limited by the cluster-owned tag.
  #checkov:skip=CKV_AWS_355:Same reason: "*" appears only on read-only Describe and pricing actions, which IAM cannot scope to a resource.
  #checkov:skip=CKV_AWS_289:Karpenter must manage instance profiles and launch instances; the actions are scoped to this cluster by tag and iam:PassRole to one role.
  #checkov:skip=CKV2_AWS_40:Not an admin policy; no action is "*".
  count = local.karpenter_create ? 1 : 0

  name        = module.labels.names["karpenter"]
  description = "Karpenter controller on ${var.cluster_name}: launches and terminates EC2 nodes the cluster owns"
  policy      = local.karpenter_policy

  tags = merge(module.labels.tags, var.tags, { Name = module.labels.names["karpenter"] })

  lifecycle {
    precondition {
      condition     = var.karpenter_node_role_arn != null
      error_message = "karpenter_node_role_arn is required when create_karpenter_policy is true: without it Karpenter could not pass a role to the nodes it launches."
    }
  }
}
