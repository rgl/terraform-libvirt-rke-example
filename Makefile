help:
	@echo 'Type one of the following commands:'
	@echo '  make recreate	# destroy and then create the cluster'
	@echo '  make apply		# create/update the cluster'
	@echo '  make destroy	# destroy the cluster'

recreate: destroy apply

apply:
	terraform init
	terraform plan -out=tfplan
	terraform apply tfplan

destroy:
	terraform destroy --auto-approve
	rm -rf *.log kubeconfig.yaml terraform-provider-rke-tmp-* terraform.tfstate* tfplan


.PHONY: help recreate apply destroy
