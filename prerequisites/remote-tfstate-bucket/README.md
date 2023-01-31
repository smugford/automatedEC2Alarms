# prerequisites

The prerequisites directory is for terraform resources that must be present before the other stacks are luanched. In this case we must create an s3 bucket for the state files to be stored in, without launching the prerequisites stack other stacks will not successfully launch.

## Prerequisites

- Install [Terraform](https://learn.hashicorp.com/terraform/getting-started/install.html)
- Install [Runway](https://docs.onica.com/projects/runway/en/release/installation.html)

## Deployment
   
Change the DEPLOY_ENVIRONMENT to AWS profile name for the account. i.e lab, dev, prod, test
   
```
DEPLOY_ENVIRONMENT=lab runway deploy
```
Select **prerequisites** from the stack list.

## Destruction

Change the DEPLOY_ENVIRONMENT to AWS profile name for the account. i.e lab, dev, prod, test

```
DEPLOY_ENVIRONMENT=lab runway destroy
```
Select **prerequisites** from the stack list.

## Built With

* Terraform >= 0.13.0
* Runway > 1.5.0
