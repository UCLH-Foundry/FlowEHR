variable "prefix" {
  type        = string
  description = "The prefix to apply to resource names (i.e. to differentiate organisations/projects)"
}

variable "environment" {
  type        = string
  description = "The environment to apply to resource names (to differentiate environments)"
}

variable "location" {
  type        = string
  description = "The location to deploy resources"
}
