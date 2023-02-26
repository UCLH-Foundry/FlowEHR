# 🌺 FlowEHR
FlowEHR is a safe, secure &amp; cloud-native development &amp; deployment platform for digital healthcare research &amp; innovation.

> **Warning**
> This repository is a _work in progress_. We're working towards a v0.1.0 release


## Getting started

This repository includes a [Dev Container](https://code.visualstudio.com/docs/devcontainers/containers) to avoid "it works on my machine" scenarios. 

Simply clone this repo:

```bash
git clone https://github.com/UCLH-Foundry/FlowEHR
```
Then open it in [VS Code](https://code.visualstudio.com) and, when prompted, click to "Open in Container" (make sure Docker is running on your host first). This will create a container with all the required packages for developing this repository.

## Configuring

Local deployment (i.e. non CI/CD) requires a `config.yaml` file in the root. Copy the `config.sample.yaml` file and save it as `config.yaml`.

```bash
cp config.sample.yaml config.yaml
```

Then edit `config.yaml` and specify the following values:

- `suffix` - a suffix to apply to all deployed resources (i.e. `flowehr-uclh`)
- `environment` - a unique name for your environment (i.e. `jgdev`)
- `location` - the [Azure region](https://azuretracks.com/2021/04/current-azure-region-names-reference/) you wish to deploy resources to
- `arm_subscription_id` - the [Azure subscription id](https://learn.microsoft.com/en-us/azure/azure-portal/get-subscription-tenant-id) you wish to deploy to

For the full reference of possible configuration values, see the [config schema file](./config_schema.json).

## Deploying
### Locally

1. Log in to Azure

    Run `az login` to authenticate to Azure

2. Run `make all`

    To bootstrap Terraform, and deploy all infrastructure, run

    ```bash
    make all
    ```

    Alternatively, you can deploy individual modules separately with their corresponding make command:

    ```bash
    make deploy-core
    ```

    To see all options:

    ```bash
    make help
    ```

### CI (GitHub Actions)

CI deployment workflows are run in [Github environments](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment). These should
be created in a private repository created from this template repository.

This step will create an AAP Application and Service Principal in the specified tenancy, and grant that service principal permissions in Azure and AAD needed for deployment. These are detailed below. 

> _NOTE_: The user following the steps below will need to be an `Owner` of the target Azure Subscription as well as a `Global Administrator` in AAD.

1. Open this repo in the dev container, and create the `config.yaml` file as outlined above.

2. Create the service principal with required AAD permissions: 

    ```bash
    make ci-auth
    ```

    _NOTE_: CI deployments require a service principal with access to deploy resources
    in the subscription, and the following permissions within the associated AAD tenancy:
    - `Application.ReadWrite.All`: Required to query the directory for the MSGraph app, and create applications used to administer the SQL Server.   
    - `AppRoleAssignment.ReadWrite.All`: Required to assign the following permissions to the System Managed Identity for SQL Server. 

    - Copy the block of JSON from the terminal for the next step.


2. Create and populate a GitHub environment

    Add an environment called `Infra-Test` with the following secrets:

    - `AZURE_CREDENTIALS`: json containing the credentials of the service principal in the format. This should have been output for you in the correct format in the previous step:

        ```json
        {
            "clientId": "xxx",
            "clientSecret": "xxx",
            "tenantId": "xxx",
            "subscriptionId": "xxx",
            "resourceManagerEndpointUrl": "management.azure.com"
        }
        ```

    - `SUFFIX`: Suffix used for naming resources. Must be unique to this repository e.g. `abcd`
    - `LOCATION`: Name of an Azure location e.g. `uksouth`. These can be listed with `az account list-locations -o table`
    - `ENVIRONMENT`: Name of the environment e.g. `dev`, also used to name resources
    - `DEVCONTAINER_ACR_NAME`: Name of the Azure Container Registry to use for the devcontainer build. This may or may not exist. e.g. `flowehrmgmtacr`


3. Run `Deploy Infra-Test`

    Trigger a deployment using a workflow dispatch trigger on the `Actions` tab.

## Identities

This table summarises the various authentication identities involved in the deployment and operation of FlowEHR:

| Name | Type | Access Needed | Purpose |
|--|--|--|--|
| Local Developer | User context of developer running `az login` | Azure: `Owner`. <br/> AAD: Either `Global Administrator` or `Priviliged Role Administrator`. | To automate the deployment of resources and identities during development |
| `sp-flowehr-cicd-<naming-suffix>` | App / Service Principal | Azure: `Owner`. <br/>AAD: `Application.ReadWrite.All` / `AppRoleAssignment.ReadWrite.All` | Context for GitHub runner for CICD. Needs to query apps, create new apps (detailed below), and assign roles to identities |
| `flowehr-sql-owner-<naming-suffix>` | App / Service Principal | AAD Administrator of SQL Feature Data Store | Used to connect to SQL as a Service Principal, and create logins + users during deployment |
| `flowehr-databricks-sql-<naming-suffix>` | App / Service Principal | No access to resources or AAD. Added as a `db_owner` of the Feature Data Store database. Credentials stored in databricks secrets to be used in saving features to SQL |
| `sql-server-features-<naming-suffix>` | System Managed Identity | AAD: `User.Read.All` / `GroupMember.Read.All` / `Application.Read.All` | For SQL to accept AAD connections |
