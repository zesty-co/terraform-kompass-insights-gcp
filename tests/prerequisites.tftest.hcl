mock_provider "google" {
  source = "./tests/mocks"
}

variables {
  query_project_id       = "example-query-project"
  dataset_id             = "billing_export"
  service_account_emails = ["node-a@identity-project.iam.gserviceaccount.com"]
}

# The first mocked apply establishes the shared API fixture. Subsequent plans
# can read dataset metadata immediately instead of deferring it until apply.
# Each negative case changes only its named prerequisite; all others are valid.
run "external_direct_readers_keep_their_grant_owner" {
  command = apply

  variables {
    service_account_emails = [
      "node-a@identity-project.iam.gserviceaccount.com",
      "node-b@identity-project.iam.gserviceaccount.com",
      "node-c@identity-project.iam.gserviceaccount.com",
      "node-d@identity-project.iam.gserviceaccount.com",
    ]
    externally_managed_dataset_reader_emails = [
      "node-a@identity-project.iam.gserviceaccount.com",
      "node-b@identity-project.iam.gserviceaccount.com",
      "node-c@identity-project.iam.gserviceaccount.com",
    ]
  }

  override_data {
    target = data.google_bigquery_dataset.billing
    values = {
      id                               = "projects/example-query-project/datasets/billing_export"
      project                          = "example-query-project"
      dataset_id                       = "billing_export"
      location                         = "EU"
      default_table_expiration_ms      = 0
      default_partition_expiration_ms  = 0
      default_encryption_configuration = []
      access = [
        {
          role          = "READER"
          user_by_email = "node-a@identity-project.iam.gserviceaccount.com"
          condition     = []
        },
        {
          role          = "WRITER"
          user_by_email = "node-b@identity-project.iam.gserviceaccount.com"
          condition     = []
        },
        {
          role          = "OWNER"
          user_by_email = "node-c@identity-project.iam.gserviceaccount.com"
          condition     = []
        },
        {
          role          = null
          user_by_email = null
          condition     = []
          view = [{
            project_id = "analytics-project"
            dataset_id = "authorized_views"
            table_id   = "billing_totals"
          }]
        },
      ]
    }
  }

  assert {
    condition = length(google_bigquery_dataset_access.billing_read) == 1 && toset([
      for grant in google_bigquery_dataset_access.billing_read : grant.user_by_email
    ]) == toset(["node-d@identity-project.iam.gserviceaccount.com"])
    error_message = "Existing direct READER, WRITER, and OWNER grants must not acquire a second Terraform owner."
  }

  assert {
    condition = toset([
      for grant in google_project_iam_member.billing_query : grant.member
      ]) == toset([
      "serviceAccount:node-a@identity-project.iam.gserviceaccount.com",
      "serviceAccount:node-b@identity-project.iam.gserviceaccount.com",
      "serviceAccount:node-c@identity-project.iam.gserviceaccount.com",
      "serviceAccount:node-d@identity-project.iam.gserviceaccount.com",
    ])
    error_message = "External dataset-grant ownership must not exclude identities from query execution grants."
  }
}

run "reject_external_reader_without_existing_grant" {
  command = plan

  variables {
    externally_managed_dataset_reader_emails = ["node-a@identity-project.iam.gserviceaccount.com"]
  }

  expect_failures = [data.google_bigquery_dataset.billing]
}

run "reject_external_reader_without_matching_direct_read_role" {
  command = plan

  variables {
    externally_managed_dataset_reader_emails = ["node-a@identity-project.iam.gserviceaccount.com"]
  }

  override_data {
    target = data.google_bigquery_dataset.billing
    values = {
      id                               = "projects/example-query-project/datasets/billing_export"
      project                          = "example-query-project"
      dataset_id                       = "billing_export"
      location                         = "EU"
      default_table_expiration_ms      = 0
      default_partition_expiration_ms  = 0
      default_encryption_configuration = []
      access = [
        {
          role          = "READER"
          user_by_email = "other-node@identity-project.iam.gserviceaccount.com"
          condition     = []
        },
        {
          role          = "roles/bigquery.metadataViewer"
          user_by_email = "node-a@identity-project.iam.gserviceaccount.com"
          condition     = []
        },
        {
          role           = "READER"
          user_by_email  = ""
          group_by_email = "node-a@identity-project.iam.gserviceaccount.com"
          condition      = []
        },
      ]
    }
  }

  expect_failures = [data.google_bigquery_dataset.billing]
}

run "reject_conditional_external_reader_even_when_expression_is_true" {
  command = plan

  variables {
    externally_managed_dataset_reader_emails = ["node-a@identity-project.iam.gserviceaccount.com"]
  }

  override_data {
    target = data.google_bigquery_dataset.billing
    values = {
      id                               = "projects/example-query-project/datasets/billing_export"
      project                          = "example-query-project"
      dataset_id                       = "billing_export"
      location                         = "EU"
      default_table_expiration_ms      = 0
      default_partition_expiration_ms  = 0
      default_encryption_configuration = []
      access = [{
        role          = "READER"
        user_by_email = "node-a@identity-project.iam.gserviceaccount.com"
        condition = [{
          title      = "conditional_read"
          expression = "true"
        }]
      }]
    }
  }

  expect_failures = [data.google_bigquery_dataset.billing]
}

run "reject_existing_customer_managed_encryption" {
  command = plan

  override_data {
    target = data.google_bigquery_dataset.billing
    values = {
      id                              = "projects/example-query-project/datasets/billing_export"
      project                         = "example-query-project"
      dataset_id                      = "billing_export"
      location                        = "EU"
      default_table_expiration_ms     = 0
      default_partition_expiration_ms = 0
      default_encryption_configuration = [{
        kms_key_name = "projects/example-query-project/locations/europe-west1/keyRings/billing/cryptoKeys/export"
      }]
      access = []
    }
  }

  expect_failures = [data.google_bigquery_dataset.billing]
}

run "reject_existing_default_table_expiration" {
  command = plan

  override_data {
    target = data.google_bigquery_dataset.billing
    values = {
      id                               = "projects/example-query-project/datasets/billing_export"
      project                          = "example-query-project"
      dataset_id                       = "billing_export"
      location                         = "EU"
      default_table_expiration_ms      = 3600000
      default_partition_expiration_ms  = 0
      default_encryption_configuration = []
      access                           = []
    }
  }

  expect_failures = [data.google_bigquery_dataset.billing]
}

run "reject_existing_default_partition_expiration" {
  command = plan

  override_data {
    target = data.google_bigquery_dataset.billing
    values = {
      id                               = "projects/example-query-project/datasets/billing_export"
      project                          = "example-query-project"
      dataset_id                       = "billing_export"
      location                         = "EU"
      default_table_expiration_ms      = 0
      default_partition_expiration_ms  = 3600000
      default_encryption_configuration = []
      access                           = []
    }
  }

  expect_failures = [data.google_bigquery_dataset.billing]
}

run "reject_observed_location_without_billing_export_support" {
  command = plan

  override_data {
    target = data.google_bigquery_dataset.billing
    values = {
      id                               = "projects/example-query-project/datasets/billing_export"
      project                          = "example-query-project"
      dataset_id                       = "billing_export"
      location                         = "europe-west12"
      default_table_expiration_ms      = 0
      default_partition_expiration_ms  = 0
      default_encryption_configuration = []
      access                           = []
    }
  }

  expect_failures = [data.google_bigquery_dataset.billing]
}
