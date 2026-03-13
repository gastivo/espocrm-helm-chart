NAME := espocrm
NAMESPACE := espocrm

helm-install helm-upgrade:
	helm upgrade --install $(NAME) -n $(NAMESPACE) --create-namespace ./ -f ./values.local.yaml

helm-template:
	helm template ./ --name-template $(NAME) --namespace $(NAMESPACE) --values ./values.local.yaml --debug

helm-uninstall:
	helm uninstall $(NAME) -n $(NAMESPACE)
