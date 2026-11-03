variable "project_id" {
  description = "Default Google provider project. Queries and the dataset use this project unless overridden."
  type        = string
  nullable    = false
}

variable "dataset_id" {
  description = "Dataset that receives the detailed billing export."
  type        = string
  nullable    = false
}

variable "service_account_emails" {
  description = "Existing node service accounts that need billing access."
  type        = set(string)
  nullable    = false
}

variable "query_project_id" {
  description = "Optional query project override."
  type        = string
  default     = null
}

variable "dataset_project_id" {
  description = "Optional billing dataset project override."
  type        = string
  default     = null
}

variable "create_dataset" {
  description = "Create or adopt a managed dataset instead of referencing an external dataset."
  type        = bool
  default     = false
  nullable    = false
}

variable "dataset_location" {
  description = "Required location when create_dataset is true."
  type        = string
  default     = null
}

variable "externally_managed_dataset_reader_emails" {
  description = "Supplied identities whose existing direct dataset read grants stay externally managed."
  type        = set(string)
  default     = []
  nullable    = false
}

variable "labels" {
  description = "Labels for a managed dataset."
  type        = map(string)
  default     = {}
  nullable    = false
}
