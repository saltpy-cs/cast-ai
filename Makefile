.PHONY: create destroy kubeconfig disconnect

SHELL   := /bin/bash
TF_DIR  := terraform
load_env = set -a; [ -f .env ] && source ./.env; set +a

create:
	@$(load_env); \
	test -n "$$TF_VAR_allowed_cidrs" || { echo "ERROR: TF_VAR_allowed_cidrs is not set. Example: TF_VAR_allowed_cidrs='[\"1.2.3.4/32\"]'"; exit 1; }; \
	test -n "$$TF_VAR_castai_api_token" || { echo "ERROR: TF_VAR_castai_api_token is not set."; exit 1; }; \
	cd $(TF_DIR) && terraform init -upgrade && terraform apply -auto-approve

destroy:
	@$(load_env); \
	export TF_VAR_allowed_cidrs='["0.0.0.0/0"]'; \
	python3 scripts/prune_state.py; \
	cd $(TF_DIR) && terraform destroy -refresh=false -auto-approve

disconnect:
	@$(load_env); \
	export TF_VAR_allowed_cidrs='["0.0.0.0/0"]'; \
	cd $(TF_DIR) && terraform destroy -auto-approve \
		-target=module.castai_eks_cluster \
		-target=module.castai_eks_role_iam \
		-target=aws_eks_access_entry.castai \
		-target=castai_eks_user_arn.castai_user_arn \
		-target=castai_eks_clusterid.cluster_id

kubeconfig:
	@$(load_env); \
	cd $(TF_DIR) && terraform output -raw configure_kubectl | bash
