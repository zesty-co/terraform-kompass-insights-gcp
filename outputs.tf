output "query_project_id" {
  description = "Project where the supplied identities receive query execution permission."
  value       = local.query_project_id
  depends_on  = [google_project_iam_member.billing_query]
}

output "dataset_project_id" {
  description = "Project that contains the selected billing dataset."
  value       = data.google_bigquery_dataset.billing.project
  depends_on  = [google_bigquery_dataset_access.billing_read]
}

output "dataset_id" {
  description = "Selected billing dataset ID. The billing administrator activates detailed export here."
  value       = data.google_bigquery_dataset.billing.dataset_id
  depends_on  = [google_bigquery_dataset_access.billing_read]
}

output "dataset_location" {
  description = "Actual location of the billing dataset, for subsequent runtime queries."
  value       = data.google_bigquery_dataset.billing.location
}

output "service_account_emails" {
  description = "Supplied runtime identities. Permission setup does not establish working runtime access."
  value       = var.service_account_emails
  depends_on  = [google_project_iam_member.billing_query, google_bigquery_dataset_access.billing_read]
}
