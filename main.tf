provider "aws" {
  region = "ap-south-1"
}

resource "aws_instance" "Jdoodle" {
  ami           = "ami-0a7cf821b91bcccbc" # Ubuntu 20.04 LTS in us-west-2
  instance_type = "t2.micro"
}

resource "aws_launch_configuration" "Jdoodle" {
  name          = "Jdoodle"
  image_id      = "ami-0a7cf821b91bcccbc" # Ubuntu 20.04 LTS in us-west-2
  instance_type = "t2.micro"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "Jdoodle" {
  desired_capacity   = 2
  max_size           = 5
  min_size           = 2
  health_check_type  = "EC2"
  launch_configuration = aws_launch_configuration.Jdoodle.id
  vpc_zone_identifier  = ["subnet-0d6d488d618cc419e", "subnet-0b86f55e063730f81"]

  tag {
    key                 = "Name"
    value               = "Jdoodle-asg"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale_up"
  autoscaling_group_name = aws_autoscaling_group.Jdoodle.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 300
}

resource "aws_cloudwatch_metric_alarm" "high_load" {
  alarm_name          = "high_load"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "LoadAverage5m"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = "75"
  alarm_description   = "This metric checks load average for 5 minutes"
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn, aws_sns_topic.notifications.arn]
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "scale_down"
  autoscaling_group_name = aws_autoscaling_group.Jdoodle.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 300
}

resource "aws_cloudwatch_metric_alarm" "low_load" {
  alarm_name          = "low_load"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "LoadAverage5m"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = "50"
  alarm_description   = "This metric checks load average for 5 minutes"
  alarm_actions       = [aws_autoscaling_policy.scale_down.arn, aws_sns_topic.notifications.arn]
}

resource "aws_iam_role" "lambda" {
  name = "lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com",
      },
    }],
  })
}

resource "aws_lambda_function" "refresh_instances" {
  filename      = "lambda_function_payload.zip"
  function_name = "lambda_function_name"
  role          = aws_iam_role.lambda.arn
  handler       = "exports.handler"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")
  runtime       = "nodejs18.x"
  timeout       = 300
}

resource "aws_cloudwatch_event_rule" "every_day" {
  schedule_expression = "cron(0 12 * * ? *)"
  name                = "every-day"
  description         = "Fires every day at 12am UTC"
}

resource "aws_cloudwatch_event_target" "refresh_instances_every_day" {
  rule      = aws_cloudwatch_event_rule.every_day.name
  target_id = "refresh_instances"
  arn       = aws_lambda_function.refresh_instances.arn
}

resource "aws_sns_topic" "notifications" {
  name = "notifications"
}

resource "aws_sns_topic_subscription" "Jdoodle_subscription" {
  topic_arn = aws_sns_topic.notifications.arn
  protocol  = "email"
  endpoint  = "dpardeshi777@gmail.com"  # Replace with your email address
}

output "sns_topic_arn" {
  value = aws_sns_topic.notifications.arn
}

output "sns_subscription_id" {
  value = aws_sns_topic_subscription.Jdoodle_subscription.id
}

resource "aws_autoscaling_notification" "Jdoodle" {
  group_names   = [aws_autoscaling_group.Jdoodle.name]
  notifications = ["autoscaling:EC2_INSTANCE_LAUNCH", "autoscaling:EC2_INSTANCE_TERMINATE"]
  topic_arn     = aws_sns_topic.notifications.arn
}