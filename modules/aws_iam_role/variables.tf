variable "name" {
  type        = string
  description = "The name of the role and policy."
}

variable "description" {
  type        = string
  description = "Description to attach to the role."
}

variable "enabled" {
  type        = string
  description = "Determines if the policy is to be created (true|false)"
  default     = "false"
}

variable "trust" {
  type        = string
  description = "Trust policy to attach to the role."
}

variable "policy" {
  type        = string
  description = "Policy to create and attach in aws_iam_policy."
}
