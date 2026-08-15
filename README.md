# Ansible Automation & Deployment Projects

This repository documents my hands-on Ansible automation projects, progressing
from basic configuration management with static inventories to an end-to-end
AWS automation workflow using Terraform, Jenkins, Ansible dynamic inventory,
Docker, and Docker Compose.

The projects demonstrate not only the final working implementations, but also
the troubleshooting and architectural improvements I made while building them.


## Projects

### Project 1: Ansible Web Server & Node.js Deployment

- Static Ansible inventory
- Nginx installation and configuration
- Node.js application deployment
- Linux user management
- Ansible variables
- Targeted deployments using `--limit`

### Project 2: Jenkins + Terraform + Ansible AWS Automation

- AWS infrastructure provisioning with Terraform
- Dynamic creation of multiple EC2 instances
- Jenkins pipeline orchestration
- Dedicated Ansible Control Node
- AWS EC2 dynamic inventory
- EC2 readiness checking before configuration
- Automated Docker installation
- Automated Docker Compose installation
- Jenkins credential management
- SSH authentication
- End-to-end infrastructure and configuration automation


# Project 1: Ansible Web Server & Node.js Deployment

## Project Overview

This project was executed from my Ansible control workspace in WSL.

I used Ansible to configure remote Linux servers, install Nginx, create Linux
users, install Node.js, and deploy a packaged Node.js application.


## Files

- `hosts` - static inventory for the `webservers` group
- `ansible.cfg` - local Ansible configuration
- `my-playbook.yaml` - installs and starts Nginx on target servers
- `deploy-node.yaml` - installs Node.js, creates the application user, and deploys the packaged Node.js application
- `project-vars` - local project variables used by the playbook and excluded from Git where sensitive


## Static Inventory

The initial implementation used a static Ansible inventory:

```ini
[webservers]
157.245.248.54
137.184.194.241

[webservers:vars]
ansible_ssh_private_key_file=/home/josep/.ssh/id_rsa
ansible_user=root
```


## How to Run

```bash
cd /home/josep/ansible

ansible-playbook -i hosts my-playbook.yaml

ansible-playbook -i hosts deploy-node.yaml
```

To deploy to only one server:

```bash
ansible-playbook -i hosts deploy-node.yaml --limit 157.245.248.54
```


## What I Learned

This project introduced me to Ansible inventory management, playbooks,
variables, package installation, Linux user management, and remote application
deployment.

It also helped me understand how configuration management can replace repetitive
manual server administration.


---

# Project 2: Jenkins + Terraform + Ansible AWS Automation

## Project Overview

This project extends my Ansible experience into an end-to-end AWS automation
workflow using Terraform, Jenkins, and Ansible.

Terraform provisions the AWS infrastructure and EC2 instances.

Jenkins acts as the automation and orchestration layer.

A dedicated Ansible Control Node performs configuration management on the
newly provisioned EC2 instances.

Instead of manually maintaining changing EC2 IP addresses, Ansible uses AWS
dynamic inventory to automatically discover the managed instances.

The discovered EC2 instances are then configured with Docker and Docker Compose.


## Architecture

### Architecture A: Terraform + Ansible Infrastructure Automation

```text
                    Terraform
                        |
                        v
              Provision AWS Infrastructure
                        |
             +----------+----------+
             |                     |
             v                     v
       AWS Networking         EC2 Instances
                                    |
                                    v
                          Wait for SSH Readiness
                                    |
                                    v
                                 Ansible
                                    |
                   +----------------+----------------+
                   |                |                |
                   v                v                v
            Install Docker   Docker Compose   Configure Server



### Architecture B: Jenkins + Ansible Automation

                      GitHub
                         |
                         v
                  Jenkins Pipeline
                         |
                         v
                Ansible Control Node
                         |
                         v
                AWS Dynamic Inventory
                         |
                         v
                 Discover EC2 Nodes
                         |
              +----------+----------+
              |                     |
              v                     v
       EC2 Managed Node 1    EC2 Managed Node 2
              |                     |
              +----------+----------+
                         |
                         v
                  Ansible Playbook
                         |
              +----------+----------+
              |                     |
              v                     v
        Install Docker      Install Docker Compose


# Infrastructure Provisioning with Terraform

Terraform defines the AWS infrastructure required by the project.

The configuration provisions:

- VPC
- Subnet
- Internet Gateway
- Route table
- Security group
- SSH key pair
- Latest Amazon Linux 2023 AMI
- Multiple EC2 instances


## Dynamic EC2 Creation with `for_each`

Instead of duplicating an `aws_instance` resource for each server, I used
Terraform `for_each` with a map of server definitions.

```hcl
variable "servers" {
  type = map(object({
    instance_type = string
    env           = string
  }))
}
```

The EC2 resource dynamically creates the servers:

```hcl
resource "aws_instance" "myapp-server" {
  for_each = var.servers

  ami           = data.aws_ami.latest-amazon-linux-image.id
  instance_type = each.value.instance_type

  subnet_id              = aws_subnet.myapp-subnet-1.id
  vpc_security_group_ids = [aws_default_security_group.default-sg.id]
  availability_zone      = var.avail_zone

  associate_public_ip_address = true
  key_name                    = aws_key_pair.ssh-key.key_name

  tags = {
    Name        = "${var.env_prefix}-${each.key}"
    Environment = each.value.env
  }
}
```

This makes it possible to define different instance types and environments
without duplicating Terraform resources.


## Dynamic Public IP Outputs

Terraform also returns the public IP address of each dynamically created
instance:

```hcl
output "ec2_public_ips" {
  value = {
    for name, server in aws_instance.myapp-server :
    name => server.public_ip
  }
}
```


# Evolution of the Terraform-to-Ansible Integration

## Initial Implementation: Terraform `local-exec`

In the initial implementation, I triggered Ansible directly from the EC2
resource using Terraform's `local-exec` provisioner.

The EC2 public IP did not exist before provisioning.

After AWS created the instance and assigned a public IP, Terraform made the
new value available through `self.public_ip` and passed it directly to Ansible
as an inline inventory.

```hcl
# Previous implementation
#
# The EC2 public IP was dynamically available after AWS created the instance.
# Terraform then passed self.public_ip directly to Ansible.
#
# This approach was later replaced as the project evolved toward a more
# decoupled Jenkins + AWS dynamic inventory workflow.

# provisioner "local-exec" {
#   working_dir = path.module
#   command = "ansible-playbook --inventory ${self.public_ip}, --private-key ${var.ssh_key_private} --user ec2-user deploy-docker-new-user.yaml"
# }
```

The original flow was:

```text
Terraform
    |
    v
Create EC2
    |
    v
AWS assigns public IP
    |
    v
Terraform receives self.public_ip
    |
    v
local-exec
    |
    v
Ansible configures the instance
```


## Intermediate Improvement: Separate Post-Provisioning Action

The project later explored separating the post-provisioning Ansible action
from the EC2 resource lifecycle using a separate lifecycle resource.

Conceptually:

```hcl
# Intermediate implementation example

# resource "null_resource" "configure_servers" {
#
#   depends_on = [
#     aws_instance.myapp-server
#   ]
#
#   provisioner "local-exec" {
#     command = "ansible-playbook ..."
#   }
# }
```

This reduced the direct coupling between the EC2 resource definition and the
configuration-management action.


## Final Design: Jenkins + AWS Dynamic Inventory

The final workflow separates responsibilities more clearly:

```text
Terraform
    |
    +------> Provision AWS infrastructure
    |
    v
AWS EC2 Instances
    |
    v
AWS Dynamic Inventory
    |
    v
Ansible discovers managed nodes
    |
    v
Jenkins orchestrates Ansible execution
    |
    v
Ansible configures EC2 instances
```

Terraform focuses on infrastructure provisioning.

Ansible focuses on configuration management.

Jenkins orchestrates the automation workflow.


# Improving EC2 Readiness Handling

One problem I encountered was that newly provisioned EC2 instances were not
always ready to accept SSH connections immediately after AWS created them.

An early workaround was to introduce a fixed delay before running Ansible.

I later improved the solution by allowing Ansible itself to check whether SSH
was actually ready.

```yaml
- name: Wait for SSH connection to be available
  hosts: tag_Environment_dev
  gather_facts: false

  tasks:
    - name: Wait for SSH to be available
      wait_for:
        port: 22
        delay: 10
        timeout: 100
        search_regex: OpenSSH
        host: "{{ ansible_ssh_host | default(ansible_host) | default(inventory_hostname) }}"
      vars:
        ansible_connection: local
        ansible_python_interpreter: /usr/bin/python3
```

This was more reliable than assuming that every EC2 instance would become
ready after a fixed number of seconds.

The configuration workflow now becomes:

```text
EC2 Created
    |
    v
Wait for port 22
    |
    v
Confirm OpenSSH availability
    |
    v
Begin Ansible configuration
```


# AWS Dynamic Inventory

Instead of hard-coding EC2 IP addresses, I configured Ansible to query AWS and
discover instances dynamically.

The inventory configuration uses the AWS EC2 inventory plugin.

```yaml
plugin: amazon.aws.aws_ec2

regions:
  - us-east-2

keyed_groups:
  - key: tags
    prefix: tag

  - key: instance_type
    prefix: instance_type
```

This allows Ansible to dynamically create inventory groups using AWS metadata
and tags.

For example:

```text
tag_Environment_dev
tag_Environment_prod
instance_type_t2_micro
instance_type_t2_small
```

The playbook can therefore target:

```yaml
hosts: tag_Environment_dev
```

instead of manually maintaining IP addresses.


# Jenkins Pipeline Workflow

The AWS infrastructure and EC2 instances used in this workflow were provisioned
with Terraform separately. Once the infrastructure was available, Jenkins
orchestrated the Ansible configuration workflow described below.

## Step 1: Jenkins Checks Out the GitHub Repository

Jenkins checks out the `feature/ansible` branch containing the application
code, Jenkinsfile, and Ansible configuration.

Example pipeline evidence:

```text
Started by user Godswill

Checking out git https://github.com/Godswill012/java-maven-app.git

using credential github-credentials

Checking out Revision 541f76aa18b7259d864e61d2f23aee44867bf2eb
(refs/remotes/origin/feature/ansible)

Commit message:
"Update Jenkins and Ansible configuration for dynamic AWS inventory"

[Pipeline] Start of Pipeline
```


## Step 2: Jenkins Copies Ansible Files to the Control Node

Jenkins transfers the required Ansible configuration to the dedicated control
node.

```text
copying all neccessary files to ansible control node

[Pipeline] sshagent
[ssh-agent] Using credentials root

scp -o StrictHostKeyChecking=no \
ansible/ansible.cfg \
ansible/inventory_aws_ec2.yaml \
ansible/my-playbook.yaml \
root@143.244.173.156:/root
```


## Step 3: Jenkins Handles SSH Credentials Securely

The EC2 private key is stored in Jenkins Credentials rather than hard-coded
inside the Jenkinsfile.

During execution, Jenkins masks the credential:

```text
[Pipeline] withCredentials

Masking supported pattern matches of $keyfile

[Pipeline] sh

+ scp **** root@143.244.173.156:/root/ssh-key.pem
```

The actual private key is not exposed in the Jenkins console output.


## Step 4: Jenkins Prepares the Ansible Control Node

Jenkins remotely runs a preparation script on the Ansible Control Node.

The required dependencies include:

- Ansible
- Python
- boto3

Pipeline evidence:

```text
Executing script on ansible-server[143.244.173.156]:
prepare-ansible-server.sh

ansible is already the newest version (9.2.0+dfsg-0ubuntu5).

python3-boto3 is already the newest version (1.34.46+dfsg-1ubuntu1).
```


## Step 5: Ansible Dynamically Discovers the EC2 Instances

Ansible uses AWS dynamic inventory and boto3 to query AWS for the EC2 instances
that were previously provisioned with Terraform.

Instead of manually maintaining changing EC2 IP addresses, Ansible dynamically
discovers the managed nodes from AWS.


## Step 6: Jenkins Executes the Ansible Playbook

Jenkins remotely triggers the Ansible playbook on the Ansible Control Node:

```text
[Pipeline] sshCommand

Executing command on ansible-server[143.244.173.156]:

ansible-playbook my-playbook.yaml
```


## Step 7: Ansible Configures Both EC2 Instances

The playbook successfully reaches both dynamically discovered managed nodes.

```text
PLAY [Install Docker]

TASK [Gathering Facts]

ok: [ec2-18-227-97-7.us-east-2.compute.amazonaws.com]
ok: [ec2-3-143-245-208.us-east-2.compute.amazonaws.com]
```

Docker is installed:

```text
TASK [Install Docker]

changed: [ec2-18-227-97-7.us-east-2.compute.amazonaws.com]
changed: [ec2-3-143-245-208.us-east-2.compute.amazonaws.com]
```

The Docker daemon is started:

```text
TASK [Start docker daemon]

changed: [ec2-18-227-97-7.us-east-2.compute.amazonaws.com]
changed: [ec2-3-143-245-208.us-east-2.compute.amazonaws.com]
```

Docker Compose is installed:

```text
TASK [Install docker-compose]

changed: [ec2-18-227-97-7.us-east-2.compute.amazonaws.com]
changed: [ec2-3-143-245-208.us-east-2.compute.amazonaws.com]
```


# Successful Pipeline Verification

The Ansible playbook completed successfully on both dynamically discovered
instances.

```text
PLAY RECAP

ec2-18-227-97-7.us-east-2.compute.amazonaws.com :
ok=7 changed=4 unreachable=0 failed=0 skipped=0 rescued=0 ignored=0

ec2-3-143-245-208.us-east-2.compute.amazonaws.com :
ok=7 changed=4 unreachable=0 failed=0 skipped=0 rescued=0 ignored=0

[Pipeline] End of Pipeline

Finished: SUCCESS
```

The important validation points are:

```text
EC2 Managed Node 1
unreachable=0
failed=0

EC2 Managed Node 2
unreachable=0
failed=0

Jenkins Pipeline
SUCCESS
```


# Full End-to-End Jenkins Pipeline Evidence

The complete Jenkins console output is retained as additional evidence of the
successful automation workflow.

It demonstrates:

- GitHub checkout
- Jenkins credentials
- SSH agent usage
- File transfer
- Ansible Control Node preparation
- boto3 dependency validation
- Remote Ansible execution
- Dynamic EC2 targeting
- Docker installation
- Docker Compose installation
- Successful play recap
- Successful Jenkins pipeline completion

<details>
<summary><strong>Click to view full Jenkins pipeline execution</strong></summary>

```text
Started by user Godswill
Lightweight checkout support not available, falling back to full checkout.
Checking out git https://github.com/Godswill012/java-maven-app.git into /var/jenkins_home/workspace/ansible-pipeline@script/ec678d5946f1df166b1331a02b4a0d920f2d1e902a317602a75e59ed5b9e7d3e to read Jenkinsfile
The recommended git tool is: git
using credential github-credentials
 > git rev-parse --resolve-git-dir /var/jenkins_home/workspace/ansible-pipeline@script/ec678d5946f1df166b1331a02b4a0d920f2d1e902a317602a75e59ed5b9e7d3e/.git # timeout=10
Fetching changes from the remote Git repository
 > git config remote.origin.url https://github.com/Godswill012/java-maven-app.git # timeout=10
Fetching upstream changes from https://github.com/Godswill012/java-maven-app.git
 > git --version # timeout=10
 > git --version # 'git version 2.47.3'
using GIT_ASKPASS to set credentials 
 > git fetch --tags --force --progress -- https://github.com/Godswill012/java-maven-app.git +refs/heads/*:refs/remotes/origin/* # timeout=10
 > git rev-parse refs/remotes/origin/feature/ansible^{commit} # timeout=10
 > git rev-parse feature/ansible^{commit} # timeout=10
Checking out Revision 541f76aa18b7259d864e61d2f23aee44867bf2eb (refs/remotes/origin/feature/ansible)
 > git config core.sparsecheckout # timeout=10
 > git checkout -f 541f76aa18b7259d864e61d2f23aee44867bf2eb # timeout=10
Commit message: "Update Jenkins and Ansible configuration for dynamic AWS inventory"
 > git rev-list --no-walk 541f76aa18b7259d864e61d2f23aee44867bf2eb # timeout=10
[Pipeline] Start of Pipeline
[Pipeline] node
Running on Jenkins in /var/jenkins_home/workspace/ansible-pipeline
[Pipeline] {
[Pipeline] stage
[Pipeline] { (Declarative: Checkout SCM)
[Pipeline] checkout
The recommended git tool is: git
using credential github-credentials
 > git rev-parse --resolve-git-dir /var/jenkins_home/workspace/ansible-pipeline/.git # timeout=10
Fetching changes from the remote Git repository
 > git config remote.origin.url https://github.com/Godswill012/java-maven-app.git # timeout=10
Fetching upstream changes from https://github.com/Godswill012/java-maven-app.git
 > git --version # timeout=10
 > git --version # 'git version 2.47.3'
using GIT_ASKPASS to set credentials 
 > git fetch --tags --force --progress -- https://github.com/Godswill012/java-maven-app.git +refs/heads/*:refs/remotes/origin/* # timeout=10
 > git rev-parse refs/remotes/origin/feature/ansible^{commit} # timeout=10
 > git rev-parse feature/ansible^{commit} # timeout=10
Checking out Revision 541f76aa18b7259d864e61d2f23aee44867bf2eb (refs/remotes/origin/feature/ansible)
 > git config core.sparsecheckout # timeout=10
 > git checkout -f 541f76aa18b7259d864e61d2f23aee44867bf2eb # timeout=10
Commit message: "Update Jenkins and Ansible configuration for dynamic AWS inventory"
[Pipeline] }
[Pipeline] // stage
[Pipeline] withEnv
[Pipeline] {
[Pipeline] withEnv
[Pipeline] {
[Pipeline] stage
[Pipeline] { (copy files to ansible server)
[Pipeline] script
[Pipeline] {
[Pipeline] echo
copying all neccessary files to ansible control node
[Pipeline] sshagent
[ssh-agent] Using credentials root
$ ssh-agent
SSH_AUTH_SOCK=/tmp/ssh-0eSTerOiLSZ7/agent.78051
SSH_AGENT_PID=78055
Running ssh-add (command line suppressed)
[ssh-agent] Started.
[Pipeline] {
[Pipeline] sh
+ scp -o StrictHostKeyChecking=no ansible/ansible.cfg ansible/inventory_aws_ec2.yaml ansible/my-playbook.yaml root@143.244.173.156:/root
[Pipeline] withCredentials
Masking supported pattern matches of $keyfile
[Pipeline] {
[Pipeline] sh
+ scp **** root@143.244.173.156:/root/ssh-key.pem
[Pipeline] }
[Pipeline] // withCredentials
[Pipeline] }
$ ssh-agent -k
unset SSH_AUTH_SOCK;
unset SSH_AGENT_PID;
echo Agent pid 78055 killed;
[ssh-agent] Stopped.
[Pipeline] // sshagent
[Pipeline] }
[Pipeline] // script
[Pipeline] }
[Pipeline] // stage
[Pipeline] stage
[Pipeline] { (execute ansible playbook)
[Pipeline] script
[Pipeline] {
[Pipeline] echo
calling ansible playbook to configure ec2 instances
[Pipeline] withCredentials
Masking supported pattern matches of $keyfile
[Pipeline] {
[Pipeline] sshScript
Executing script on ansible-server[143.244.173.156]: /var/jenkins_home/workspace/ansible-pipeline/prepare-ansible-server.sh

WARNING: apt does not have a stable CLI interface. Use with caution in scripts.

Hit:1 http://mirrors.digitalocean.com/ubuntu noble InRelease
Hit:2 http://mirrors.digitalocean.com/ubuntu noble-updates InRelease
Hit:3 http://mirrors.digitalocean.com/ubuntu noble-backports InRelease
Hit:4 http://security.ubuntu.com/ubuntu noble-security InRelease
Hit:5 https://repos-droplet.digitalocean.com/apt/droplet-agent main InRelease
Reading package lists...

Building dependency tree...

Reading state information...
95 packages can be upgraded. Run 'apt list --upgradable' to see them.

WARNING: apt does not have a stable CLI interface. Use with caution in scripts.

Reading package lists...

Building dependency tree...

Reading state information...

ansible is already the newest version (9.2.0+dfsg-0ubuntu5).
0 upgraded, 0 newly installed, 0 to remove and 95 not upgraded.

WARNING: apt does not have a stable CLI interface. Use with caution in scripts.

Reading package lists...

Building dependency tree...

Reading state information...

python3-boto3 is already the newest version (1.34.46+dfsg-1ubuntu1).
0 upgraded, 0 newly installed, 0 to remove and 95 not upgraded.
[Pipeline] sshCommand
Executing command on ansible-server[143.244.173.156]: ansible-playbook my-playbook.yaml sudo: false

PLAY [Install Docker] **********************************************************

TASK [Gathering Facts] *********************************************************
[WARNING]: Platform linux on host ec2-18-227-97-7.us-
east-2.compute.amazonaws.com is using the discovered Python interpreter at
/usr/bin/python3.9, but future installation of another Python interpreter could
change the meaning of that path. See https://docs.ansible.com/ansible-
core/2.16/reference_appendices/interpreter_discovery.html for more information.
[WARNING]: Platform linux on host ec2-3-143-245-208.us-
east-2.compute.amazonaws.com is using the discovered Python interpreter at
/usr/bin/python3.9, but future installation of another Python interpreter could
change the meaning of that path. See https://docs.ansible.com/ansible-
core/2.16/reference_appendices/interpreter_discovery.html for more information.
ok: [ec2-18-227-97-7.us-east-2.compute.amazonaws.com]
ok: [ec2-3-143-245-208.us-east-2.compute.amazonaws.com]

TASK [Install Docker] **********************************************************
changed: [ec2-18-227-97-7.us-east-2.compute.amazonaws.com]
changed: [ec2-3-143-245-208.us-east-2.compute.amazonaws.com]

TASK [Start docker daemon] *****************************************************
changed: [ec2-18-227-97-7.us-east-2.compute.amazonaws.com]
changed: [ec2-3-143-245-208.us-east-2.compute.amazonaws.com]

PLAY [Install docker-compose] **************************************************

TASK [Gathering Facts] *********************************************************
ok: [ec2-18-227-97-7.us-east-2.compute.amazonaws.com]
ok: [ec2-3-143-245-208.us-east-2.compute.amazonaws.com]

TASK [create docker-compose directory] *****************************************
ok: [ec2-18-227-97-7.us-east-2.compute.amazonaws.com]
ok: [ec2-3-143-245-208.us-east-2.compute.amazonaws.com]

TASK [Get architecture of the remote host] *************************************
changed: [ec2-18-227-97-7.us-east-2.compute.amazonaws.com]
changed: [ec2-3-143-245-208.us-east-2.compute.amazonaws.com]

TASK [Install docker-compose] **************************************************
changed: [ec2-3-143-245-208.us-east-2.compute.amazonaws.com]
changed: [ec2-18-227-97-7.us-east-2.compute.amazonaws.com]

PLAY RECAP *********************************************************************
ec2-18-227-97-7.us-east-2.compute.amazonaws.com : ok=7    changed=4    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
ec2-3-143-245-208.us-east-2.compute.amazonaws.com : ok=7    changed=4    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   

[Pipeline] }
[Pipeline] // withCredentials
[Pipeline] }
[Pipeline] // script
[Pipeline] }
[Pipeline] // stage
[Pipeline] }
[Pipeline] // withEnv
[Pipeline] }
[Pipeline] // withEnv
[Pipeline] }
[Pipeline] // node
[Pipeline] End of Pipeline
Finished: SUCCESS

</details>


# Troubleshooting & Challenges

## EC2 SSH Readiness

New EC2 instances were sometimes created successfully by AWS but were not
immediately ready for SSH connections.

Instead of relying only on a fixed `sleep`, I implemented an Ansible `wait_for`
check that waits for port 22 and OpenSSH before beginning configuration.


## SSH Authentication Failure

During testing, Ansible initially failed to connect to the EC2 instances:

```text
Permission denied (publickey,gssapi-keyex,gssapi-with-mic)
```

I tested SSH connectivity independently and discovered that the EC2 instances
had been created using a different AWS key pair from the one initially
configured locally.

After locating the correct `ansible-key` private key, updating the Ansible
configuration, and testing connectivity again, both instances responded
successfully:

```text
ec2-3-143-245-208... | SUCCESS
"ping": "pong"

ec2-18-227-97-7... | SUCCESS
"ping": "pong"
```


## AWS Dynamic Inventory Configuration

I also worked through AWS inventory configuration and credential issues before
Ansible successfully discovered the EC2 instances.

This strengthened my understanding of the relationship between:

```text
Ansible
   |
   v
AWS EC2 Inventory Plugin
   |
   v
boto3
   |
   v
AWS API
   |
   v
EC2 Instance Discovery
```


# Security Practices

Sensitive information is intentionally excluded from this repository.

Security practices used in this project include:

- Jenkins Credentials for SSH keys
- Jenkins masking of credential values in console output
- `.gitignore` exclusions for private keys
- `.gitignore` exclusions for Terraform state files
- `.gitignore` exclusions for sensitive variable files
- No private key contents stored in the README
- No AWS secret access keys stored in source control


# What I Built

Through this project I:

- Provisioned AWS infrastructure with Terraform
- Dynamically created multiple EC2 instances using `for_each`
- Configured a dedicated Ansible Control Node
- Integrated Jenkins with Ansible
- Implemented AWS EC2 dynamic inventory
- Used boto3 for AWS integration
- Implemented SSH readiness checking
- Automated Docker installation
- Automated Docker Compose installation
- Managed Jenkins SSH credentials securely
- Remotely executed Ansible through Jenkins
- Troubleshot SSH authentication and infrastructure readiness issues
- Verified successful configuration across multiple EC2 instances


# What I Learned

One of my biggest learnings from this project was understanding how Jenkins,
Terraform, and Ansible complement each other rather than treating them as
separate technologies.

Terraform provides infrastructure provisioning.

Jenkins provides automation and workflow orchestration.

Ansible provides configuration management.

AWS dynamic inventory connects the dynamically changing infrastructure to the
configuration-management layer.

I also gained practical experience with:

- Terraform
- Jenkins pipelines
- Ansible playbooks
- AWS EC2
- AWS dynamic inventory
- boto3
- SSH authentication
- Jenkins Credentials
- Docker
- Docker Compose
- Linux
- Git and GitHub
- Infrastructure troubleshooting
- Configuration-management troubleshooting

Most importantly, I learned how infrastructure provisioning, dynamic resource
discovery, credential management, configuration management, and CI/CD
automation can work together as one end-to-end DevOps workflow.


# Technologies Used

- AWS
- Terraform
- Jenkins
- Ansible
- Python
- boto3
- Docker
- Docker Compose
- Linux
- SSH
- Git
- GitHub