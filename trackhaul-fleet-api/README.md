# TrackHaul — Serverless Fleet Management API

This folder contains the Serverless Fleet Management API — the operational control plane for querying and managing fleet vehicle records. The API is built on API Gateway, Lambda, and DynamoDB, secured with Cognito JWT authentication and KMS encryption throughout.

All infrastructure is defined in Terraform using a modular structure. No manual console configuration is used.

---

## Architecture

```
Dispatcher / Ops Admin
        │
        ▼
  Cognito User Pool
  (JWT IdToken)
        │
        ▼
  API Gateway REST API
  (Cognito Authoriser)
        │
        ▼
  Lambda — get_vehicle
  (Python 3.12)
        │
        ▼
  DynamoDB — trackhaul-vehicles
  (KMS CMK encrypted)
```

**Primary region:** eu-central-1  
**Auth:** Cognito JWT — IdToken passed in Authorization header  
**Encryption:** KMS customer managed key — DynamoDB and Lambda environment variables  

---

## API Endpoints

| Method | Path | Description | Groups Permitted |
|---|---|---|---|
| GET | /fleet/{truckId} | Retrieve vehicle record by truck ID | ops-admin, dispatcher, auditor |

---

## Module Reference

| Module | Path | Description |
|---|---|---|
| `kms` | `modules/kms` | Customer managed key for DynamoDB and Lambda encryption. Key rotation enabled. |
| `dynamodb` | `modules/dynamodb` | Vehicle records table. On-demand billing. Encrypted with KMS CMK. |
| `iam` | `modules/iam` | Lambda execution role. Least privilege — scoped to specific table, log group, and KMS key only. |
| `lambda` | `modules/lambda` | Fleet query handler. Python 3.12. Packaged and deployed via Terraform archive. |
| `api_gateway` | `modules/api_gateway` | REST API with Cognito JWT authoriser. Throttling configured per stage. |
| `cognito` | `modules/cognito` | User pool with three groups — ops-admin, dispatcher, auditor. |

---

## Repository Structure

```
trackhaul-fleet-api/
├── main.tf                        — Root module (empty — deployment driven from environments/)
├── variables.tf                   — Input variable declarations
├── outputs.tf                     — Root outputs
├── providers.tf                   — AWS provider configuration
├── backend.tf                     — Remote state configuration
├── terraform.tfvars.example       — Variable template (copy to terraform.tfvars)
├── environments/
│   └── dev/
│       ├── main.tf                — Module orchestration for dev environment
│       ├── variables.tf           — Dev variable declarations
│       ├── outputs.tf             — Dev outputs
│       └── backend.tf             — Dev remote state
├── lambda_src/
│   └── get_vehicle.py             — Lambda handler — fleet vehicle query
├── modules/
│   ├── api_gateway/               — REST API, Cognito authoriser, throttling
│   ├── cognito/                   — User pool, groups, app client
│   ├── dynamodb/                  — Vehicle records table
│   ├── iam/                       — Lambda execution role and policies
│   ├── kms/                       — Customer managed key
│   └── lambda/                    — Function deployment, CloudWatch log group
├── scripts/                       — Utility scripts
└── docs/                          — Module and architecture documentation
```

---

## Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| Terraform | >= 1.6 | Infrastructure provisioning |
| AWS CLI | >= 2.13 | Authentication and CLI operations |
| Python | >= 3.12 | Lambda function runtime |
| Git | Any | Version control |

AWS prerequisites:
- IAM Identity Center configured — SSO profile with admin access to target account
- Terraform remote state S3 bucket and DynamoDB lock table provisioned
- S3 bucket: `trackhaul-terraform-state-281136219737`
- DynamoDB lock table: `trackhaul-terraform-locks`

---

## Usage

### 1. Authenticate

```bash
aws sso login --profile default

# Verify you are in the correct account
aws sts get-caller-identity --profile default
```

### 2. Initialise Terraform

```bash
cd trackhaul-fleet-api/environments/dev

terraform init
```

### 3. Plan

```bash
terraform plan -var-file="terraform.tfvars"
```

### 4. Apply

```bash
terraform apply -var-file="terraform.tfvars"
```

### 5. Get a Cognito token for testing

```bash
TOKEN=$(aws cognito-idp initiate-auth \
  --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters USERNAME=<username>,PASSWORD=<password> \
  --client-id <app_client_id> \
  --query "AuthenticationResult.IdToken" \
  --output text \
  --profile default)
```

### 6. Call the API

```bash
curl -s \
  -H "Authorization: $TOKEN" \
  "https://<api-id>.execute-api.eu-central-1.amazonaws.com/dev/fleet/TH-4821"
```

Expected response:

```json
{
    "truck_id": "TH-4821",
    "make": "Mercedes",
    "model": "Actros",
    "plate": "B-TH-4821",
    "status": "active",
    "region": "DE",
    "year": 2021
}
```

---

## Security Considerations

**KMS encryption**  
A customer managed key is used for DynamoDB table encryption and Lambda environment variable encryption. The key policy grants decrypt access explicitly to the Lambda execution role. AWS managed keys are not used. Key rotation is enabled.

**Least privilege IAM**  
The Lambda execution role has three inline policies — CloudWatch Logs scoped to the function's log group only, DynamoDB scoped to the specific table ARN and its GSIs only, and KMS scoped to the CMK ARN only. No wildcard resources.

**Cognito JWT authorisation**  
All API Gateway endpoints require a valid Cognito IdToken in the Authorization header. Unauthenticated requests are rejected at the API Gateway layer before reaching Lambda.

**No PII in records**  
Vehicle records contain truck IDs, make, model, plate, region, and status only. No driver names, personal identifiers, or GPS coordinates are stored in this table.

**AWSLambdaBasicExecutionRole**  
The Lambda execution role attaches the AWS managed `AWSLambdaBasicExecutionRole` policy as a baseline. Without this, the AWS managed Lambda KMS key denies environment variable decryption at invocation time — a non-obvious failure mode that produces misleading KMS error messages.

---

## Hints

**Cognito username vs email**  
When a user is created programmatically, Cognito assigns a UUID as the username. Email is stored as an attribute but is not usable as a login identifier unless the user pool is configured with email as a sign-in alias. Use the UUID when calling `initiate-auth` unless aliases are explicitly enabled.

**USER_PASSWORD_AUTH must be enabled on the app client**  
The `initiate-auth` CLI call with `USER_PASSWORD_AUTH` flow will return `NotAuthorizedException` if this flow is not explicitly enabled on the Cognito app client — even with correct credentials.

**API Gateway stage must be redeployed after resource changes**  
Adding or modifying API Gateway resources in Terraform does not automatically update the live stage. Force redeployment with `-replace` on the deployment resource:

```bash
terraform apply -replace="module.api_gateway.aws_api_gateway_deployment.this"
```

**KMS key policy and IAM role policy — both must allow**  
AWS KMS enforces a two-sided permission model. The IAM role policy must allow `kms:Decrypt` and the KMS key policy must also explicitly allow the role. Either side alone is insufficient.
