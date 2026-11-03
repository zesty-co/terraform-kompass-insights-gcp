# Quick Start

Use Terraform to prepare billing access for existing GKE node service accounts.
Then pass its outputs to your existing Spoke deployment.

## Values worksheet

Complete this worksheet first. Replace all example values with values from your environment.

| Value | Default | Where to get it |
| --- | --- | --- |
| Google provider project / wrapper `project_id` | Required | Console project picker: copy the project **ID** for query jobs. |
| `dataset_id` | Required | Intended account's **Billing export > BigQuery export > Detailed usage cost** destination. Use only the dataset ID. |
| `billing_account_id` | `null` | **Billing > Manage billing accounts**: copy the intended account ID. Required for the table-output example below. |
| `service_account_emails` | Required | Selected clusters' node-pool service accounts; see [node identities](#find-node-service-accounts). |
| `externally_managed_dataset_reader_emails` | `[]` | Existing direct grants with another owner; see [grant ownership](#determine-grant-ownership). |
| `query_project_id` | `null` | Optional query-project ID from the Console project picker. Null uses the provider project. |
| `dataset_project_id` | `null` | Export destination's project ID. Null uses the resolved query project. |
| `create_dataset` | `false` | Choose `true` only for a new dataset or a planned [dataset import](../../README.md#import-an-existing-dataset). |
| `dataset_location` | `null` | For a new dataset, choose an explicit [supported location](#select-the-billing-destination). |
| `labels` | `{}` | Your labels for a managed dataset. Keep `{}` for an externally managed dataset. |

`project_id` belongs to this example wrapper. It sets the Google provider project
([providers.tf:1](providers.tf#L1)). The root module has no `project_id` input.
For the root module, set the Google provider's `project` argument directly.
By default, both query jobs and the dataset use that provider project
([../../main.tf:1](../../main.tf#L1)).
If you set a different `query_project_id`, also set `dataset_project_id` to the export destination.
Otherwise, the dataset project follows the query-project override.

## Prerequisites and release status

- Terraform `>= 1.9.0` and `hashicorp/google ~> 8.9`, tested with provider `8.9.0`.
- Google Cloud CLI with `gcloud` and `bq`, authenticated for the read-only discovery commands.
- Google Cloud projects with billing enabled. Link the dataset project to the intended account.
- Read access to cluster settings, node-pool settings, project billing details, and the complete
  dataset access list.
- Operator permissions from the [module prerequisites](../../README.md#prerequisites).
- One persistent Terraform state for the shared destination and its module-managed grants.

Terraform `v1.1.0` includes the billing-account input and expected-table output.
The [installation example](../../README.md#installation-instructions) uses that published version.
This example uses the local module with `source = "../.."` ([main.tf:1](main.tf#L1)).
Use a checkout of `v1.1.0` or a compatible later release for this flow.
Public client rollout also requires compatible agent, Insights chart, and Spoke releases.
Use compatible checked-out chart and agent code until those releases are available.

For local discovery, sign in with the Google Cloud CLI:

```bash
gcloud auth login
```

Discovery commands use this `gcloud` account. Terraform uses operator
[Application Default Credentials (ADC)]. For local Terraform, configure ADC:

```bash
gcloud auth application-default login
```

This login does not authenticate the `gcloud` account or the agent.
Check `GOOGLE_APPLICATION_CREDENTIALS` if Terraform selects unexpected ADC.

## Find your values

### Select the billing destination

1. Open **Billing > Manage billing accounts** in Console.
2. Select the intended account and copy its billing account ID.
3. Open **Billing export > BigQuery export**.
4. Read the **Detailed usage cost** destination. Copy its project ID and dataset ID.

Use the detailed export, not the standard usage export.
If no detailed export is active, choose an existing compatible dataset or a new dataset ID.
For an existing dataset, open **BigQuery > Explorer > project > dataset > Details**.
Read its location, encryption, and expiration settings.

Set these shell values from your worksheet:

```bash
DATASET_PROJECT_ID="example-billing-project"
DATASET_ID="billing_export"
QUERY_PROJECT_ID="example-billing-project"

gcloud billing projects describe "$DATASET_PROJECT_ID" --format=json
```

The [billing-project command] must return `billingEnabled: true`.
Its `billingAccountName` must end with the intended billing account ID.
The destination project can differ from the cluster projects.

If query jobs use another project, check that it also has billing enabled:

```bash
gcloud billing projects describe "$QUERY_PROJECT_ID" --format=json
```

The query project's billing account can differ from the export's billing account.

For an existing dataset, use [the dataset show command] to read its settings and access list:

```bash
bq --project_id="$DATASET_PROJECT_ID" --format=prettyjson show \
  "${DATASET_PROJECT_ID}:${DATASET_ID}"
```

Read `location`, `access`, `defaultEncryptionConfiguration`, `defaultTableExpirationMs`, and
`defaultPartitionExpirationMs`.
The module requires Google-managed encryption and no default table or partition expiration
([../../main.tf:65](../../main.tf#L65)).
For an externally managed dataset, keep `dataset_location = null` and `labels = {}`.

For a new dataset, set `create_dataset = true` and choose `dataset_location` explicitly.
Use `US`, `EU`, or a region in Google's [supported billing export locations].
Check that the location is also in the module's list
([../../main.tf:14](../../main.tf#L14)). The dataset location cannot change after creation.

### Find node service accounts

In Console, select each cluster project under **Kubernetes Engine > Clusters**.
Open the cluster's **Nodes** tab and select a node pool.
Read the service account in the node pool's security settings.

Use the [cluster list command] to get cluster names and locations for each project:

```bash
CLUSTER_PROJECT_ID="cluster-a-project"
gcloud container clusters list --project="$CLUSTER_PROJECT_ID" \
  --format='table(name,location)'
```

Copy a cluster name and its location into the [node-pool list command].
Use the listed region or zone as `CLUSTER_LOCATION`:

```bash
CLUSTER_NAME="example-cluster"
CLUSTER_LOCATION="us-central1"
gcloud container node-pools list --project="$CLUSTER_PROJECT_ID" \
  --cluster="$CLUSTER_NAME" --location="$CLUSTER_LOCATION" \
  --format='table(name,config.serviceAccount)'
```

If `config.serviceAccount` is `default`, resolve the cluster project's number with
the [project describe command]:

```bash
PROJECT_NUMBER="$(gcloud projects describe "$CLUSTER_PROJECT_ID" \
  --format='value(projectNumber)')"
printf '%s-compute@developer.gserviceaccount.com\n' "$PROJECT_NUMBER"
```

Use that full email in Terraform, not `default`.
Repeat these steps for all selected cluster projects and node pools.
Include the pools on which Insights can run under its scheduling rules.
If pools or clusters share an account, include its email only once in `service_account_emails`.
Node-pool settings show configured node identities. They do not prove which identity the agent
uses at runtime.

### Determine grant ownership

Classify existing grants before the first apply.
Open **BigQuery > Explorer > dataset > Sharing > Permissions**.
Use the complete `access` list from `bq show` to identify direct grants.
If your account cannot read the complete list, obtain a complete read from the dataset owner.
A missing or partial list does not prove that no grants exist.

An existing direct grant looks like this JSON fragment:

```json
{
  "access": [
    {
      "role": "READER",
      "userByEmail": "gke-nodes@cluster-a-project.iam.gserviceaccount.com"
    }
  ]
}
```

Add an email to `externally_managed_dataset_reader_emails` only when these conditions apply:

- The email is also in `service_account_emails`.
- A direct `access` entry has that `userByEmail` and role `READER`, `WRITER`, or `OWNER`.
- The entry has no condition, and its existing owner will keep control of it.

Inherited access, group membership, and conditional grants do not qualify
([../../main.tf:84](../../main.tf#L84)). The module adds direct readers for the other emails.
Keep the billing export writer's access.

Keep the same ownership settings and Terraform state on later runs.
A `READER` grant that Terraform created must stay module-managed when it appears in `bq show`.
Adding that email to the external-reader set can revoke the grant.
For an ownership transfer, follow [the existing grant procedure][reader ownership].

Also examine the query project's IAM policy:

```bash
gcloud projects get-iam-policy "$QUERY_PROJECT_ID" --format=json
```

This state manages every selected account's query-project `roles/bigquery.jobUser` grant.
This includes accounts in the external-reader set.
Transfer ownership from other states before apply; see [query grant ownership].

## Installation instructions

From the checked-out repository root, copy the example variable file:

```bash
cd examples/quick-start
cp terraform.tfvars.example terraform.tfvars
```

Fill `terraform.tfvars` with your worksheet values. Use one of these complete examples.
Both examples use the provider project for query jobs and the dataset.
For a separate query project, set both `query_project_id` and `dataset_project_id` explicitly.

### Existing dataset

This example assumes cluster A's account has an existing direct grant with another owner.
Use `[]` for external readers if no selected account has such a grant.

```hcl
project_id         = "example-billing-project"
query_project_id   = null
dataset_project_id = null
dataset_id         = "billing_export"
billing_account_id = "012345-ABCDEF-678901"
create_dataset     = false
dataset_location   = null
labels             = {}

service_account_emails = [
  "gke-nodes@cluster-a-project.iam.gserviceaccount.com",
  "gke-nodes@cluster-b-project.iam.gserviceaccount.com",
]
externally_managed_dataset_reader_emails = [
  "gke-nodes@cluster-a-project.iam.gserviceaccount.com",
]
```

### New dataset

Choose an unused dataset ID and a supported location. `US` is an example, not a location default.

```hcl
project_id         = "example-billing-project"
query_project_id   = null
dataset_project_id = null
dataset_id         = "billing_export"
billing_account_id = "012345-ABCDEF-678901"
create_dataset     = true
dataset_location   = "US"
labels             = {}

service_account_emails = [
  "gke-nodes@cluster-a-project.iam.gserviceaccount.com",
  "gke-nodes@cluster-b-project.iam.gserviceaccount.com",
]
externally_managed_dataset_reader_emails = []
```

### Apply and keep state

Initialize Terraform and save a plan:

```bash
terraform init
terraform plan -out=tfplan
```

Examine the destination and grant changes in the plan. Then apply the saved plan:

```bash
terraform apply tfplan
terraform output -json billing_access
```

Keep the configuration and state for later changes. Use your team's persistent backend for shared
deployments. Keep one state owner for these grants across all selected clusters.

`billing_access` contains the projects, dataset, actual location, supplied accounts, and expected
export table ([outputs.tf:1](outputs.tf#L1)).
`billing_account_id` is optional for permission setup.
It is required for the table-output flow below.
Without it, `expected_export_table` is `null`.
With it, the module derives the fully qualified detailed export table name
([../../outputs.tf:30](../../outputs.tf#L30)).
This name does not confirm that the table exists or contains data for the intended account.

## Enable the billing export

Terraform prepares access. The billing administrator activates the export in Console.
If detailed export is already active, verify its destination. Otherwise:

1. Open **Billing > Billing export** for the intended account.
2. On **BigQuery export**, enable **Detailed usage cost** export.
3. Select the returned `dataset_project_id` and `dataset_id`.
4. Save the export settings.

See Google's [billing export setup] for roles and export options.
Google creates the table and adds the billing writer's dataset access.
Keep that writer's access. Exported data can take time to appear.

List the tables after export starts:

```bash
bq --project_id="$DATASET_PROJECT_ID" --format=prettyjson ls \
  "${DATASET_PROJECT_ID}:${DATASET_ID}"
```

In BigQuery, check the expected table and its data against the intended account and clusters.

## Configure your existing Spoke deployment

Fill these Spoke values from `terraform output -json billing_access`.
Use compatible local chart and agent code until compatible releases are published.

```yaml
kompass-insights:
  gcpBilling:
    enabled: true
    project: "example-billing-project"
    table: "example-billing-project.billing_export.gcp_billing_export_resource_v1_012345_ABCDEF_678901"
    location: "US"
```

| Spoke value under `kompass-insights.gcpBilling` | Source | Agent environment variable |
| --- | --- | --- |
| `enabled` | Set `true` to enable GCP billing; the default is `false`. | `GCP_BILLING_ENABLED` |
| `project` | `billing_access.query_project_id` | `GCP_BILLING_PROJECT` |
| `table` | `billing_access.expected_export_table` | `GCP_BILLING_TABLE` |
| `location` | `billing_access.dataset_location` | `GCP_BILLING_LOCATION` |

When enabled, all three strings must be nonblank.
The query project can differ from the project in the fully qualified table name.
The billing account ID is a Terraform input, not an agent setting.
Existing `kompass-insights.insights.extraEnv` entries override matching ConfigMap values.
Remove conflicting overrides before using these values.

For a shared Terraform configuration, add this fragment inside your existing Spoke `helm_release`.
It assumes `module.kompass_insights` calls the root module in that configuration.
Keep existing `values` entries before the generated entry below.
Add the module to any existing `depends_on` list.

```hcl
values = [
  # Keep existing values entries here.
  yamlencode({
    "kompass-insights" = {
      gcpBilling = {
        enabled  = true
        project  = module.kompass_insights.query_project_id
        table    = module.kompass_insights.expected_export_table
        location = module.kompass_insights.dataset_location
      }
    }
  }),
]

depends_on = [module.kompass_insights]
```

The dependency waits for module-managed grants before Helm configures the agent.
It does not wait for billing export data.
With separate Terraform states, apply the access state first, then pass its outputs to Spoke.

## Verify runtime access

After export data is available, verify access from the actual agent runtime:

- Confirm that ADC selects the intended identity.
- Check OAuth scopes and network access to Google APIs.
- Confirm query-job creation in `query_project_id` and reads from the expected table at its
  location.
- Check that the data covers the intended account and clusters.

Follow the [live acceptance steps](../../README.md#live-acceptance) in an authorized sandbox.
Local Terraform checks and Helm rendering do not prove a successful GCP deployment.

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
| <a name="input_billing_account_id"></a> [billing\_account\_id](#input\_billing\_account\_id) | Optional billing account ID used to derive the expected detailed export table name. | `string` | `null` | no |
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
[Application Default Credentials (ADC)]: https://cloud.google.com/docs/authentication/set-up-adc-local-dev-environment
[billing-project command]: https://cloud.google.com/sdk/gcloud/reference/billing/projects/describe
[the dataset show command]: https://cloud.google.com/bigquery/docs/reference/bq-cli-reference#bq_show
[cluster list command]: https://cloud.google.com/sdk/gcloud/reference/container/clusters/list
[node-pool list command]: https://cloud.google.com/sdk/gcloud/reference/container/node-pools/list
[project describe command]: https://cloud.google.com/sdk/gcloud/reference/projects/describe
[reader ownership]: ../../README.md#use-existing-dataset-reader-grants
[query grant ownership]: ../../README.md#query-grant-ownership
