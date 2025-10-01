# Deploy
aws cloudformation deploy \
  --stack-name terraform-backend \
  --template-file backend.yaml

# Grab outputs
s3_bucket=$(aws cloudformation describe-stacks \
  --stack-name terraform-backend \
  --output text \
  --query "Stacks[0].Outputs[?OutputKey=='S3Bucket'].OutputValue | [0]")

dynamodb_table=$(aws cloudformation describe-stacks \
  --stack-name terraform-backend \
  --output text \
  --query "Stacks[0].Outputs[?OutputKey=='DynamoDBTable'].OutputValue | [0]")

echo
echo "S3 bucket: ${s3_bucket}"
echo "DynamoDB Table: ${dynamodb_table}"
echo "*** Please, add these two values in your Terraform backend block ***"
