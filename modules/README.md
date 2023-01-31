# modules

A module is a container for multiple resources that are used together. Modules can be used to create lightweight abstractions, so that you can describe your infrastructure in terms of its architecture, rather than directly in terms of physical objects. By using modules we reduce the amount of duplicate code in our repository.

## Prerequisites

- Install [Terraform](https://learn.hashicorp.com/terraform/getting-started/install.html)
- Install [Runway](https://docs.onica.com/projects/runway/en/release/installation.html)

## Files

**main.tf** - This is where all of the resources are created through logic such as if statements and loops which is determined by the input variable values sent from the main.tf in the parent stack. We are utilizing count with some logic as the if statements and loops as you will see in the child directories.

**variables.tf** - The variables file in the module is a definition of all the variables that will be required for the module to work correctly when referenced by your stack. When creating a variables.tf file for a module it is very important to set default (fallback) values so that if a feature of the module such as aws_cloudwatch_event_rule is not used (by setting var.enable_cw_rule_for_lambda to false), the code will not ask you to enter variable values for components that are not being used.

**outputs.tf** - The outputs file contains all of the output values that we will want to send back to the parent maint.tf file so that important information can be easily referred to by other resources in the parent stack.