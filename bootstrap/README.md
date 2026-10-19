# Creation of terraform state using CloudFormation

## Verify your AWS account

```bash
aws sts get-caller-identity

aws configure get region
```

## Validate the CloudFormation template

```bash
aws cloudformation validate-template \
  --template-body file://terraform-state.yaml \
  --region ap-southeast-1
```

## Deploy the CloudFormation template

```bash
aws cloudformation deploy \
  --template-file .\terraform-state.yaml \
  --stack-name terraform-state-bootstrap \
  --region ap-southeast-1
```

## Retrieve the deployed template resources

```bash
aws cloudformation describe-stacks \
  --stack-name terraform-state-bootstrap \
  --region ap-southeast-1 \
  --query "Stacks[0].Outputs" \
  --output table
```

## Delete the deployed template

```bash
aws cloudformation delete-stack \
  --stack-name terraform-state-bootstrap \
  --region ap-southeast-1
```
