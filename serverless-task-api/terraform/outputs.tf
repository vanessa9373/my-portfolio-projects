output "api_endpoint" {
  description = "Base URL for the Task API"
  value       = "${aws_apigatewayv2_stage.main.invoke_url}"
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.tasks.name
}

output "lambda_function_names" {
  value = {
    create = aws_lambda_function.create_task.function_name
    get    = aws_lambda_function.get_task.function_name
    list   = aws_lambda_function.list_tasks.function_name
    update = aws_lambda_function.update_task.function_name
    delete = aws_lambda_function.delete_task.function_name
  }
}
