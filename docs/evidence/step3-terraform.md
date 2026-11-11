# Terraform evidence

## Clean plan (staging, no changes)
module.runtime.data.aws_ami.ubuntu: Reading...
module.runtime.data.aws_vpc.default: Reading...
module.runtime.aws_cloudwatch_log_group.app: Refreshing state... [id=/aws/ec2/devops-task/staging]
module.runtime.aws_iam_role.instance: Refreshing state... [id=devops-task-staging-ec2]
module.runtime.data.aws_ami.ubuntu: Read complete after 0s [id=ami-063d94c44d4eba6e0]
module.runtime.data.aws_vpc.default: Read complete after 0s [id=vpc-0126bcceee5319fe6]
module.runtime.data.aws_subnets.default: Reading...
module.runtime.aws_security_group.app: Refreshing state... [id=sg-02dea1564e5b5772d]
module.runtime.data.aws_subnets.default: Read complete after 0s [id=ap-southeast-1]
module.runtime.aws_iam_role_policy.logs: Refreshing state... [id=devops-task-staging-ec2:devops-task-staging-logs]
module.runtime.aws_iam_role_policy_attachment.ssm: Refreshing state... [id=devops-task-staging-ec2/arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore]
module.runtime.aws_iam_instance_profile.instance: Refreshing state... [id=devops-task-staging-ec2]
module.runtime.aws_instance.app: Refreshing state... [id=i-087d5d7936610b736]

No changes. Your infrastructure matches the configuration.

Terraform has compared your real infrastructure against your configuration
and found no differences, so no changes are needed.

## Apply outputs
instance_id = "i-087d5d7936610b736"
log_group_name = "/aws/ec2/devops-task/staging"
public_ip = "18.143.167.212"

## State (10 resources)
module.runtime.data.aws_ami.ubuntu
module.runtime.data.aws_subnets.default
module.runtime.data.aws_vpc.default
module.runtime.aws_cloudwatch_log_group.app
module.runtime.aws_iam_instance_profile.instance
module.runtime.aws_iam_role.instance
module.runtime.aws_iam_role_policy.logs
module.runtime.aws_iam_role_policy_attachment.ssm
module.runtime.aws_instance.app
module.runtime.aws_security_group.app

## Destroy

Destroy complete! Resources: 7 destroyed.
