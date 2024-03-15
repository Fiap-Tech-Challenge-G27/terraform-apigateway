variable "aws-region" {
  type        = string  
  description = "Região da AWS"
  default     = "us-east-1"
}

terraform {
  required_version = ">= 1.3, <= 1.7.5"

  backend "s3" {
    bucket         = "techchallengestate-g27"
    key            = "terraform-apigateway/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
  }

  required_providers {
    
    random = {
      version = "~> 3.0"
    }

    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.65"
    }
  }
}

provider "aws" {
  region = var.aws-region
}

data "terraform_remote_state" "lambda" {
  backend = "s3"
  config = {
    bucket = "techchallengestate-g27"
    key    = "terraform-lambda/terraform.tfstate"
    region = var.aws-region
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "AuthenticationAPI"
  description = "API for user authentication"
}

resource "aws_api_gateway_resource" "auth_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "auth"
}

resource "aws_api_gateway_method" "auth_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.auth_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.auth_resource.id
  http_method = aws_api_gateway_method.auth_method.http_method

  integration_http_method = "GET"
  type                    = "AWS_PROXY"
  uri                     = data.terraform_remote_state.lambda.outputs.lambda_function_invoke_arn
}

# Deploy the API Gateway
resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on = [aws_api_gateway_integration.lambda_integration]

  rest_api_id = aws_api_gateway_rest_api.api.id
#   stage_name  = "prod"
}

# Give API Gateway permissions to invoke the Lambda function
resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = data.terraform_remote_state.lambda.outputs.lambda_function_name
  principal     = "apigateway.amazonaws.com"

  # Source ARN for the API Gateway method
  source_arn = "${aws_api_gateway_rest_api.api.execution_arn}/auth"
}