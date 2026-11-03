# Quick Start

This example prepares a BigQuery billing export dataset and permissions for existing GKE node
service accounts. It uses the local module with `source = "../.."` ([main.tf:1](main.tf#L1)).
It does not install Kompass Insights or enable the billing export.

## Prerequisites

- Terraform `>= 1.9.0` and `hashicorp/google ~> 8.9`, tested with provider `8.9.0`.
- Google Cloud projects with billing enabled. Link the dataset project to the intended billing
  account.
- Existing node service account emails and an existing compatible dataset, unless creation is
  enabled.
- Operator permissions from the [module prerequisites](../../README.md#prerequisites).
- One state that owns the shared destination and its module-managed grants across all clusters.

For local use, configure Application Default Credentials:

```bash
gcloud auth application-default login
```

These are operator credentials for Terraform. Check workload authentication after setup.

## Installation instructions

From the repository root, change to the example directory:

```bash
cd examples/quick-start
```

Create `terraform.tfvars` with your values. This configuration uses an existing dataset:

```hcl
project_id = "example-billing-project"
dataset_id = "billing_export"
service_account_emails = [
  "node-sa@example-cluster-a.iam.gserviceaccount.com",
  "node-sa@example-cluster-b.iam.gserviceaccount.com",
]
```

`project_id` selects the Google provider project ([providers.tf:1](providers.tf#L1)).
The example forwards the other module inputs.
When `query_project_id` is `null`, the module uses the provider project.
When `dataset_project_id` is `null`, the module uses the query project.

Optional values have these defaults:

| Input | Default | Use |
| --- | --- | --- |
| `query_project_id` | `null` | Project where the supplied accounts can create query jobs. |
| `dataset_project_id` | `null` | Project that contains the billing dataset. |
| `create_dataset` | `false` | Create or import the dataset under module ownership. |
| `dataset_location` | `null` | Required when creation is enabled; use a supported billing export location. |
| `externally_managed_dataset_reader_emails` | `[]` | Supplied accounts whose existing direct dataset grants have another owner. |
| `labels` | `{}` | Labels for a dataset that the module creates or imports. |

To create a new dataset, add these values to `terraform.tfvars`:

```hcl
create_dataset   = true
dataset_location = "US"
```

Use `US`, `EU`, or a region in Google's [supported billing export locations].
The module requires Google-managed encryption and no default table or partition expiration.
The returned location always comes from the actual dataset.
For an externally managed dataset, keep `dataset_location = null` and `labels = {}`.

Before apply, examine
[existing grant ownership](../../README.md#use-existing-dataset-reader-grants).
For existing dataset grants, set `externally_managed_dataset_reader_emails` to the applicable
subset of `service_account_emails`. Each account must have a direct, unconditional `READER`,
`WRITER`, or `OWNER` grant. Query grants remain module-managed.
Transfer query-grant ownership from another state before this module manages those grants.

Initialize Terraform and create a plan:

```bash
terraform init
terraform plan -out=tfplan
```

Examine the plan. Then apply it:

```bash
terraform apply tfplan
terraform output
```

## Enable the billing export

1. Open **Billing > Billing export** in Google Cloud Console.
2. Select the intended billing account.
3. On **BigQuery export**, enable **Detailed usage cost** export.
4. Select the returned `dataset_project_id` and `dataset_id`.
5. Save the export settings.

See Google's [billing export setup] for roles and export options.
Google creates the table and adds the billing writer's dataset access.
Keep that writer's access. Exported data can take time to appear.

The `billing_access` output contains the projects, dataset, actual location, and supplied accounts
([outputs.tf:1](outputs.tf#L1)). It does not identify an export table or show that data is
available.
Follow the [live acceptance steps](../../README.md#live-acceptance) in an authorized sandbox.
Check runtime ADC identity, OAuth scopes, network access, and query access after setup.

## Removal and ownership

Removing the module keeps the dataset and its data. It revokes module-managed query and reader
grants. External reader grants and enabled APIs remain.

Before moving a managed reader to external ownership, move its state ownership without
deleting the grant. Changing only the external-reader set plans grant deletion.
See [grant ownership](../../README.md#use-existing-dataset-reader-grants)
for the state procedure.

To import a dataset, follow the
[dataset import procedure](../../README.md#import-an-existing-dataset).
Dataset imports do not import reader grants.
After changing `create_dataset` from `true` to `false`, import the dataset before setting it back
to `true`.

## API Reference

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 8.9 |

## Providers

No providers.

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_kompass_insights"></a> [kompass\_insights](#module\_kompass\_insights) | ../.. | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_create_dataset"></a> [create\_dataset](#input\_create\_dataset) | Create or adopt a managed dataset instead of referencing an external dataset. | `bool` | `false` | no |
| <a name="input_dataset_id"></a> [dataset\_id](#input\_dataset\_id) | Dataset that receives the detailed billing export. | `string` | n/a | yes |
| <a name="input_dataset_location"></a> [dataset\_location](#input\_dataset\_location) | Required location when create\_dataset is true. | `string` | `null` | no |
| <a name="input_dataset_project_id"></a> [dataset\_project\_id](#input\_dataset\_project\_id) | Optional billing dataset project override. | `string` | `null` | no |
| <a name="input_externally_managed_dataset_reader_emails"></a> [externally\_managed\_dataset\_reader\_emails](#input\_externally\_managed\_dataset\_reader\_emails) | Supplied identities whose existing direct dataset read grants stay externally managed. | `set(string)` | `[]` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels for a managed dataset. | `map(string)` | `{}` | no |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | Default Google provider project. Queries and the dataset use this project unless overridden. | `string` | n/a | yes |
| <a name="input_query_project_id"></a> [query\_project\_id](#input\_query\_project\_id) | Optional query project override. | `string` | `null` | no |
| <a name="input_service_account_emails"></a> [service\_account\_emails](#input\_service\_account\_emails) | Existing node service accounts that need billing access. | `set(string)` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_billing_access"></a> [billing\_access](#output\_billing\_access) | Billing destination and identities for export activation and subsequent runtime verification. |
<!-- END_TF_DOCS -->

[supported billing export locations]: https://cloud.google.com/billing/docs/how-to/export-data-bigquery-setup#supported-dataset-locations
[billing export setup]: https://cloud.google.com/billing/docs/how-to/export-data-bigquery-setup
