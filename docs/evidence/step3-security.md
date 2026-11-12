# Security posture (Terraform-built staging)

> Account-specific identifiers (account ID, VPC, subnet, security group, AMI,
> instance, public IP) are replaced with documentation placeholders. The
> plan, apply, destroy and IAM results are otherwise verbatim.


## Security group: only 8080 ingress
[
  {
    "IpProtocol": "tcp",
    "FromPort": 8080,
    "ToPort": 8080,
    "UserIdGroupPairs": [],
    "IpRanges": [
      {
        "Description": "Application traffic",
        "CidrIp": "0.0.0.0/0"
      }
    ],
    "Ipv6Ranges": [],
    "PrefixListIds": []
  }
]

## IAM: logs scoped to one log group
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Effect": "Allow",
            "Resource": "arn:aws:logs:ap-southeast-1:<account-id>:log-group:/aws/ec2/devops-task/staging:*"
        }
    ]
}

## No static keys (devopstask)
{
    "AccessKeyMetadata": []
}

## Instance: t3.micro, no key pair, instance profile attached
{
  "Id": "i-0123456789abcdef0",
  "Type": "t3.micro",
  "VPC": "vpc-0123456789abcdef0",
  "AZ": "ap-southeast-1a",
  "Key": null,
  "Profile": "arn:aws:iam::<account-id>:instance-profile/devops-task-staging-ec2",
  "SG": [
    {
      "GroupId": "sg-0123456789abcdef0",
      "GroupName": "devops-task-staging-app"
    }
  ]
}
