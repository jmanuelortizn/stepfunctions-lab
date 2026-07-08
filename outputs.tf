output "state_machine_arn" {
  description = "ARN of the pipeline state machine."
  value       = aws_sfn_state_machine.pipeline.arn
}

output "start_execution_happy_path" {
  description = "Run this to trigger the happy path (Choice -> valid)."
  value       = <<-EOT
    aws stepfunctions start-execution \
      --state-machine-arn ${aws_sfn_state_machine.pipeline.arn} \
      --input '{"source":"s3","records":[{"id":1,"value":10},{"id":2,"value":20},{"id":3,"value":30}]}'
  EOT
}

output "start_execution_invalid_input" {
  description = "Triggers the Choice default branch -> Fail state."
  value       = <<-EOT
    aws stepfunctions start-execution \
      --state-machine-arn ${aws_sfn_state_machine.pipeline.arn} \
      --input '{"source":"s3"}'
  EOT
}

output "start_execution_quality_failure" {
  description = "Record without numeric value -> QualityCheck raises -> Catch -> HandleFailure."
  value       = <<-EOT
    aws stepfunctions start-execution \
      --state-machine-arn ${aws_sfn_state_machine.pipeline.arn} \
      --input '{"source":"s3","records":[{"id":1,"value":10},{"id":2,"value":"oops"}]}'
  EOT
}
