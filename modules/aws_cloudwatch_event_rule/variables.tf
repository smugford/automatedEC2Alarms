variable "name" {
  type        = string
  description = "The name of the event rule."
}

variable "description" {
  type        = string
  description = "The description for the event rule."
}

variable "event_pattern" {
  type        = string
  description = "The event pattern for the event rule."
}

variable "create_event_target" {
  type        = string
  description = "Create an event target at the same time of the event (true|false)"
  default     = "false"
}

variable "target_resource_arn" {
  type        = string
  description = "Arn of the target (ssm document, etc) for when we create an event target."
  default     = ""
}

variable "policy_actions" {
  type        = list(string)
  description = "The actions to attach to the policy allowing access to the resource defined in the variable `target_resource_arn`."
  default     = []
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