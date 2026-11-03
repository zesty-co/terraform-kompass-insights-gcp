# Zesty Kompass Insights GCP Module

This module prepares BigQuery permissions and a Cloud Billing export dataset for Kompass Insights
on GKE. It uses existing node service accounts from one or more clusters.

The module grants query-job access and dataset read access. It can also create the dataset.
You must enable the billing export in Google Cloud Console after the dataset is ready.

Start with the [Terraform onboarding guide](examples/quick-start/README.md).
It explains how to find each value, assign grant ownership, and pass outputs to Spoke.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Installation instructions](#installation-instructions)
- [Deployed Resources](#deployed-resources)
- [Advanced Usage](#advanced-usage)
- [Verification](#verification)
- [API Reference](#api-reference)

## Prerequisites

- Terraform `>= 1.9.0` and `hashicorp/google ~> 8.9`. Tests use Google provider `8.9.0`.
- Google Cloud projects with billing enabled. Link the dataset project to the intended billing
  account.
- At least one existing GKE node service account email. Check that each email belongs to the
  intended nodes before you apply the module.
- An existing dataset, or permission to create one in a [supported billing export location].
- Operator credentials with permission to read project details, enable APIs, and manage the
  requested grants.
- Billing account and dataset permissions for the [manual export setup].

The Terraform operator needs permissions for these operations:

| Service | Operations |
| --- | --- |
| Resource Manager | `resourcemanager.projects.get`, `resourcemanager.projects.getIamPolicy`, and `resourcemanager.projects.setIamPolicy` |
| Service Usage | Enable and read services, and read operations: `serviceusage.services.enable`, `serviceusage.services.get`, and `serviceusage.operations.get` |
| BigQuery | Read dataset settings and update access: `bigquery.datasets.get` and `bigquery.datasets.update`; also `bigquery.datasets.create` when creation is enabled |

Select roles that cover these operations for the applicable projects and dataset.
The operator needs these permissions in addition to the node service account grants.

For local use, configure [Application Default Credentials (ADC)]:

```bash
gcloud auth application-default login
```

This command configures credentials for Terraform. It does not configure authentication inside
the GKE workload.

## Quick Start

Use the [quick-start guide](examples/quick-start/README.md) to find values in Console or with
read-only commands. Copy its example configuration, fill in your values, and apply Terraform.
The guide also covers the current checkout's billing-table output and Spoke configuration.

Use one Terraform state for a shared billing destination and its module-managed grants.
Supply all cluster node identities in `service_account_emails`.

## Installation instructions

Create a Terraform configuration with the Google provider and the module call below.
Replace all example values with your project, dataset, and existing node service account emails.
This example reads an existing dataset.

```hcl
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.9"
    }
  }
}

provider "google" {
  project = "example-billing-project"
}

module "kompass_insights" {
  source = "git::https://github.com/zesty-co/terraform-kompass-insights-gcp.git?ref=v1.0.0"

  dataset_id = "billing_export"
  service_account_emails = [
    "node-sa@example-cluster-a.iam.gserviceaccount.com",
    "node-sa@example-cluster-b.iam.gserviceaccount.com",
  ]
}
```

This example uses published `v1.0.0` for dataset and grant setup.
The new billing-account input and expected-table output are not in that release.
Use the [local quick-start](examples/quick-start/README.md#prerequisites-and-release-status)
for those features and the new Spoke billing values.
Public client rollout requires compatible published Terraform, agent, Insights chart, and Spoke
releases. Pin their actual compatible versions after release.

Before the first apply, identify any existing grants for the supplied accounts.
Use [external reader ownership](#use-existing-dataset-reader-grants) for existing dataset grants.
Transfer any query grants owned by another state as described under [query grant ownership].

Run these commands from your configuration directory:

```bash
terraform init
terraform plan -out=tfplan
```

Examine the plan. Then apply it:

```bash
terraform apply tfplan
```

### Enable the billing export

1. Open **Billing > Billing export** in Google Cloud Console.
2. Select the intended billing account.
3. On **BigQuery export**, enable **Detailed usage cost** export.
4. Select the module's `dataset_project_id` and `dataset_id`.
5. Save the export settings.

Follow the [manual export setup] for the required roles and export options.
Google creates the billing table and adds its export writer identity to the dataset.
Keep that writer's access. The first export can take time.

The module returns `query_project_id`, `dataset_project_id`, `dataset_id`, `dataset_location`,
and `service_account_emails`. The location comes from the selected dataset
([outputs.tf:19](outputs.tf#L19)).

### Expected export table in the current checkout

The following input and output are included in this module source, but not in `v1.0.0`.
Use the [local example](examples/quick-start/README.md#installation-instructions) to try them.
Optionally add the intended billing account ID to that module call:

```hcl
billing_account_id = "012345-ABCDEF-678901"
```

The `expected_export_table` output identifies the expected detailed export in the dataset project
([outputs.tf:30](outputs.tf#L30)). For the example dataset, its value is:

```text
example-billing-project.billing_export.gcp_billing_export_resource_v1_012345_ABCDEF_678901
```

The output is `null` when `billing_account_id` is omitted. The name is derived from the supplied ID.
Runtime verification must confirm the intended account, table, and data before the agent uses them.
The [Spoke values](examples/quick-start/README.md#configure-your-existing-spoke-deployment)
map these outputs to the agent settings. The billing account ID is not an agent setting.

## Deployed Resources

| Resource | Behavior |
| --- | --- |
| `google_project_service` | Enables the BigQuery API once per distinct query or dataset project. Uses `disable_on_destroy = false`. |
| `google_project_iam_member` | Grants `roles/bigquery.jobUser` in the query project to each supplied service account. |
| `google_bigquery_dataset_access` | Adds a direct `READER` grant for each supplied account outside the external-reader set. Keeps other consumers' grants and the billing writer's grant. |
| `google_bigquery_dataset.billing` | Creates a dataset only when `create_dataset = true`. Uses Google-managed encryption and no default table or partition expiration. |
| `data.google_bigquery_dataset.billing` | Reads the selected dataset after optional creation and checks its settings and external grants. |

The module rejects datasets with unsupported billing export locations, default CMEK encryption,
or nonzero default table or partition expiration. The CMEK restriction is a module constraint.
For external reader ownership, the module also requires a direct, unconditional `READER`,
`WRITER`, or `OWNER` grant for each selected account.

With `create_dataset = false`, the module reads dataset settings without managing them.
It still manages the requested grants.

The managed dataset ignores changes to `access`, `default_table_expiration_ms`,
`default_partition_expiration_ms`, and `default_encryption_configuration`.
Creation uses Google-managed encryption with no default expiration.
The dataset check reports incompatible existing, imported, or changed settings without resetting
them. These checks apply to managed datasets too.
See [main.tf:33](main.tf#L33) for lifecycle settings and [main.tf:59](main.tf#L59) for checks.

The module accepts the supplied identities. It does not check their attachment to GKE nodes.
It creates no service accounts or keys and changes no GKE configuration.
It does not install Kompass Insights or implement runtime billing-data ingestion.

## Advanced Usage

### Select projects and dataset settings

`query_project_id = null` uses the Google provider's project through `data.google_project`.
`dataset_project_id = null` uses the resolved query project ([main.tf:1](main.tf#L1)).
Set either value explicitly when the projects differ.

`create_dataset` defaults to `false`. To create a dataset, add these arguments to the module call:

```hcl
create_dataset   = true
dataset_location = "US"
labels = {
  purpose = "billing-export"
}
```

`dataset_location` defaults to `null` and is required only when `create_dataset = true`.
Use `US`, `EU`, or a region in Google's [supported billing export location] list.
The dataset location cannot change after creation.
`labels` defaults to `{}` and applies only to a dataset that this module creates or imports.
For an externally managed dataset, keep `dataset_location = null` and `labels = {}`.
See [variables.tf:55](variables.tf#L55) and [variables.tf:92](variables.tf#L92).

### Use existing dataset reader grants

The `externally_managed_dataset_reader_emails` input defaults to an empty set.
It must be a subset of `service_account_emails`.
For an account with an existing dataset grant, add this argument to the module call:

```hcl
externally_managed_dataset_reader_emails = [
  "node-sa@example-cluster-a.iam.gserviceaccount.com",
]
```

The module checks that each listed account has a direct, unconditional `READER`, `WRITER`, or
`OWNER` grant. Group membership, inherited access, and conditional grants do not meet this check.
The external owner keeps control of these grants. The module leaves them in place on removal.

Google provider `8.9.0` does not support imports for `google_bigquery_dataset_access`.
Creating a duplicate access entry fails. Importing a dataset does not import its reader grants.
Use the explicit external-reader set to keep grant ownership with its current owner.
Do not derive resource `for_each` keys from the live access list; those keys can change after apply.

Before moving a module-managed reader to external ownership, move its state ownership without
deleting the grant. Use a `removed` block with `destroy = false` where applicable.
For one indexed grant, use a carefully selected `terraform state rm` operation.
See [Remove a resource from state] for the supported procedure.
Back up state and coordinate the configuration change with the new owner.
Adding an email to the external-reader set alone plans deletion of its module-managed grant.

### Query grant ownership

The module manages every requested `roles/bigquery.jobUser` grant, including accounts in the
external-reader set. The external-reader input affects dataset access only.

Applying the module also takes ownership of matching existing query grants.
Transfer ownership from another Terraform state first.
For explicit adoption before apply, the provider supports [project IAM member imports]
([main.tf:100](main.tf#L100)):

```bash
terraform import \
  'module.kompass_insights.google_project_iam_member.billing_query["node-sa@example-cluster-a.iam.gserviceaccount.com"]' \
  'example-billing-project roles/bigquery.jobUser serviceAccount:node-sa@example-cluster-a.iam.gserviceaccount.com'
```

The import ID contains the query project, role, and `serviceAccount:EMAIL`, with spaces between
them.
Do not manage the same grant from two states or an authoritative project IAM binding.

### Import an existing dataset

Keep `create_dataset = false` if another owner manages the dataset settings.
To put dataset management under this module:

1. Read the existing location, encryption, expiration, labels, and access list.
2. Make sure that the settings meet this module's dataset constraints.
3. Move ownership from any previous state without deleting the dataset.
4. Set `create_dataset = true` and the actual `dataset_location`.
5. Set `labels` to the values that this module must manage.
6. Put existing reader grants in the external-reader set.
7. Import the dataset into the module resource:

```bash
terraform import \
  'module.kompass_insights.google_bigquery_dataset.billing[0]' \
  'projects/example-billing-project/datasets/billing_export'
```

8. Examine a new plan before apply. Stop if it changes settings outside the intended import.

This import puts the dataset resource under module management. It does not import dataset reader
grants.
The selected-dataset check does not replace inspection before import and apply.

### Removal and changes in ownership

The managed dataset uses `deletion_policy = "ABANDON"` and `delete_contents_on_destroy = false`.
Removing it from the configuration keeps the dataset and its data.
The module revokes its query grants and dataset reader grants when their resources are removed.
External reader grants and enabled APIs remain.

Changing `create_dataset` from `true` to `false` keeps the dataset and ends module ownership of
its settings. Changing it back to `true` requires a dataset import before apply.
Dataset ownership does not control reader-grant ownership ([main.tf:110](main.tf#L110)).

## Verification

From the repository root, run the local checks with Terraform, `terraform-docs`, and Make available:

```bash
make check
```

This command checks formatting, validates both modules, runs native mocked tests, and checks
generated documentation ([Makefile](Makefile)). The mocked tests verify the module contract only.
They do not verify provider-project discovery, live grant preservation, dataset imports, or actual
billing export.

### Live acceptance

Use your own authorized sandbox for live checks. Replace all example values first.
The Terraform commands below can change cloud resources and access.
Authenticate the Google Cloud CLI too; the ADC login does not authenticate `gcloud`.

Before apply, examine an existing destination and its query-project policy:

```bash
bq --format=prettyjson show 'example-billing-project:billing_export'
gcloud projects get-iam-policy example-billing-project --format=json
```

Record the dataset settings, other consumers, external readers, and billing writer.
If the query and dataset projects differ, use the query project in the IAM command.
Apply the sandbox configuration with the installation commands above.
Repeat the read commands to check that only the requested grants changed.
Run `terraform plan` again to check for unexpected changes.

For dataset adoption, test the import procedure with a compatible sandbox dataset.
Make sure that the plan keeps its settings, access list, and existing tables.
After manual export setup, examine the tables:

```bash
bq --format=prettyjson ls 'example-billing-project:billing_export'
```

Check the export table and data in BigQuery. A table listing alone does not show data ingestion.
Test workload access later from the actual runtime identity.
Check ADC identity, OAuth scopes, network access, query-job creation, and access to the actual
table.
A successful permission grant does not show runtime access.

For removal acceptance, use an isolated state with only the sandbox module:

```bash
terraform plan -destroy -out=destroy.tfplan
```

Examine the plan before you run `terraform apply destroy.tfplan`.
Repeat the read commands after removal.
Check dataset retention, module-managed grant removal, and external-grant preservation.
Check that the BigQuery API remains enabled in each project.
These live checks require sandbox credentials and resources.
The mocked tests do not perform them.

## API Reference

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 8.9 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | ~> 8.9 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [google_bigquery_dataset.billing](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/bigquery_dataset) | resource |
| [google_bigquery_dataset_access.billing_read](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/bigquery_dataset_access) | resource |
| [google_project_iam_member.billing_query](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_service.bigquery](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_service) | resource |
| [google_bigquery_dataset.billing](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/bigquery_dataset) | data source |
| [google_project.query](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/project) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_billing_account_id"></a> [billing\_account\_id](#input\_billing\_account\_id) | Optional billing account ID used to derive the expected detailed export table name. | `string` | `null` | no |
| <a name="input_create_dataset"></a> [create\_dataset](#input\_create\_dataset) | Manage the dataset lifecycle. Set false to reference an externally managed dataset. | `bool` | `false` | no |
| <a name="input_dataset_id"></a> [dataset\_id](#input\_dataset\_id) | ID of the dataset that receives the detailed billing export. | `string` | n/a | yes |
| <a name="input_dataset_location"></a> [dataset\_location](#input\_dataset\_location) | Billing-export location for a managed dataset. Existing datasets report their actual location. | `string` | `null` | no |
| <a name="input_dataset_project_id"></a> [dataset\_project\_id](#input\_dataset\_project\_id) | Project that contains the billing dataset. Defaults to the query project. | `string` | `null` | no |
| <a name="input_externally_managed_dataset_reader_emails"></a> [externally\_managed\_dataset\_reader\_emails](#input\_externally\_managed\_dataset\_reader\_emails) | Supplied identities whose direct dataset read grants stay with their existing owner. | `set(string)` | `[]` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels for a dataset managed by this module. | `map(string)` | `{}` | no |
| <a name="input_query_project_id"></a> [query\_project\_id](#input\_query\_project\_id) | Project where queries run. Defaults to the Google provider project. | `string` | `null` | no |
| <a name="input_service_account_emails"></a> [service\_account\_emails](#input\_service\_account\_emails) | Existing node service accounts that need billing access. Shared identities need one entry. | `set(string)` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_dataset_id"></a> [dataset\_id](#output\_dataset\_id) | Selected billing dataset ID. The billing administrator activates detailed export here. |
| <a name="output_dataset_location"></a> [dataset\_location](#output\_dataset\_location) | Actual location of the billing dataset, for subsequent runtime queries. |
| <a name="output_dataset_project_id"></a> [dataset\_project\_id](#output\_dataset\_project\_id) | Project that contains the selected billing dataset. |
| <a name="output_expected_export_table"></a> [expected\_export\_table](#output\_expected\_export\_table) | Expected fully qualified detailed export table, or null without a billing account ID. Does not verify export activation or data availability. |
| <a name="output_query_project_id"></a> [query\_project\_id](#output\_query\_project\_id) | Project where the supplied identities receive query execution permission. |
| <a name="output_service_account_emails"></a> [service\_account\_emails](#output\_service\_account\_emails) | Supplied runtime identities. Permission setup does not establish working runtime access. |
<!-- END_TF_DOCS -->

[Application Default Credentials (ADC)]: https://cloud.google.com/docs/authentication/set-up-adc-local-dev-environment
[manual export setup]: https://cloud.google.com/billing/docs/how-to/export-data-bigquery-setup
[supported billing export location]: https://cloud.google.com/billing/docs/how-to/export-data-bigquery-setup#supported-dataset-locations
[query grant ownership]: #query-grant-ownership
[project IAM member imports]: https://registry.terraform.io/providers/hashicorp/google/8.9.0/docs/resources/google_project_iam#google_project_iam_member
[Remove a resource from state]: https://developer.hashicorp.com/terraform/language/state/remove
