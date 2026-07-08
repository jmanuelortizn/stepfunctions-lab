# One map drives everything: add a Lambda here and Terraform
# packages it, creates the function, its log group, and wires it
# into the state machine template. Good talking point: DRY via
# for_each instead of copy-pasted resources.

locals {
  lambda_functions = {
    validate_input = { description = "Validates pipeline input payload" }
    process_record = { description = "Processes a single record (Map state)" }
    enrich_data    = { description = "Enriches batch metadata (Parallel branch)" }
    quality_check  = { description = "Data quality checks (Parallel branch)" }
    notify         = { description = "Emits final pipeline summary" }
  }
}

# --- Execution role shared by all lab Lambdas (least privilege:
# --- they only need to write logs) -----------------------------

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${var.project_name}-lambda-exec"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# --- Packaging + functions -------------------------------------

data "archive_file" "lambda_zip" {
  for_each = local.lambda_functions

  type        = "zip"
  source_file = "${path.module}/src/${each.key}.py"
  output_path = "${path.module}/.build/${each.key}.zip"
}

resource "aws_lambda_function" "pipeline" {
  for_each = local.lambda_functions

  function_name = "${var.project_name}-${replace(each.key, "_", "-")}"
  description   = each.value.description
  role          = aws_iam_role.lambda_exec.arn

  filename         = data.archive_file.lambda_zip[each.key].output_path
  source_code_hash = data.archive_file.lambda_zip[each.key].output_base64sha256

  handler = "${each.key}.handler"
  runtime = "python3.12"
  timeout = 15

  depends_on = [aws_cloudwatch_log_group.lambda]
}

# Explicit log groups so retention is controlled by IaC instead of
# the default "never expire" — cost + governance talking point.
resource "aws_cloudwatch_log_group" "lambda" {
  for_each = local.lambda_functions

  name              = "/aws/lambda/${var.project_name}-${replace(each.key, "_", "-")}"
  retention_in_days = var.log_retention_days
}
