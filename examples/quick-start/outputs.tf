output "billing_access" {
  description = "Billing destination and identities for export activation and subsequent runtime verification."
  value = {
    query_project_id       = module.kompass_insights.query_project_id
    dataset_project_id     = module.kompass_insights.dataset_project_id
    dataset_id             = module.kompass_insights.dataset_id
    dataset_location       = module.kompass_insights.dataset_location
    service_account_emails = module.kompass_insights.service_account_emails
  }
}
