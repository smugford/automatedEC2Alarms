variable "name" {
  type        = string
  description = "The name of the role and policy."
}

variable "enabled" {
  type        = number
  description = "Determines if the policy is to be created (1 or 0)"
}

variable "description" {
  type        = string
  description = "Description to attach to the role."
}

variable "policy" {
  type        = string
  description = "Policy to create and attach in aws_iam_policy."
}
