output "user_pool_id"    { value = aws_cognito_user_pool.main.id }
output "app_client_id"  { value = aws_cognito_user_pool_client.web.id }
output "cognito_domain" { value = aws_cognito_user_pool_domain.main.domain }
