clean:
    find . -name "_.*.gen.tf" -type f | xargs -r rm -rv
    find . -name ".terraform.lock.hcl" -type f | xargs -r rm -rv
    find . -name ".terraform" -type d | xargs -r rm -rv
    find . -name ".terragrunt-cache" -type d | xargs -r rm -rv

login env:
    doppler run \
    -- assume-role login -p {{env}}Terraform

init dir:
    doppler run \
    --name-transformer tf-var  \
    -- terragrunt init --tf-path terraform \
    --reconfigure \
    --working-dir {{infraDir}}/{{dir}}

init-all:
    doppler run \
    --name-transformer tf-var  \
    -- terragrunt stack run --tf-path terraform \
    --working-dir {{infraDir}} \
    init

init-migrate dir:
    doppler run \
    --name-transformer tf-var  \
    -- terragrunt init --tf-path terraform -migrate-state \
    --working-dir {{infraDir}}/{{dir}}

init-all-migrate:
    doppler run \
    --name-transformer tf-var  \
    -- terragrunt stack run --tf-path terraform \
    --working-dir {{infraDir}} \
    init -migrate-state

validate dir:
    doppler run \
    --name-transformer tf-var  \
    -- terragrunt validate --tf-path terraform \
    --working-dir {{infraDir}}/{{dir}}

validate-all:
    doppler run \
    --name-transformer tf-var  \
    -- terragrunt validate --tf-path terraform \
    --working-dir {{infraDir}}

apply dir:
    doppler run \
    --name-transformer tf-var  \
    -- terragrunt apply --tf-path terraform \
    -auto-approve \
    --working-dir {{infraDir}}/{{dir}}

apply-all:
    doppler run \
    --name-transformer tf-var  \
    -- terragrunt --non-interactive stack run --tf-path terraform \
    --working-dir {{infraDir}} \
    apply

plan dir:
    doppler run \
    --name-transformer tf-var  \
    -- terragrunt plan --tf-path terraform \
    --working-dir {{infraDir}}/{{dir}}

plan-all:
    doppler run \
    --name-transformer tf-var  \
    -- terragrunt stack run --tf-path terraform \
    --working-dir {{infraDir}} \
    plan

destroy dir:
    doppler run \
    --name-transformer tf-var  \
    -- terragrunt destroy --tf-path terraform \
    -auto-approve \
    --working-dir {{infraDir}}/{{dir}}

destroy-target dir target:
    doppler run \
    --name-transformer tf-var  \
    -- terragrunt destroy --tf-path terraform \
    --target {{target }} \
    --working-dir {{infraDir}}/{{dir}}

destroy-all:
    doppler run \
    --name-transformer tf-var  \
    -- terragrunt --non-interactive stack run --tf-path terraform \
    --working-dir {{infraDir}} \
    destroy

import dir tf_resource aws_resource:
    doppler run \
    --name-transformer tf-var  \
    -- terragrunt import --tf-path terraform \
    --working-dir {{infraDir}}/{{dir}} \
    {{tf_resource}} {{aws_resource}}

state-list dir:
    doppler run \
    --name-transformer tf-var  \
    -- terragrunt state list --tf-path terraform \
    --working-dir {{infraDir}}/{{dir}}

output dir:
    doppler run \
    --name-transformer tf-var  \
    -- terragrunt output --tf-path terraform \
    --working-dir {{infraDir}}/{{dir}}

output-module-groups:
    doppler run \
    --name-transformer tf-var  \
    -- terragrunt output-module-groups --tf-path terraform \
    --working-dir {{infraDir}}

fmt:
    doppler run \
    --name-transformer tf-var  \
    -- terraform fmt \
    --recursive

@init-module dir:
    mkdir -p {{infraDir}}/{{dir}}/env-config/us-east-1

    touch {{infraDir}}/{{dir}}/env-config/common.tfvars
    touch {{infraDir}}/{{dir}}/env-config/us-east-1/common.tfvars
    touch {{infraDir}}/{{dir}}/env-config/us-east-1/dev.tfvars
    touch {{infraDir}}/{{dir}}/env-config/us-east-1/prod.tfvars
    touch {{infraDir}}/{{dir}}/_outputs.tf
    touch {{infraDir}}/{{dir}}/_inputs.tf
    touch {{infraDir}}/{{dir}}/_locals.tf
    touch {{infraDir}}/{{dir}}/_data.tf
    touch {{infraDir}}/{{dir}}/_variables.tf
    touch {{infraDir}}/{{dir}}/main.tf
    touch {{infraDir}}/{{dir}}/terragrunt.hcl

    echo 'asset_name = "{{dir}}"' >> {{infraDir}}/{{dir}}/env-config/common.tfvars
    echo 'locals {}' >> {{infraDir}}/{{dir}}/_locals.tf
    echo 'environment = "dev"' >> {{infraDir}}/{{dir}}/env-config/us-east-1/dev.tfvars
    echo 'environment = "prod"' >> {{infraDir}}/{{dir}}/env-config/us-east-1/prod.tfvars
    echo 'include "root" { path = find_in_parent_folders() }' >> {{infraDir}}/{{dir}}/terragrunt.hcl
    echo 'data "aws_caller_identity" "current" {}' >> {{infraDir}}/{{dir}}/_data.tf
    echo 'data "aws_region" "current" {}' >> {{infraDir}}/{{dir}}/_data.tf
    @# {{infraDir}}/{{dir}} created.

