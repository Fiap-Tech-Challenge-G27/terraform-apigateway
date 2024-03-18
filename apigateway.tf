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

data "aws_lb" "k8s_lb" {
  name = "k8s-default-ingressb-97436f9206" 
}

resource "aws_apigatewayv2_api" "techchallaenge" {
  name          = "techchallenge"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "lambda" {
  api_id = aws_apigatewayv2_api.techchllanege.id

  name        = "auth"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn

    format = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
      }
    )
  }
}

resource "aws_apigatewayv2_integration" "auth_lambda" {
  api_id = aws_apigatewayv2_api.techchallenge.id

  integration_uri    = data.terraform_remote_state.lambda.outputs.lambda_function_invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

resource "aws_apigatewayv2_integration" "lanchonete" {
  api_id             = aws_apigatewayv2_api.techchllanege.id 
  integration_type   = "HTTP_PROXY"
  integration_uri    = data.aws_lb.k8s_lb.dns_name
  integration_method = "GET"
}

resource "aws_apigatewayv2_route" "lanchonete" {
  api_id    = aws_apigatewayv2_api.techchallenge.id 
  route_key = "GET /lanchonete" 
  target    = "integrations/${aws_apigatewayv2_integration.lanchonete.id}"
}



resource "aws_apigatewayv2_route" "auth_lambda" {
  api_id = aws_apigatewayv2_api.lambda.id

  route_key = "POST /auth"
  target    = "integrations/${aws_apigatewayv2_integration.auth_lambda.id}"
}

resource "aws_cloudwatch_log_group" "api_gw" {
  name = "/aws/api_gw/${aws_apigatewayv2_api.lambda.name}"

  retention_in_days = 30
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = data.terraform_remote_state.lambda.outputs.lambda_function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.lambda.execution_arn}/*/*"
}

# resource "aws_api_gateway_rest_api" "api" {
#   name        = "AuthenticationAPI"
#   description = "API for user authentication"
# }

# resource "aws_api_gateway_resource" "auth_resource" {
#   rest_api_id = aws_api_gateway_rest_api.api.id
#   parent_id   = aws_api_gateway_rest_api.api.root_resource_id
#   path_part   = "auth"
# }

# resource "aws_api_gateway_method" "auth_method" {
#   rest_api_id   = aws_api_gateway_rest_api.api.id
#   resource_id   = aws_api_gateway_resource.auth_resource.id
#   http_method   = "POST"
#   authorization = "NONE"
# }

# resource "aws_api_gateway_integration" "lambda_integration" {
#   rest_api_id = aws_api_gateway_rest_api.api.id
#   resource_id = aws_api_gateway_resource.auth_resource.id
#   http_method = aws_api_gateway_method.auth_method.http_method

#   integration_http_method = "POST"
#   type                    = "AWS_PROXY"
#   uri                     = data.terraform_remote_state.lambda.outputs.lambda_function_invoke_arn
# }

# # Deploy the API Gateway
# resource "aws_api_gateway_deployment" "api_deployment" {
#   depends_on = [aws_api_gateway_integration.lambda_integration]

#   rest_api_id = aws_api_gateway_rest_api.api.id
#   stage_name  = "prod"
#   triggers = {
#     always_run = "${timestamp()}"
#   }
# }

# # Give API Gateway permissions to invoke the Lambda function
# resource "aws_lambda_permission" "api_gateway_invoke" {
#   statement_id  = "AllowExecutionFromAPIGateway"
#   action        = "lambda:InvokeFunction"
#   function_name = data.terraform_remote_state.lambda.outputs.lambda_function_name
#   principal     = "apigateway.amazonaws.com"

#   # Source ARN for the API Gateway method
#   source_arn = "${aws_api_gateway_rest_api.api.execution_arn}/*/*/"
# }