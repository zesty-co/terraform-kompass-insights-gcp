data "google_project" "query" {
  project_id = var.query_project_id
}

locals {
  query_project_id   = data.google_project.query.project_id
  dataset_project_id = coalesce(var.dataset_project_id, local.query_project_id)
  managed_dataset_reader_emails = setsubtract(
    var.service_account_emails, var.externally_managed_dataset_reader_emails
  )

  # Cloud Billing supports fewer regions than BigQuery itself.
  # https://cloud.google.com/billing/docs/how-to/export-data-bigquery-setup#supported-dataset-locations
  supported_dataset_locations = toset([
    "us", "eu",
    "northamerica-northeast1", "southamerica-east1",
    "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
    "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
    "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1",
    "europe-central2", "europe-north1", "europe-west1", "europe-west2", "europe-west3",
    "europe-west4", "europe-west6", "me-central1", "me-central2", "me-west1",
  ])
}

resource "google_project_service" "bigquery" {
  for_each = toset([local.query_project_id, local.dataset_project_id])

  project            = each.value
  service            = "bigquery.googleapis.com"
  disable_on_destroy = false
}

resource "google_bigquery_dataset" "billing" {
  count = var.create_dataset ? 1 : 0

  project    = local.dataset_project_id
  dataset_id = var.dataset_id
  location   = var.dataset_location
  labels     = var.labels

  default_table_expiration_ms     = null
  default_partition_expiration_ms = null
  delete_contents_on_destroy      = false
  deletion_policy                 = "ABANDON"

  lifecycle {
    # Preserve access owners and report incompatible settings instead of changing them.
    ignore_changes = [
      access,
      default_table_expiration_ms,
      default_partition_expiration_ms,
      default_encryption_configuration,
    ]
  }

  depends_on = [google_project_service.bigquery]
}

data "google_bigquery_dataset" "billing" {
  project = local.dataset_project_id
  dataset_id = var.create_dataset ? (
    google_bigquery_dataset.billing[0].dataset_id
  ) : var.dataset_id

  lifecycle {
    postcondition {
      condition     = contains(local.supported_dataset_locations, lower(self.location))
      error_message = "Unmet prerequisite: the existing dataset location does not support billing export."
    }

    postcondition {
      condition     = length(self.default_encryption_configuration) == 0
      error_message = "Unmet prerequisite: this module supports Google-managed dataset encryption only."
    }

    postcondition {
      condition = (
        coalesce(self.default_table_expiration_ms, 0) == 0 &&
        coalesce(self.default_partition_expiration_ms, 0) == 0
      )
      error_message = "Unmet prerequisite: the billing dataset must not have default table or partition expiration."
    }

    postcondition {
      condition = alltrue([
        for email in var.externally_managed_dataset_reader_emails : anytrue([
          for access in self.access :
          access.user_by_email == email &&
          try(contains(["READER", "WRITER", "OWNER"], access.role), false) &&
          try(length(access.condition), 0) == 0
        ])
      ])
      error_message = "Unmet prerequisite: each external reader needs an existing unconditional direct dataset read grant."
    }
  }

  depends_on = [google_project_service.bigquery]
}

resource "google_project_iam_member" "billing_query" {
  for_each = var.service_account_emails

  project = local.query_project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${each.value}"

  depends_on = [data.google_bigquery_dataset.billing]
}

resource "google_bigquery_dataset_access" "billing_read" {
  for_each = local.managed_dataset_reader_emails

  project         = data.google_bigquery_dataset.billing.project
  dataset_id      = data.google_bigquery_dataset.billing.dataset_id
  role            = "READER"
  user_by_email   = each.value
  deletion_policy = "DELETE"
}
