output "cluster_endpoint" { value = aws_rds_cluster.main.endpoint; sensitive = true }
output "reader_endpoint"  { value = aws_rds_cluster.main.reader_endpoint; sensitive = true }
output "db_secret_arn"    { value = aws_secretsmanager_secret.db_credentials.arn }
