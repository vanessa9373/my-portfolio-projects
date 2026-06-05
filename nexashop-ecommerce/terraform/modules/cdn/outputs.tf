output "cloudfront_domain"    { value = aws_cloudfront_distribution.main.domain_name }
output "cloudfront_id"        { value = aws_cloudfront_distribution.main.id }
output "frontend_bucket_name" { value = aws_s3_bucket.frontend.bucket }
output "frontend_bucket_arn"  { value = aws_s3_bucket.frontend.arn }
