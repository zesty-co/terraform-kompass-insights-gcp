mock_provider "google" {
  source = "./tests/mocks"
}

variables {
  query_project_id       = "example-query-project"
  dataset_id             = "billing_export"
  service_account_emails = ["node-a@identity-project.iam.gserviceaccount.com"]
}

run "require_location_when_creating_dataset" {
  command = plan

  variables {
    create_dataset = true
  }

  expect_failures = [var.dataset_location]
}

run "reject_creation_location_without_billing_export_support" {
  command = plan

  variables {
    create_dataset   = true
    dataset_location = "europe-west12"
  }

  expect_failures = [var.dataset_location]
}

run "reject_location_override_for_existing_dataset" {
  command = plan

  variables {
    dataset_location = "US"
  }

  expect_failures = [var.dataset_location]
}

run "reject_dataset_id_above_1024_characters" {
  command = plan

  variables {
    dataset_id = format("%01025d", 0)
  }

  expect_failures = [var.dataset_id]
}

run "reject_non_service_account_identity" {
  command = plan

  variables {
    service_account_emails = ["analyst@example.com"]
  }

  expect_failures = [var.service_account_emails]
}

run "reject_empty_identity_set" {
  command = plan

  variables {
    service_account_emails = []
  }

  expect_failures = [var.service_account_emails]
}

run "reject_external_reader_outside_supplied_identities" {
  command = plan

  variables {
    externally_managed_dataset_reader_emails = ["unknown-node@identity-project.iam.gserviceaccount.com"]
  }

  expect_failures = [var.externally_managed_dataset_reader_emails]
}

run "reject_malformed_billing_account_id" {
  command = plan

  variables {
    billing_account_id = "012345_ABCDEF_678901"
  }

  expect_failures = [var.billing_account_id]
}
