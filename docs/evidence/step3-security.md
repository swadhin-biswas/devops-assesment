# Security posture (Terraform-built staging)

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
            "Resource": "arn:aws:logs:ap-southeast-1:434362445578:log-group:/aws/ec2/devops-task/staging:*"
        }
    ]
}

## No static keys (devopstask)
{
    "AccessKeyMetadata": []
}

## Instance: t3.micro, no key pair, instance profile attached
{
  "Id": "i-087d5d7936610b736",
  "Type": "t3.micro",
  "VPC": "vpc-0126bcceee5319fe6",
  "AZ": "ap-southeast-1a",
  "Key": null,
  "Profile": "arn:aws:iam::434362445578:instance-profile/devops-task-staging-ec2",
  "SG": [
    {
      "GroupId": "sg-02dea1564e5b5772d",
      "GroupName": "devops-task-staging-app"
    }
  ]
}
