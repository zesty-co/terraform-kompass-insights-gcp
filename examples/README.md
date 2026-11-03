# Examples

Use [`quick-start/`](quick-start/) to configure a billing export dataset and permissions for
existing GKE node service accounts. The example uses the local module with `source = "../.."`.

The example uses an existing dataset by default. It also supports dataset creation, different
query and dataset projects, and externally managed dataset reader grants.
See [quick-start/main.tf:1](quick-start/main.tf#L1) for the module call.

Read the [module prerequisites](../README.md#prerequisites) before you apply the example.
Use one state for a shared billing destination and its module-managed grants across clusters.
All example values are placeholders.
