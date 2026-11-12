# Terraform evidence

> Account-specific identifiers (account ID, VPC, subnet, security group, AMI,
> instance, public IP) are replaced with documentation placeholders. The
> plan, apply, destroy and IAM results are otherwise verbatim.


## Clean plan (staging, no changes)
module.runtime.data.aws_ami.ubuntu: Reading...
module.runtime.data.aws_vpc.default: Reading...
module.runtime.aws_cloudwatch_log_group.app: Refreshing state... [id=/aws/ec2/devops-task/staging]
module.runtime.aws_iam_role.instance: Refreshing state... [id=devops-task-staging-ec2]
module.runtime.data.aws_ami.ubuntu: Read complete after 0s [id=ami-0123456789abcdef0]
module.runtime.data.aws_vpc.default: Read complete after 0s [id=vpc-0123456789abcdef0]
module.runtime.data.aws_subnets.default: Reading...
module.runtime.aws_security_group.app: Refreshing state... [id=sg-0123456789abcdef0]
module.runtime.data.aws_subnets.default: Read complete after 0s [id=ap-southeast-1]
module.runtime.aws_iam_role_policy.logs: Refreshing state... [id=devops-task-staging-ec2:devops-task-staging-logs]
module.runtime.aws_iam_role_policy_attachment.ssm: Refreshing state... [id=devops-task-staging-ec2/arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore]
module.runtime.aws_iam_instance_profile.instance: Refreshing state... [id=devops-task-staging-ec2]
module.runtime.aws_instance.app: Refreshing state... [id=i-0123456789abcdef0]

No changes. Your infrastructure matches the configuration.

Terraform has compared your real infrastructure against your configuration
and found no differences, so no changes are needed.

## Apply outputs
instance_id = "i-0123456789abcdef0"
log_group_name = "/aws/ec2/devops-task/staging"
public_ip = "198.51.100.20"

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

## Remote state (S3 + native lockfile)

Both environments use a partial backend (`terraform/envs/{staging,production}/main.tf`):

```hcl
backend "s3" {}
```

The applied run used the values from the gitignored `backend.hcl`:
bucket from the bootstrap output, `staging/terraform.tfstate` or
`production/terraform.tfstate`, `ap-southeast-1`, encryption, and
`use_lockfile = true`. The example files are committed; the bucket-specific
file is not. There is no local state file; the state list above was read through
this backend:

```text
$ ls terraform/envs/staging/*.tfstate
ls: cannot access 'terraform/envs/staging/*.tfstate': No such file or directory
```

`.terraform/terraform.tfstate` records the resolved backend configuration
(bucket, `encrypt: true`, `use_lockfile: true`). `use_lockfile` is Terraform's
S3-native locking, which is why `required_version` is `>= 1.10.0`.

## Demo deploy targets destroyed after the final release

The two instances the release pipeline deployed to were terminated once the
final release evidence was captured, as the task asked. Their security groups
and the instance profile went with them.

```text
$ aws ec2 describe-instances --instance-ids i-073b2301f4bf67be5 i-0e12b3f4da2c399e5 --query 'Reservations[].Instances[].{Id:InstanceId,State:State.Name,Tags:Tags[?Key==`Name`].Value|[0]}' --output table
-----------------------------------------------------------------
|                       DescribeInstances                       |
+----------------------+-------------+--------------------------+
|          Id          |    State    |          Tags            |
+----------------------+-------------+--------------------------+
|  i-073b2301f4bf67be5 |  terminated |  devops-task-staging     |
|  i-0e12b3f4da2c399e5 |  terminated |  devops-task-production  |
+----------------------+-------------+--------------------------+

$ aws ec2 describe-instances --filters Name=instance-state-name,Values=running,pending,stopped --query 'Reservations[].Instances[].InstanceId' --output text

$ aws ec2 describe-volumes --query 'Volumes[].VolumeId' --output text

$ aws ec2 describe-addresses --query 'Addresses[].PublicIp' --output text

$ aws ec2 describe-security-groups --query 'SecurityGroups[?GroupName!=`default`].GroupName' --output text

$ aws iam list-instance-profiles --query 'InstanceProfiles[].InstanceProfileName' --output text

$ aws iam list-roles --query 'Roles[?starts_with(RoleName, `devops-task`)].RoleName' --output text
devops-task-github-deploy

$ aws logs describe-log-groups --log-group-name-prefix /aws/ec2/devops-task --query 'logGroups[].{Name:logGroupName,Retention:retentionInDays}' --output table
--------------------------------------------------
|                DescribeLogGroups               |
+----------------------------------+-------------+
|               Name               |  Retention  |
+----------------------------------+-------------+
|  /aws/ec2/devops-task/production |  30         |
|  /aws/ec2/devops-task/staging    |  14         |
+----------------------------------+-------------+

$ aws s3 ls
2026-11-11 11:52:52 devops-task-tfstate-33b24359cdc06619b607c93fe3

```

What stays in the account is the pipeline and the evidence: the
`devops-task-github-deploy` OIDC role the release workflow assumes, the S3
bucket that holds the Terraform state, and the two CloudWatch log groups that
recorded the container output (14-day staging, 30-day production retention).
To deploy again, run `terraform apply` for an environment and point
`EC2_INSTANCE_ID_STAGING` and `EC2_INSTANCE_ID_PROD` at the new instances.
