mock_provider "google" {
  source = "./tests/mocks"
}

variables {
  query_project_id = "example-query-project"
  dataset_id       = "billing_export"
  service_account_emails = [
    "node-a@identity-project.iam.gserviceaccount.com",
    "node-b@other-identity-project.iam.gserviceaccount.com",
    "node-a@identity-project.iam.gserviceaccount.com",
  ]
}

run "existing_dataset_cross_project_permissions" {
  # API enablement defers the dataset read; apply here is entirely mocked.
  command = apply

  variables {
    query_project_id   = "example-runtime-project"
    dataset_project_id = "example-billing-project"
    billing_account_id = "012345-ABCDEF-678901"
  }

  override_data {
    target = data.google_bigquery_dataset.billing
    values = {
      id                               = "projects/example-billing-project/datasets/billing_export"
      project                          = "example-billing-project"
      dataset_id                       = "billing_export"
      location                         = "EU"
      default_table_expiration_ms      = 0
      default_partition_expiration_ms  = 0
      default_encryption_configuration = []
      access                           = []
    }
  }

  assert {
    condition = length(google_project_iam_member.billing_query) == 2 && toset([
      for grant in google_project_iam_member.billing_query :
      "${grant.project}|${grant.role}|${grant.member}"
      ]) == toset([
      "example-runtime-project|roles/bigquery.jobUser|serviceAccount:node-a@identity-project.iam.gserviceaccount.com",
      "example-runtime-project|roles/bigquery.jobUser|serviceAccount:node-b@other-identity-project.iam.gserviceaccount.com",
    ])
    error_message = "Every distinct identity must receive query execution permission only in the query project."
  }

  assert {
    condition = length(google_bigquery_dataset_access.billing_read) == 2 && toset([
      for grant in google_bigquery_dataset_access.billing_read :
      "${grant.project}/${grant.dataset_id}|${grant.role}|${grant.user_by_email}"
      ]) == toset([
      "example-billing-project/billing_export|READER|node-a@identity-project.iam.gserviceaccount.com",
      "example-billing-project/billing_export|READER|node-b@other-identity-project.iam.gserviceaccount.com",
    ])
    error_message = "Dataset read grants must target the billing dataset, not the query or identity projects."
  }

  assert {
    condition = toset([
      for service in google_project_service.bigquery :
      "${service.project}|${service.service}|${service.disable_on_destroy}"
      ]) == toset([
      "example-runtime-project|bigquery.googleapis.com|false",
      "example-billing-project|bigquery.googleapis.com|false",
    ])
    error_message = "Both projects need BigQuery API declarations that do not disable the API on removal."
  }

  assert {
    condition     = length(google_bigquery_dataset.billing) == 0 && output.dataset_location == "EU"
    error_message = "Referencing an existing dataset must not manage its lifecycle and must report its observed location."
  }

  assert {
    condition     = output.expected_export_table == "example-billing-project.billing_export.gcp_billing_export_resource_v1_012345_ABCDEF_678901"
    error_message = "The expected detailed export must identify the billing account in the dataset project, not the query project."
  }
}

run "same_project_deduplicates_api_declarations" {
  command = plan

  assert {
    condition = length(google_project_service.bigquery) == 1 && alltrue([
      for service in google_project_service.bigquery : service.project == "example-query-project"
    ])
    error_message = "When the dataset uses the query project, declare the BigQuery API exactly once."
  }

  assert {
    condition     = output.expected_export_table == null
    error_message = "Without a billing account ID, the module must not guess an export table."
  }
}

run "created_dataset_has_non_destructive_retention_policy" {
  command = plan

  # Exercise the longest valid ID without relying on provider validation.
  variables {
    create_dataset     = true
    dataset_project_id = "example-billing-project"
    dataset_location   = "europe-west1"
    dataset_id         = format("%01024d", 0)
  }

  assert {
    condition = (
      length(google_bigquery_dataset.billing) == 1 &&
      google_bigquery_dataset.billing[0].project == "example-billing-project" &&
      google_bigquery_dataset.billing[0].deletion_policy == "ABANDON" &&
      !google_bigquery_dataset.billing[0].delete_contents_on_destroy
    )
    error_message = "Managed billing datasets must target the dataset project and declare retention rather than destructive deletion."
  }

  assert {
    condition = (
      coalesce(google_bigquery_dataset.billing[0].default_table_expiration_ms, 0) == 0 &&
      coalesce(google_bigquery_dataset.billing[0].default_partition_expiration_ms, 0) == 0 &&
      length(google_bigquery_dataset.billing[0].default_encryption_configuration) == 0
    )
    error_message = "Created billing datasets must have no default expiration or customer-managed encryption key."
  }
}
