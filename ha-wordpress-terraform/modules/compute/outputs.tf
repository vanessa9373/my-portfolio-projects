output "alb_dns_name"   { value = aws_lb.main.dns_name }
output "alb_zone_id"    { value = aws_lb.main.zone_id }
output "alb_arn_suffix" { value = aws_lb.main.arn_suffix }
output "asg_name"       { value = aws_autoscaling_group.wordpress.name }
output "target_group_arn" { value = aws_lb_target_group.wordpress.arn }
output "tg_arn_suffix"  { value = aws_lb_target_group.wordpress.arn_suffix }
