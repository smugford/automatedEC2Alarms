variable "target_resource_arn" {
  type        = string
  description = "The ARN of the SSM document that we will be targeting."
}

variable "cloudwatch_event_rule" {
  type        = string
  description = "The name of the cloudwatch event rule that the target is attached to."
}

variable "cloudwatch_event_execution_role" {
  type        = string
  description = "The role that the event target will use to trigger the SSM document."
  default     = ""
}

variable "input_paths" {
  type        = map(string)
  description = "The data that we are taking from the event."
  default     = {}
}

variable "input_template" {
  type        = string
  description = "The output that we are getting from the input path data."
  default     = ""
}