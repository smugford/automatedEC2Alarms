# SSM Parameters

These SSM Parameters are used by the cloudwatch agent to monitor disks, memory, and all other custom metrics.


## Prerequisites

- Install [Terraform](https://learn.hashicorp.com/terraform/getting-started/install.html)
- Install [Runway](https://docs.onica.com/projects/runway/en/release/installation.html)


## Deployment

Change the DEPLOY_ENVIRONMENT to AWS profile name for the account. i.e dev, prod, test

```
cd AWS/terraform/accounts/application/lab
DEPLOY_ENVIRONMENT=lab runway deploy
```
Select `regional/cwagent-config-parameters` stack, fill in parameters, review and deploy.

## Destruction

Change the DEPLOY_ENVIRONMENT to AWS profile name for the account. i.e dev, prod, test

```
cd AWS/terraform/accounts/application/lab
DEPLOY_ENVIRONMENT=lab runway destroy
```
Select `regional/cwagent-config-parameters` stack, review and destroy.

## Built With

* Terraform >= 0.12.26
* Runway > 1.5.0

## Authors

* **Matt Van Zanten**
