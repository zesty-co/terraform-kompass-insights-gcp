variable "dataset_id" {
  description = "ID of the dataset that receives the detailed billing export."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.dataset_id)) && length(var.dataset_id) <= 1024
    error_message = "dataset_id must contain 1 to 1024 letters, numbers, or underscores."
  }
}

variable "service_account_emails" {
  description = "Existing node service accounts that need billing access. Shared identities need one entry."
  type        = set(string)
  nullable    = false

  validation {
    condition = length(var.service_account_emails) > 0 && alltrue([
      for email in var.service_account_emails :
      can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.gserviceaccount\\.com$", email))
    ])
    error_message = "Provide at least one service-account email ending in .gserviceaccount.com."
  }
}

variable "query_project_id" {
  description = "Project where queries run. Defaults to the Google provider project."
  type        = string
  default     = null

  validation {
    condition     = var.query_project_id == null ? true : length(trimspace(var.query_project_id)) > 0
    error_message = "query_project_id must be null or a nonempty project ID."
  }
}

variable "dataset_project_id" {
  description = "Project that contains the billing dataset. Defaults to the query project."
  type        = string
  default     = null

  validation {
    condition     = var.dataset_project_id == null ? true : length(trimspace(var.dataset_project_id)) > 0
    error_message = "dataset_project_id must be null or a nonempty project ID."
  }
}

variable "create_dataset" {
  description = "Manage the dataset lifecycle. Set false to reference an externally managed dataset."
  type        = bool
  default     = false
  nullable    = false
}

variable "dataset_location" {
  description = "Billing-export location for a managed dataset. Existing datasets report their actual location."
  type        = string
  default     = null

  validation {
    condition     = !var.create_dataset || var.dataset_location != null
    error_message = "dataset_location is required when create_dataset is true."
  }

  validation {
    condition = var.dataset_location == null ? true : contains(
      local.supported_dataset_locations, lower(var.dataset_location)
    )
    error_message = "dataset_location must be a Google-supported location for detailed billing export."
  }

  validation {
    condition     = var.create_dataset || var.dataset_location == null
    error_message = "Omit dataset_location for an externally managed dataset; its location is read from Google."
  }
}

variable "externally_managed_dataset_reader_emails" {
  description = "Supplied identities whose direct dataset read grants stay with their existing owner."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition = length(setsubtract(
      var.externally_managed_dataset_reader_emails, var.service_account_emails
    )) == 0
    error_message = "Externally managed dataset readers must also appear in service_account_emails."
  }
}

variable "labels" {
  description = "Labels for a dataset managed by this module."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition     = var.create_dataset || length(var.labels) == 0
    error_message = "Labels can only be set when create_dataset is true."
  }
}
