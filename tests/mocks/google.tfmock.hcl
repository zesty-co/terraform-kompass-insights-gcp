# Only provider responses are mocked. Resource configuration and module guards
# are evaluated by Terraform against the installed Google provider schema.
# Native mocks do not resolve provider-level project defaults. Test callers
# supply query_project_id; real provider default resolution needs a live check.

mock_data "google_bigquery_dataset" {
  defaults = {
    id                               = "projects/example-query-project/datasets/billing_export"
    project                          = "example-query-project"
    dataset_id                       = "billing_export"
    location                         = "EU"
    default_table_expiration_ms      = 0
    default_partition_expiration_ms  = 0
    default_encryption_configuration = []
    access                           = []
  }
}
