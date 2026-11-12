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

## Both environments applied, then destroyed

Both environments were applied from this code, the release pipeline deployed
to the resulting instances, and everything was destroyed afterwards.

Staging, `terraform/envs/staging`:

```text
$ terraform plan -var-file=staging.tfvars
Plan: 6 to add, 1 to change, 0 to destroy.
$ terraform apply -var-file=staging.tfvars -auto-approve
module.runtime.aws_cloudwatch_log_group.app: Modifications complete after 0s [id=/aws/ec2/devops-task/staging]
module.runtime.aws_iam_role.instance: Creation complete after 2s [id=devops-task-staging-ec2]
module.runtime.aws_iam_role_policy_attachment.ssm: Creation complete after 1s [id=devops-task-staging-ec2/arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore]
module.runtime.aws_iam_role_policy.logs: Creation complete after 1s [id=devops-task-staging-ec2:devops-task-staging-logs]
module.runtime.aws_iam_instance_profile.instance: Creation complete after 8s [id=devops-task-staging-ec2]
module.runtime.aws_security_group.app: Creation complete after 3s [id=sg-07f20adaa00676e1a]
module.runtime.aws_instance.app: Creation complete after 13s [id=i-081a665854ba77101]

Apply complete! Resources: 6 added, 1 changed, 0 destroyed.

Outputs:

instance_id = "i-081a665854ba77101"
log_group_name = "/aws/ec2/devops-task/staging"
public_ip = "52.221.230.102"
```

Production, `terraform/envs/production`, with the CIDR overridden on the
command line because the committed value is the documentation range:

```text
$ terraform apply -var-file=production.tfvars -var allowed_cidr=0.0.0.0/0 -auto-approve
Apply complete! Resources: 6 added, 1 changed, 0 destroyed.

Outputs:

instance_id = "i-05229c53e54895401"
log_group_name = "/aws/ec2/devops-task/production"
public_ip = "13.212.174.204"
```

The user data bootstrapped both instances on their own, with no SSH:

```text
PRETTY_NAME="Ubuntu 24.04.5 LTS"
Docker version 29.1.3, build 29.1.3-0ubuntu3~24.04.2
AWS_REGION=ap-southeast-1
LOG_GROUP=/aws/ec2/devops-task/staging
APP_ENV=staging
LOG_LEVEL=INFO
2.1.1
devops-task-app swadhinbiswas/devops-task:v2.1.1 Up 10 minutes (healthy)
{"status":"ok","version":"2.1.1","environment":"staging"}
```

The release workflow then deployed `v2.1.2` to those instances over SSM
(run [43196222236](https://github.com/swadhin-biswas/devops-assesment/actions/runs/43196222236)),
and both reported `healthy: 2.1.2`.

One bug surfaced during this run. The environment level `app_version` default
had drifted to `2.0.0` while the image tag moved on, so a Terraform-provisioned
instance ran the current image but reported the old version. The version now
comes from the pinned `vMAJOR.MINOR.PATCH` image tag, the module takes it
explicitly, `image_uri` is validated to be a semver tag, and
`scripts/check_versions.sh` asserts the derivation so it cannot drift again.
The bootstrap script also moved into its own `terraform_data` resource, so a
change to the user data replaces the instance instead of being applied in place
to an instance that already booted.

Destroy, both environments:

```text
$ terraform destroy -var-file=staging.tfvars -auto-approve
Destroy complete! Resources: 8 destroyed.

$ terraform destroy -var-file=production.tfvars -var allowed_cidr=0.0.0.0/0 -auto-approve
Destroy complete! Resources: 8 destroyed.
```

What is left in the account afterwards:

```text
$ aws ec2 describe-instances --filters Name=instance-state-name,Values=running,pending,stopped --query ...
(no output)

$ aws ec2 describe-volumes --query ...
(no output)

$ aws ec2 describe-addresses --query ...
(no output)

$ aws iam list-instance-profiles --query ...
(no output)

$ aws logs describe-log-groups --log-group-name-prefix /aws/ec2/devops-task
(no output)

$ aws s3 ls
2026-11-11 11:52:52 devops-task-tfstate-33b24359cdc06619b607c93fe3
```

The state bucket stays because it holds the Terraform state. The container
output that the log groups collected is in
[step3-cloudwatch-sample.txt](step3-cloudwatch-sample.txt).
