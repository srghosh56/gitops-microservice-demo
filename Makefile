CLUSTER ?= skao-demo
IMAGE   ?= demo-service
TAG     ?= 0.1.0

.PHONY: test build run cluster load platform argocd-app argocd-password helm-check \
        pf-grafana pf-prometheus pf-argocd pf-app traffic destroy

test:            ## Run unit tests
	python -m pytest -q

build:           ## Build the container image
	docker build -t $(IMAGE):$(TAG) .

run:             ## Run the container locally on http://localhost:8081
	docker run --rm -p 8081:8080 -e APP_VERSION=$(TAG) $(IMAGE):$(TAG)

cluster:         ## Create the local kind cluster
	kind create cluster --name $(CLUSTER)

load:            ## Copy the local image into the kind node
	kind load docker-image $(IMAGE):$(TAG) --name $(CLUSTER)

platform:        ## Install monitoring + Argo CD with Terraform (needs TF_VAR_grafana_admin_password)
	cd terraform && terraform init && terraform apply

helm-check:      ## Lint and render the chart
	helm lint charts/demo-service
	helm template demo-service charts/demo-service --namespace demo

argocd-app:      ## Register the app with Argo CD
	kubectl apply -f argocd/application.yaml

argocd-password: ## Print the initial Argo CD admin password
	kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode; echo

pf-grafana:
	kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80

pf-prometheus:
	kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090

pf-argocd:
	kubectl -n argocd port-forward svc/argocd-server 8080:80

pf-app:
	kubectl -n demo port-forward svc/demo-service 8081:80

traffic:         ## Send ~10 req/s to the app for a minute (run pf-app first)
	for i in $$(seq 1 600); do curl -s -o /dev/null http://localhost:8081/; sleep 0.1; done

destroy:         ## Delete the whole cluster
	kind delete cluster --name $(CLUSTER)
