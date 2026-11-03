module "kompass_insights" {
  source = "../.."

  dataset_id                               = var.dataset_id
  service_account_emails                   = var.service_account_emails
  query_project_id                         = var.query_project_id
  dataset_project_id                       = var.dataset_project_id
  create_dataset                           = var.create_dataset
  dataset_location                         = var.dataset_location
  externally_managed_dataset_reader_emails = var.externally_managed_dataset_reader_emails
  labels                                   = var.labels
}
