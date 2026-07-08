variable "aws_region" {
  description = "AWS region to deploy the lab into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "sfn-lab"
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for Lambdas and the state machine."
  type        = number
  default     = 3
}
variable "aws_profile" {
  description = "AWS CLI profile to use for credentials."
  type        = string
  default     = "default"
}
