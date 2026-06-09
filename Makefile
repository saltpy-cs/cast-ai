.PHONY: create destroy kubeconfig disconnect

TF_DIR := terraform

ifneq (,$(wildcard .env))
  include .env
  export
endif

create:
	@test -n "$(TF_VAR_allowed_cidrs)" || (echo "ERROR: TF_VAR_allowed_cidrs is not set. Example: export TF_VAR_allowed_cidrs='[\"1.2.3.4/32\"]'"; exit 1)
	@test -n "$(TF_VAR_castai_api_token)" || (echo "ERROR: TF_VAR_castai_api_token is not set."; exit 1)
	cd $(TF_DIR) && terraform init -upgrade && terraform apply -auto-approve

destroy:
	cd $(TF_DIR) && terraform destroy -auto-approve

disconnect:
	cd $(TF_DIR) && terraform destroy -auto-approve \
		-target=module.castai_eks_cluster \
		-target=module.castai_eks_role_iam \
		-target=aws_eks_access_entry.castai \
		-target=castai_eks_user_arn.castai_user_arn \
		-target=castai_eks_clusterid.cluster_id

kubeconfig:
	cd $(TF_DIR) && terraform output -raw configure_kubectl | bash
