# --- IAM for the state machine: it may ONLY invoke the five lab
# --- Lambdas and write its own logs (least privilege) -----------

data "aws_iam_policy_document" "sfn_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "sfn_permissions" {
  statement {
    sid       = "InvokePipelineLambdas"
    actions   = ["lambda:InvokeFunction"]
    resources = [for fn in aws_lambda_function.pipeline : fn.arn]
  }

  # CloudWatch Logs delivery for Step Functions requires these
  # actions on * (documented AWS limitation).
  statement {
    sid = "StateMachineLogging"
    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
      "logs:DescribeLogGroups",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "sfn" {
  name               = "${var.project_name}-sfn-role"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume.json
}

resource "aws_iam_role_policy" "sfn" {
  name   = "${var.project_name}-sfn-policy"
  role   = aws_iam_role.sfn.id
  policy = data.aws_iam_policy_document.sfn_permissions.json
}

# --- Observability: execution history shipped to CloudWatch -----

resource "aws_cloudwatch_log_group" "sfn" {
  name              = "/aws/states/${var.project_name}-pipeline"
  retention_in_days = var.log_retention_days
}

# --- The state machine itself -----------------------------------
# Type = STANDARD: durable, exactly-once, up to 1 year, priced per
# state transition. EXPRESS: high-volume/short-lived (< 5 min),
# at-least-once, priced per request+duration — ideal for streaming.

resource "aws_sfn_state_machine" "pipeline" {
  name     = "${var.project_name}-pipeline"
  role_arn = aws_iam_role.sfn.arn
  type     = "STANDARD"

  definition = templatefile("${path.module}/statemachine/pipeline.asl.json", {
    validate_input_arn = aws_lambda_function.pipeline["validate_input"].arn
    process_record_arn = aws_lambda_function.pipeline["process_record"].arn
    enrich_data_arn    = aws_lambda_function.pipeline["enrich_data"].arn
    quality_check_arn  = aws_lambda_function.pipeline["quality_check"].arn
    notify_arn         = aws_lambda_function.pipeline["notify"].arn
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }
  tracing_configuration {
    enabled = true
  }
}
