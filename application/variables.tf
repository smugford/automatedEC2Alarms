variable "aws_region" {
  type        = string
  description = "Region to deploy resources into."
}

variable "company" {
  type        = string
  description = "Company to be used on all the resources as identifier."
}

variable "environment" {
  type        = string
  description = "Environment to be used on all the resources as identifier."
}

variable "application" {
  type        = string
  description = "The application name"
  default     = ""
}

variable "application_runbook_url"{
  type        = string
  description = "url for the application runbooks"
  default     = ""
}

variable "share_account_ids" {
  type        = string
  description = "The string (comma separated) of all the accounts that we want to share the document or automation with."
}

variable "template_bucket" {
  type        = string
  description = "The bucket that we are uploading the cloudformation templates to."
}

variable "input_paths_map" {
  description = "A map of input paths which are looked up by event rule filenames."
}

variable "input_template_map" {
  type = map(string)
  description = "A map of input templates which are looked up by event rule filenames."
}

variable "sns_topic_high" {
  type        = string
  description = "The SNS topic arn that we would like to send alarms to."
}

variable "sns_topic_low" {
  type        = string
  description = "The SNS topic arn that we would like to send notifications to."
}