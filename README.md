# Ansible Automation & Deployment Projects

This repository documents my hands-on Ansible work across Linux server configuration, Node.js deployment, AWS EC2 automation, Terraform integration, Jenkins orchestration, AWS dynamic inventory, reusable Ansible roles, Kubernetes resource management, and Nexus Repository automation.

Rather than presenting all of these as one pipeline, this README separates the projects and workflows according to how they were actually implemented.

---

## Repository Projects

### Project 1 — Linux, Nginx & Node.js Automation

- Static Ansible inventory
- Nginx installation and service management
- Node.js and npm installation
- Dedicated Linux application user
- Versioned application artifact deployment
- Background application startup and process verification

### Project 2 — AWS EC2 Automation with Terraform & Ansible

- AWS VPC, subnet, route, Internet Gateway and security-group provisioning
- Latest Amazon Linux 2023 AMI lookup
- Multiple EC2 instances created with Terraform `for_each`
- Terraform-to-Ansible integration
- EC2 SSH readiness checks
- Docker and Docker Compose installation
- Linux user creation
- Container startup with Docker Compose

### Project 3 — Jenkins + Ansible with AWS Dynamic Inventory

- Jenkins pipeline orchestration
- Dedicated Ansible Control Node
- AWS EC2 dynamic inventory
- boto3 integration
- Jenkins-managed SSH credentials
- Remote Ansible playbook execution
- Successful configuration of multiple EC2 managed nodes

### Project 4 — Refactoring Ansible with Roles

- Reusable `create_user` role
- Reusable `start_containers` role
- Cleaner separation of playbook responsibilities

### Project 5 — Kubernetes Deployment with Ansible

- `kubernetes.core.k8s`
- Kubernetes namespace creation
- Manifest-driven Nginx deployment
- Ansible running locally against a Kubernetes cluster

### Project 6 — Nexus Repository Automation

- Java 17 and supporting package installation
- Nexus download and extraction
- Dedicated Nexus service user
- Ownership and permissions
- Nexus configuration
- Service startup
- Status, log, process and port verification
- Evolution from a manual shell procedure to Ansible automation

---

# Project 1 — Linux, Nginx & Node.js Automation

## Overview

The first project establishes the foundation of the repository: using Ansible from a control machine to configure Linux servers through a static inventory.

The root `my-playbook.yaml` installs and starts Nginx on hosts in the `webservers` group:

```yaml
---
- name: Configure nginx web server
  hosts: webservers

  tasks:
    - name: Update apt package index
      apt:
        update_cache: true
        cache_valid_time: 3600

    - name: Install nginx server
      apt:
        name: nginx
        state: latest

    - name: Start nginx server
      service:
        name: nginx
        state: started
```

The root `deploy-node.yaml` builds on that foundation by automating a Node.js application deployment.

## Node.js Deployment Workflow

```text
Static Inventory
      |
      v
Install Node.js + npm
      |
      v
Create Application User
      |
      v
Unpack Versioned Application Artifact
      |
      v
Install npm Dependencies
      |
      v
Start Application as Non-Root User
      |
      v
Verify Node.js Process
```

The playbook uses `project-vars` for values such as the application user, archive version, source location and home directory. Sensitive/local variable files are intentionally excluded from source control where appropriate.

## Root Ansible Configuration

The root `ansible.cfg` includes SSH timeout and keepalive settings as well as pipelining:

```ini
[defaults]
host_key_checking = False
timeout = 60

[ssh_connection]
ssh_args = -o ControlMaster=no -o ControlPersist=no -o ServerAliveInterval=30 -o ServerAliveCountMax=4
pipelining = True
```

## What I Learned

This project helped me understand:

- Static inventories
- Ansible playbooks and modules
- Linux package management
- Service management
- User creation
- Variables and variable files
- Privilege escalation
- Running application tasks as a non-root user
- Background execution with `async` and `poll`
- Verifying application processes after deployment

---

# Project 2 — AWS EC2 Automation with Terraform & Ansible

## Overview

This project moves from manually managed servers to dynamically provisioned AWS infrastructure.

Terraform creates the AWS infrastructure and EC2 instances. Ansible then performs operating-system and application configuration on those instances.

**Jenkins is not part of this Terraform-to-Ansible workflow.** The Jenkins + Ansible workflow is documented separately in Project 3.

---

## Terraform Infrastructure

The Terraform configuration provisions:

- VPC
- Subnet
- Internet Gateway
- Default route table
- Security group
- SSH key pair
- Latest Amazon Linux 2023 AMI
- Multiple EC2 instances

### Dynamic EC2 Creation

The project uses a map of server definitions:

```hcl
variable "servers" {
  type = map(object({
    instance_type = string
    env           = string
  }))
}
```

and creates the EC2 instances with `for_each`:

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

This avoids duplicating an EC2 resource block for every server.

Terraform also outputs the public IP address of each created instance:

```hcl
output "ec2_public_ips" {
  value = {
    for name, server in aws_instance.myapp-server :
    name => server.public_ip
  }
}
```

---

## Evolution of Terraform-to-Ansible Integration

### Initial Approach — `local-exec`

An early implementation triggered Ansible after Terraform created an EC2 instance.

The public IP was not hard-coded in advance. After AWS assigned the instance a public IP, Terraform could reference the value through `self.public_ip` and pass it to Ansible as inline inventory:

```hcl
# Previous implementation
#
# provisioner "local-exec" {
#   working_dir = path.module
#   command = "ansible-playbook --inventory ${self.public_ip}, --private-key ${var.ssh_key_private} --user ec2-user deploy-docker-new-user.yaml"
# }
```

The flow was:

```text
Terraform
   |
   v
Create EC2
   |
   v
AWS Assigns Public IP
   |
   v
Terraform Receives self.public_ip
   |
   v
local-exec
   |
   v
Ansible Configures the Instance
```

### Intermediate Approach — Separate Post-Provisioning Action

The project also explored separating the post-provisioning Ansible action from the EC2 resource using a `null_resource`:

```hcl
# resource "null_resource" "configure_servers" {
#   depends_on = [
#     aws_instance.myapp-server
#   ]
#
#   provisioner "local-exec" {
#     command = "ansible-playbook ..."
#   }
# }
```

The repository retains these commented examples to show how the design evolved.

---

## EC2 SSH Readiness

A newly created EC2 instance can exist in AWS before its SSH service is ready.

The Ansible playbook checks port 22 and confirms that OpenSSH is available before continuing with configuration:

```yaml
---
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

This makes readiness dependent on the actual SSH condition rather than only on EC2 resource creation.

---

## Docker Deployment Variants

The repository contains several EC2 playbooks showing the evolution of the Docker deployment.

### `deploy-docker-ec2-user.yaml`

This version targets a static `docker_servers` inventory and:

- Installs Docker
- Starts the Docker service
- Installs Docker Compose as a CLI plugin
- Detects remote CPU architecture with `uname -m`
- Adds `ec2-user` to the Docker group
- Resets the SSH connection so new group membership becomes effective
- Verifies group membership
- Verifies Docker access with `docker ps`
- Copies the Compose file
- Logs in to Docker
- Starts the application stack with `community.docker.docker_compose_v2`

### `deploy-docker-new-user.yaml`

This version moves to a dedicated Linux user and an AWS tag-based target group:

- Waits for EC2 SSH readiness
- Installs Docker
- Starts Docker
- Installs Docker Compose
- Creates a dedicated Linux user
- Runs container-management tasks as that user
- Copies the Compose file
- Logs in to Docker
- Starts the containers

### Static Inventory Example

The earlier EC2 workflow also contains a static inventory:

```ini
[docker_servers]
3.133.121.187

[docker_servers:vars]
ansible_ssh_private_key_file=/home/josep/.ssh/id_rsa
ansible_user=ec2-user
```

This is useful for showing the progression from static addressing toward AWS inventory discovery.

---

# Project 3 — Jenkins + Ansible with AWS Dynamic Inventory

## Overview

This is a separate automation workflow from Project 2.

The AWS EC2 infrastructure already exists before the Jenkins pipeline runs. Jenkins does **not** execute Terraform in the demonstrated pipeline.

Jenkins orchestrates the configuration workflow through a dedicated Ansible Control Node.

## Architecture

```text
                       GitHub
                          |
                          v
                   Jenkins Pipeline
                          |
                          v
                 Ansible Control Node
                          |
              +-----------+-----------+
              |                       |
              v                       v
       AWS Dynamic Inventory    Ansible Playbook
              |                       |
              +-----------+-----------+
                          |
                          v
                 Discover/Target EC2
                          |
               +----------+----------+
               |                     |
               v                     v
        EC2 Managed Node 1    EC2 Managed Node 2
               |                     |
               +----------+----------+
                          |
                          v
               Docker / Docker Compose
```

---

## AWS Dynamic Inventory

The committed EC2 inventory configuration currently contains:

```yaml
---
plugin: aws_ec2
regions:
  - us-east-2

# keyed_groups:
#   - key: tags
#     prefix: tag
#   - key: instance_type
#     prefix: instance_type
```

and `deploy-to-ec2/ansible.cfg` points Ansible to that inventory:

```ini
[defaults]
host_key_checking = False
inventory = inventory_aws_ec2.yaml

enable_plugins = aws_ec2

remote_user = ec2-user
private_key_file = /home/josep/.ssh/ansible-key.pem
```

The `keyed_groups` example is retained but currently commented in the committed inventory file. Some playbook versions target tag-derived groups such as `tag_Environment_dev`, so those groups require the corresponding keyed-group configuration to be enabled when that variant is used.

This is documented explicitly so the README reflects the repository as it currently exists rather than pretending every historical variant is active at the same time.

---

## Jenkins Pipeline Workflow

### Step 1 — Source Checkout

Jenkins checks out the `feature/ansible` branch from the application repository:

```text
Started by user Godswill
Checking out git https://github.com/Godswill012/java-maven-app.git
using credential github-credentials
Checking out Revision 541f76aa18b7259d864e61d2f23aee44867bf2eb
Commit message: "Update Jenkins and Ansible configuration for dynamic AWS inventory"
```

### Step 2 — Transfer Ansible Files

Jenkins copies the Ansible configuration, inventory and playbook to the Ansible Control Node:

```text
scp -o StrictHostKeyChecking=no \
ansible/ansible.cfg \
ansible/inventory_aws_ec2.yaml \
ansible/my-playbook.yaml \
root@<ANSIBLE_CONTROL_NODE_IP>:/root
```

### Step 3 — Inject SSH Credentials

Jenkins retrieves the EC2 SSH private key from Jenkins Credentials. The console masks the credential value:

```text
[Pipeline] withCredentials
Masking supported pattern matches of $keyfile

+ scp **** root@<ANSIBLE_CONTROL_NODE_IP>:/root/ssh-key.pem
```

### Step 4 — Prepare the Ansible Control Node

The pipeline remotely executes the preparation script and verifies required dependencies:

```text
ansible is already the newest version (9.2.0+dfsg-0ubuntu5).
python3-boto3 is already the newest version (1.34.46+dfsg-1ubuntu1).
```

### Step 5 — Execute the Ansible Playbook

Jenkins remotely triggers:

```text
ansible-playbook my-playbook.yaml
```

### Step 6 — Configure the EC2 Managed Nodes

The successful run shows both discovered EC2 hosts being configured:

```text
TASK [Install Docker]
changed: [ec2-18-227-97-7.us-east-2.compute.amazonaws.com]
changed: [ec2-3-143-245-208.us-east-2.compute.amazonaws.com]

TASK [Start docker daemon]
changed: [ec2-18-227-97-7.us-east-2.compute.amazonaws.com]
changed: [ec2-3-143-245-208.us-east-2.compute.amazonaws.com]

TASK [Install docker-compose]
changed: [ec2-18-227-97-7.us-east-2.compute.amazonaws.com]
changed: [ec2-3-143-245-208.us-east-2.compute.amazonaws.com]
```

### Step 7 — Verify the Pipeline

```text
PLAY RECAP

ec2-18-227-97-7.us-east-2.compute.amazonaws.com :
ok=7 changed=4 unreachable=0 failed=0

ec2-3-143-245-208.us-east-2.compute.amazonaws.com :
ok=7 changed=4 unreachable=0 failed=0

Finished: SUCCESS
```

---

## Full Jenkins Execution Evidence

The full sanitized console output is included below as evidence of the completed workflow.

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
\+ scp -o StrictHostKeyChecking=no ansible/ansible.cfg ansible/inventory_aws_ec2.yaml ansible/my-playbook.yaml root@<ANSIBLE_CONTROL_NODE_IP>:/root
[Pipeline] withCredentials
Masking supported pattern matches of $keyfile
[Pipeline] {
[Pipeline] sh
\+ scp **** root@<ANSIBLE_CONTROL_NODE_IP>:/root/ssh-key.pem
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
Executing script on ansible-server[<ANSIBLE_CONTROL_NODE_IP>]: /var/jenkins_home/workspace/ansible-pipeline/prepare-ansible-server.sh

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
Executing command on ansible-server[<ANSIBLE_CONTROL_NODE_IP>]: ansible-playbook my-playbook.yaml sudo: false

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
ec2-18-227-97-7.us-east-2.compute.amazonaws.com : ok=7    changed=4    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
ec2-3-143-245-208.us-east-2.compute.amazonaws.com : ok=7    changed=4    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   

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
```

</details>

---

# Project 4 — Refactoring Ansible with Roles

## Overview

The role-based playbook demonstrates refactoring from a larger task-oriented playbook into reusable Ansible roles.

The playbook still handles Docker and Docker Compose installation directly, while reusable responsibilities are delegated to roles:

```yaml
- name: Create new linux user
  hosts: aws_ec2
  become: yes
  vars_files:
    - project-vars
  roles:
    - create_user

- name: Start docker containers
  hosts: aws_ec2
  become: yes
  become_user: josep
  vars_files:
    - project-vars
  roles:
    - start_containers
```

## Why This Matters

This helped demonstrate:

- Reusable automation
- Cleaner separation of responsibilities
- Smaller main playbooks
- Easier maintenance
- Moving repeated task groups into roles

---

# Project 5 — Kubernetes Deployment with Ansible

## Overview

Ansible is not limited to configuring Linux hosts over SSH. This project uses the `kubernetes.core.k8s` collection to manage Kubernetes resources.

The playbook runs locally:

```yaml
---
- name: Deploy app in new namespace
  hosts: localhost

  tasks:
    - name: Create a k8s namespace
      kubernetes.core.k8s:
        name: my-app
        api_version: v1
        kind: Namespace
        state: present

    - name: Deploy nginx app
      kubernetes.core.k8s:
        src: /mnt/c/Users/josep/eks-deployment/nginx-deployment.yaml
        state: present
        namespace: my-app
```

## Workflow

```text
Ansible Control Machine
        |
        v
Kubernetes API
        |
        +------> Create Namespace: my-app
        |
        v
Apply Kubernetes Manifest
        |
        v
Deploy Nginx Workload
```

The repository also contains `nexus/ansible-projects/nginx-config.yaml`, which defines an Nginx `Deployment` and a `LoadBalancer` `Service`. The current `deploy-to-k8s.yaml` references a different local manifest path, so this README does not claim that `nginx-config.yaml` is the exact file consumed by that playbook.

## Portability Note

The original lab playbook uses a machine-specific WSL path:

```text
/mnt/c/Users/josep/eks-deployment/nginx-deployment.yaml
```

For a reusable production-style repository, a relative path inside the repository would be preferable.

---

# Project 6 — Nexus Repository Automation

## Overview

The Nexus project demonstrates one of the clearest automation progressions in this repository.

The original `nexus.sh` documents the manual installation procedure:

```text
Update packages
    |
    v
Install Java + net-tools
    |
    v
Download Nexus
    |
    v
Extract Nexus
    |
    v
Create nexus user
    |
    v
Set ownership
    |
    v
Configure nexus.rc
    |
    v
Start Nexus
    |
    v
Verify process and port
```

The Ansible playbook then turns those steps into repeatable automation.

---

## Nexus Automation Workflow

### 1. Install Prerequisites

The playbook refreshes apt metadata and installs Java 17 and `net-tools`.

### 2. Download and Extract Nexus

The playbook:

- Checks whether Nexus is already installed with `stat`
- Downloads the Nexus archive with `get_url`
- Extracts it with `unarchive`
- Finds the versioned Nexus directory
- Renames it to the stable `/opt/nexus` path

### 3. Create the Nexus Service User

The playbook:

- Creates the `nexus` group
- Creates the `nexus` user
- Assigns `/opt/nexus` ownership
- Assigns `/opt/sonatype-work` ownership

### 4. Configure Nexus

The playbook creates `nexus.rc` with:

```text
run_as_user="nexus"
```

and configures the Nexus datastore property required by the lab implementation.

### 5. Start and Verify Nexus

The playbook starts Nexus and then checks:

- Nexus status
- Recent Nexus logs
- Nexus process with `ps`
- Listening ports with `netstat`

A short pause is included before the final network check so Nexus has time to finish booting.

## Manual Script vs Ansible Automation

The shell script is retained as useful historical context because it shows the manual process that was later automated.

It also demonstrates how the implementation evolved: the manual script used an older Java/Nexus procedure, while the Ansible playbook was updated to Java 17 and a specific Nexus 3 archive.

---

# Troubleshooting & Engineering Improvements

## SSH Readiness

New EC2 instances were not always immediately available over SSH after creation.

The Ansible `wait_for` task checks port 22/OpenSSH before continuing.

## SSH Key Mismatch

During testing, Ansible initially returned:

```text
Permission denied (publickey,gssapi-keyex,gssapi-with-mic)
```

I verified SSH separately and identified that the target EC2 instances had been created with a different AWS key pair than the one initially configured.

After using the correct key and updating the Ansible configuration, connectivity succeeded:

```text
ec2-3-143-245-208... | SUCCESS
"ping": "pong"

ec2-18-227-97-7... | SUCCESS
"ping": "pong"
```

## AWS Dynamic Inventory

I worked through AWS inventory-plugin and credential configuration until Ansible could discover the intended EC2 instances.

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
EC2 Discovery
```

## Docker Group Membership

The `ec2-user` Docker playbook explicitly resets the SSH connection after adding the user to the Docker group, then verifies the groups and runs `docker ps` without privilege escalation.

That exercise helped demonstrate that Linux group-membership changes may require a new login session before they take effect.

---

# Security Considerations

The repository is configured to keep sensitive local files out of Git where appropriate.

Practices demonstrated include:

- Jenkins Credentials for SSH credential injection
- Masked credential values in Jenkins console output
- Private key files excluded through `.gitignore`
- Terraform state files excluded from Git
- Sensitive variable files excluded from Git
- No private-key contents included in this README

Some lab configurations intentionally prioritize learning convenience. For example:

```ini
host_key_checking = False
```

and the Jenkins pipeline uses:

```text
StrictHostKeyChecking=no
```

For production use, I would harden SSH host verification, IAM permissions, secret storage, key persistence and credential delivery.

---

# Repository Structure

```text
ansible-automation/
├── .gitignore
├── README.md
├── ansible.cfg
├── hosts
├── my-playbook.yaml
├── deploy-node.yaml
│
├── deploy-to-ec2/
│   ├── .gitignore
│   ├── .terraform.lock.hcl
│   ├── ansible.cfg
│   ├── hosts
│   ├── inventory_aws_ec2.yaml
│   ├── main.tf
│   ├── providers.tf
│   ├── deploy-docker-ec2-user.yaml
│   ├── deploy-docker-new-user.yaml
│   ├── deploy-docker-with-roles.yaml
│   └── deploy-to-k8s.yaml
│
└── nexus/
    └── ansible-projects/
        ├── ansible.cfg
        ├── hosts
        ├── deploy-nexus.yaml
        ├── deploy-node.yaml
        ├── nexus.sh
        └── nginx-config.yaml
```

Sensitive/local files such as `project-vars`, private keys, Terraform state and `terraform.tfvars` are intentionally not shown as committed project artifacts.

---

# What I Built

Across these projects I:

- Configured Linux servers with Ansible
- Installed and managed Nginx
- Automated Node.js application deployment
- Created and used dedicated application users
- Provisioned AWS infrastructure with Terraform
- Dynamically created multiple EC2 instances using `for_each`
- Integrated Terraform-created infrastructure with Ansible
- Implemented EC2 SSH readiness checks
- Automated Docker and Docker Compose installation
- Managed Docker group membership
- Used static and AWS dynamic inventories
- Integrated Jenkins with an Ansible Control Node
- Used boto3 for AWS inventory discovery
- Managed Jenkins SSH credentials
- Executed Ansible remotely from Jenkins
- Refactored automation into Ansible roles
- Managed Kubernetes resources with `kubernetes.core.k8s`
- Automated Nexus installation and verification
- Troubleshot SSH, inventory, permissions and startup issues

---

# What I Learned

The biggest lesson from this repository was understanding that DevOps tools can work together while still having different responsibilities.

- **Terraform** provisions infrastructure.
- **Ansible** performs configuration management.
- **Jenkins** orchestrates automation workflows.
- **AWS dynamic inventory** allows Ansible to discover changing infrastructure.
- **Docker and Docker Compose** provide application runtime and multi-container orchestration.
- **Kubernetes** provides container orchestration at cluster level.

The projects also showed me why automation often evolves through several versions. I worked with static inventories before dynamic inventory, direct playbook tasks before reusable roles, manual Nexus installation before Ansible automation, and simple provisioning/configuration coupling before separating responsibilities more clearly.

Troubleshooting was an important part of that learning. SSH readiness, SSH key mismatches, dynamic inventory configuration, Linux group membership and service startup all required understanding what was happening underneath the automation rather than only following commands.

---

# Technologies Used

- Ansible
- Terraform
- Jenkins
- AWS EC2
- AWS VPC
- AWS Dynamic Inventory
- Python
- boto3
- Docker
- Docker Compose
- Kubernetes
- Nginx
- Nexus Repository
- Node.js
- npm
- Linux
- SSH
- Git
- GitHub
