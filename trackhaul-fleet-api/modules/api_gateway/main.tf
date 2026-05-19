# REST API
resource "aws_api_gateway_rest_api" "this" {
  name        = var.api_name
  description = "TrackHaul Fleet Management API"

  endpoint_configuration {
    types = ["REGIONAL"] # Never EDGE for GDPR — EDGE uses CloudFront PoPs outside EU
  }

  tags = {
    Project     = "trackhaul"
    Environment = var.environment
  }
}

# /fleet resource
resource "aws_api_gateway_resource" "fleet" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "fleet"
}

# /fleet/{truckId} resource
resource "aws_api_gateway_resource" "fleet_truck" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.fleet.id
  path_part   = "{truckId}"
}

# GET /fleet/{truckId}
resource "aws_api_gateway_method" "get_vehicle" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.fleet_truck.id
  http_method   = "GET"
  authorization        = "COGNITO_USER_POOLS"
  authorizer_id        = aws_api_gateway_authorizer.cognito.id
  authorization_scopes = []

  request_parameters = {
    "method.request.path.truckId" = true # truckId path param is required
  }
}

resource "aws_api_gateway_integration" "get_vehicle" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.fleet_truck.id
  http_method             = aws_api_gateway_method.get_vehicle.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.get_vehicle_invoke_arn
}


resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.fleet.id,
      aws_api_gateway_resource.fleet_truck.id,
      aws_api_gateway_method.get_vehicle.id,
      aws_api_gateway_integration.get_vehicle.id,
      aws_api_gateway_authorizer.cognito.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_method.get_vehicle,
    aws_api_gateway_integration.get_vehicle,
  ]
}

# Stage with throttling
resource "aws_api_gateway_stage" "this" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
  stage_name    = var.stage_name


  tags = {
    Project     = "trackhaul"
    Environment = var.environment
  }
}

# Method-level throttling on GET /fleet/{truckId}
resource "aws_api_gateway_method_settings" "get_vehicle" {
  depends_on = [aws_api_gateway_account.this]
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name
  method_path = "${aws_api_gateway_resource.fleet_truck.path_part}/GET"

  settings {
    throttling_rate_limit  = var.throttling_rate_limit
    throttling_burst_limit = var.throttling_burst_limit
    logging_level          = "INFO" # ERROR in prod — INFO is noisy at scale
    data_trace_enabled     = false  # Never enable in prod — logs full request/response bodies
    metrics_enabled        = true
  }
}

resource "aws_iam_role" "api_gateway_cloudwatch" {
  name = "trackhaul-apigw-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "apigateway.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch" {
  role       = aws_iam_role.api_gateway_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "this" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch.arn
}

resource "aws_api_gateway_authorizer" "cognito" {
  name            = "${var.api_name}-${var.environment}-cognito-authorizer"
  rest_api_id     = aws_api_gateway_rest_api.this.id
  type            = "COGNITO_USER_POOLS"
  provider_arns   = [var.user_pool_arn]
  identity_source = "method.request.header.Authorization"
}