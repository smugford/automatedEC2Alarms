variable "name" {
  type        = string
  description = "The name of the ssm parameter."
}

variable "type" {
  type        = string
  description = "The type of the ssm parameter."
}

variable "value" {
  type        = string
  description = "The value of the ssm parameter."
}

variable "tags" {
  type        = map
  description = "Standard set of tags."
  default     = {automation = "terraform"}
}

variable "param_tags" {
  type        = map
  description = "Additional tags specific to parameter"
  default     = {}
}

variable "allow_overwrite" {
  type        = string
  description = "Enable or disable overwrite of SSM Paramters"
  default     = "true"
}