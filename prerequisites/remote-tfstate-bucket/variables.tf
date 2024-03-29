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