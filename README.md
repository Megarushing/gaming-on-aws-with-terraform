 ![Terraform Version](https://img.shields.io/badge/tf-%3E%3D0.12.0-blue.svg)

 #  Playing with Terraform to deploy an AWS instance dedicated to gaming

 ## Quick start

 **Note**: These example deploys resources into your AWS account. You WILL BE charged money for this, and the gaming instance can cost up to £500/month if left running 24/7 D:

 1. Install [Terraform](https://www.terraform.io/). You can also use https://brew.sh/ to install Brew, and then launch `brew install terraform`
 1. Set your AWS credentials as the environment variables `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`. Open Terminal and launch
`export AWS_ACCESS_KEY_ID="yourkey"`
`export AWS_SECRET_ACCESS_KEY="yourkey"`
 1. `cd` into the working folder
 1. Run `terraform init`.
 1. Run `terraform apply`.
 1. you can download the Remote Desktop preset from the AWS web console to login and finish the setup.
 1. Launch and login in Parsec. Close RDP and use Parsec on your client.


To clean up and delete all resources after you're done, run `terraform destroy`.


## To do:

- auto-set the public IP of my connection
- link an external EBS where all Steam games are installed and link it at boot
- improve readme :S
