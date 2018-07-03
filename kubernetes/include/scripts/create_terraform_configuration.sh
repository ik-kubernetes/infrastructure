#!/usr/bin/env bash
AWS_REGION = "${AWS_REGION?Please provide an AWS region to operate in.}"
AWS_ACCESS_KEY_ID = "${AWS_ACCESS_KEY_ID?Please provide an access key.}"
AWS_SECRET_ACCESS_KEY = "${AWS_SECRET_ACCESS_KEY?Please provide a secret key.}"
TERRAFORM_STATE_S3_BUCKET = "${TERRAFORM_BACKEND_S3_BUCKET?Please provide the S3 bucket into which state  will be stored.}"
TERRAFORM_STATE_S3_KEY = "${TERRAFORM_BACKEND_S3_KEY?Please provide the S3 key within the bucket into which state  will be stored.}"
KUBERNETES_INFRASTRUCTURE_SOURCE_PATH = "$(git rev-parse --show-toplevel)/kubernetes/control_plane/aws"
TERRAFORM_BACKEND_PATH = "${KUBERNETES_INFRASTRUCTURE_SOURCE_PATH}/backend.tf"
TERRAFORM_PROVIDER_PATH = "${KUBERNETES_INFRASTRUCTURE_SOURCE_PATH}/provider.tf"
AUTOGENERATED_TERRAFORM_TFVARS_PATH = "${KUBERNETES_INFRASTRUCTURE_SOURCE_PATH}/terraform.tfvars"
TEMPLATED_TERRAFORM_TFVARS_PATH = "${AUTOGENERATED_TERRAFORM_TFVARS_PATH}.template"

create_s3_backend() {
  cat >"$TERRAFORM_BACKEND_PATH" <<BACKEND_CONFIG
terraform {
  backend "s3" {
    bucket = "${TERRAFORM_STATE_S3_BUCKET}"
    key = "${TERRAFORM_STATE_S3_KEY}"
    region = "${AWS_REGION}"
  }
}
BACKEND_CONFIG
}

configure_aws_provider() {
  cat >"${TERRAFORM_PROVIDER_PATH}" <<PROVIDER_CONFIG
provider "aws" {
  region = "${AWS_REGION}"
  access_key = "${AWS_ACCESS_KEY_ID}"
  secret_key = "${AWS_SECRET_ACCESS_KEY}"
}
PROVIDER_CONFIG
}

configure_terraform_variables() {
  if [ ! -z "$TEMPLATED_TERRAFORM_TFVARS_PATH" ]
  then
    >&2 echo "ERROR: Please provide terraform.tfvars template file at $TEMPLATED_TERRAFORM_TFVARS_PATH"
    return 1
  fi
  rm "$AUTOGENERATED_TERRAFORM_TFVARS_PATH"
  cat "$TEMPLATED_TERRAFORM_TFVARS_PATH" | \
    while read -r key_value_pair
    do
      if ! _is_key_value_pair "$key_value_pair" 
      then
        _copy_line_verbatim "$key_value_pair" "$AUTOGENERATED_TERRAFORM_TFVARS_PATH"
        continue
      fi
      terraform_variable=$(echo "$key_value_pair" | cut -f1 -d =)
      env_var_to_use=$(echo "$key_value_pair" | cut -f2 -d =)
      env_var_value="${!env_var_to_use}"
      if [ -z "$env_var_value" ]
      then
        _comment_out_missing_terraform_variable "$terraform_variable" "$AUTOGENERATED_TERRAFORM_TFVARS_PATH"
      else
        _fill_in_templated_value "$terraform_variable" "$AUTOGENERATED_TERRAFORM_TFVARS_PATH" 
      fi
    done
}

_comment_out_missing_terraform_variable() {
  terraform_variable="${1?Please provide the Terraform variable.}"
  tfvars_path="${2?Please provide the path to the Terraform variables to manipulate.}"
  echo "#${terraform_variable}=\"nothing provided\"" >> "$tfvars_path"
}

_fill_in_templated_value() {
  terraform_variable="${1?Please provide the Terraform variable.}"
  tfvars_path="${2?Please provide the path to the Terraform variables to manipulate.}"
  actual_value="${3?Please provide the actual value being substituted.}"
  echo "${terraform_variable}=\"$env_var_value\"" >> "$tfvars_path"
}

_is_key_value_pair() {
  key_value_pair_under_test="$1"
  $(echo "$key_value_pair_under_test" | grep -q "^[a-zA-Z]{1,}=\".*\"$")
}

_copy_line_verbatim() {
  key_value_pair="${1?Please provide a kvp.}"
  tfvars_path="${2?Please provide a path to the tfvars file being generated.}"
  echo "$key_value_pair" >> "$tfvars_path"
}