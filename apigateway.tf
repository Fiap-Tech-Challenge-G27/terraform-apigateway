variable "aws-region" {
  type        = string  
  description = "Região da AWS"
  default     = "us-east-1"
}

terraform {
  required_version = ">= 1.3"

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

resource "aws_apigatewayv2_api" "techchallenge" {
  name          = "techchallenge"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "lambda" {
  api_id = aws_apigatewayv2_api.techchallenge.id

  name        = "lanchonete"
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

  integration_uri    = data.terraform_remote_state.lambda.outputs.authlambda_function_invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

resource "aws_apigatewayv2_integration" "delete_lambda" {
  api_id = aws_apigatewayv2_api.techchallenge.id

  integration_uri    = data.terraform_remote_state.lambda.outputs.deletelambda_function_invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

resource "aws_apigatewayv2_integration" "http_proxy_integration_basic" {
  for_each = toset([
    "POST/categories",
    "GET/categories",
    "POST/products",
    "GET/products",
    "POST/customers",
    "GET/customers",
    "POST/orders",
    "GET/orders",
    "GET/health",
    "POST/payment"
  ])

  api_id             = aws_apigatewayv2_api.techchallenge.id
  integration_type   = "HTTP_PROXY"
  integration_uri    = "http://${data.aws_lb.k8s_lb.dns_name}/${join("/", slice(split("/", each.key), 1, length(split("/", each.key))))}"
  integration_method = split("/", each.key)[0]
}

resource "aws_apigatewayv2_integration" "http_proxy_integration_dynamic" {
  for_each = toset([
    "GET/categories/{slug}",
    "PATCH/categories/{id}",
    "PATCH/products/{id}",
    "DELETE/products/{id}",
    "GET/customers/{cpf}",
    "PATCH/customers/{cpf}",
    "DELETE/customers/{cpf}",
    "GET/orders/{id}",
    "PATCH/orders/{id}/state"
  ])

  api_id             = aws_apigatewayv2_api.techchallenge.id
  integration_type   = "HTTP_PROXY"
  integration_uri    = "http://${data.aws_lb.k8s_lb.dns_name}/${join("/", slice(split("/", each.key), 1, length(split("/", each.key))))}"
  integration_method = split("/", each.key)[0]
}

resource "aws_apigatewayv2_route" "api_routes_dynamic" {
  for_each  = aws_apigatewayv2_integration.http_proxy_integration_dynamic
  api_id    = aws_apigatewayv2_api.techchallenge.id

  route_key = "${each.value.integration_method} /${each.key}"
  target    = "integrations/${each.value.id}"
}

resource "aws_apigatewayv2_integration" "http_proxy_integration_payment_confirmation" {
  api_id             = aws_apigatewayv2_api.techchallenge.id
  integration_type   = "HTTP_PROXY"
  integration_uri    = "http://${data.aws_lb.k8s_lb.dns_name}/orders/payment-confirmation"
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "api_route_payment_confirmation" {
  api_id    = aws_apigatewayv2_api.techchallenge.id
  route_key = "POST /orders/payment-confirmation"
  target    = "integrations/${aws_apigatewayv2_integration.http_proxy_integration_payment_confirmation.id}"
}

resource "aws_apigatewayv2_integration" "http_proxy_integration_customers_notification" {
  api_id             = aws_apigatewayv2_api.techchallenge.id
  integration_type   = "HTTP_PROXY"
  integration_uri    = "http://${data.aws_lb.k8s_lb.dns_name}/customers/notification"
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "api_route_customers_notification" {
  api_id    = aws_apigatewayv2_api.techchallenge.id
  route_key = "POST /customers/notification"
  target    = "integrations/${aws_apigatewayv2_integration.http_proxy_integration_customers_notification.id}"
}

resource "aws_apigatewayv2_integration" "http_proxy_integration_payment_initiate" {
  api_id             = aws_apigatewayv2_api.techchallenge.id
  integration_type   = "HTTP_PROXY"
  integration_uri    = "http://${data.aws_lb.k8s_lb.dns_name}/payment/initiate"
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "api_route_payment_initiate" {
  api_id    = aws_apigatewayv2_api.techchallenge.id
  route_key = "POST /payment/initiate"
  target    = "integrations/${aws_apigatewayv2_integration.http_proxy_integration_payment_initiate.id}"
}

resource "aws_apigatewayv2_integration" "http_proxy_integration_payment_toggle" {
  api_id             = aws_apigatewayv2_api.techchallenge.id
  integration_type   = "HTTP_PROXY"
  integration_uri    = "http://${data.aws_lb.k8s_lb.dns_name}/payment/toggle"
  integration_method = "PUT"
}

resource "aws_apigatewayv2_route" "api_route_payment_toggle" {
  api_id    = aws_apigatewayv2_api.techchallenge.id
  route_key = "PUT /payment/toggle"
  target    = "integrations/${aws_apigatewayv2_integration.http_proxy_integration_payment_toggle.id}"
}

resource "aws_apigatewayv2_route" "api_routes_basic" {
  for_each  = aws_apigatewayv2_integration.http_proxy_integration_basic
  api_id    = aws_apigatewayv2_api.techchallenge.id
  route_key = "${each.value.integration_method} /${split("/", each.key)[1]}"
  target    = "integrations/${each.value.id}"
}

resource "aws_apigatewayv2_route" "auth_lambda" {
  api_id = aws_apigatewayv2_api.techchallenge.id

  route_key = "POST /auth"
  target    = "integrations/${aws_apigatewayv2_integration.auth_lambda.id}"
}

resource "aws_apigatewayv2_route" "delete_lambda" {
  api_id = aws_apigatewayv2_api.techchallenge.id

  route_key = "POST /customers/delete"
  target    = "integrations/${aws_apigatewayv2_integration.delete_lambda.id}"
}

resource "aws_cloudwatch_log_group" "api_gw" {
  name = "/aws/api_gw/${aws_apigatewayv2_api.techchallenge.name}"

  retention_in_days = 30
}

resource "aws_lambda_permission" "api_gw_auth_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = data.terraform_remote_state.lambda.outputs.authlambda_function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.techchallenge.execution_arn}/*/*"
}

resource "aws_lambda_permission" "api_gw_delete_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = data.terraform_remote_state.lambda.outputs.deletelambda_function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.techchallenge.execution_arn}/*/*"
}

output "aws_apigatewayv2_api_endpoint" {
  value = aws_apigatewayv2_api.techchallenge.api_endpoint
}
