variable "name" {
  type        = string
  description = "The name of the ssm document."
}

variable "document_type" {
  type        = string
  description = "The type of the document (Automation|Command)."
}

variable "content" {
  type        = string
  description = "The contents of the automation or document."
}

variable "document_format" {
  type        = string
  description = "The format of the document (YAML|JSON)."
}

variable "share_account_ids" {
  type        = string
  description = "The string (comma separated) of all the accounts that we want to share the document or automation with."
  default     = ""
}

variable "company" {
  type        = string
  description = "Company to be used on all the resources as identifier."
  default     = "cloud-brothers"
}

variable "environment" {
  type        = string
  description = "Environment to be used on all the resources as identifier."
  default     = "test"
}

variable "tags" {
  type        = map
  description = "Standard set of tags."
  default     = { automation  = "terraform" }
}

variable "document_tags" {
  type        = map
  description = "Additional tags specific to the document."
  default     = {}
}