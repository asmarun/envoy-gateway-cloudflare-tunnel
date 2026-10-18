ENVOY_GATEWAY_VERSION ?= v1.9.2
MINIKUBE_PROFILE      ?= gw-lab
K8S_VERSION           ?= v1.33.1

.PHONY: help
help: ## Show targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-18s %s\n", $$1, $$2}'

# ---- cluster (pick one; any cluster with a recent Kubernetes works) -----------
.PHONY: cluster-minikube
cluster-minikube: ## Local cluster with Calico, so NetworkPolicy is enforced
	minikube start -p $(MINIKUBE_PROFILE) --driver=docker --cpus=3 --memory=4096 \
	  --cni=calico --kubernetes-version=$(K8S_VERSION)
	minikube addons enable metrics-server -p $(MINIKUBE_PROFILE)   # the Envoy HPA needs it

.PHONY: cluster-kind
cluster-kind: ## Local cluster with kind (NetworkPolicy enforcement varies by kindnet version)
	kind create cluster --name $(MINIKUBE_PROFILE) --image kindest/node:$(K8S_VERSION)

# ---- install -------------------------------------------------------------------
.PHONY: install-envoy
install-envoy: ## Install Envoy Gateway (control plane + CRDs)
	helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm \
	  --version $(ENVOY_GATEWAY_VERSION) -n envoy-gateway-system --create-namespace \
	  -f deploy/helm/envoy-gateway-values.yaml --wait --timeout 5m

.PHONY: deploy
deploy: ## Namespaces, Gateway, policies and the sample app
	kubectl apply -f deploy/envoy-gateway/00-namespaces.yaml
	kubectl apply -f deploy/envoy-gateway/10-gateway.yaml
	kubectl apply -f deploy/envoy-gateway/20-policies.yaml
	kubectl apply -f deploy/sample-app/podinfo.yaml
	kubectl apply -f deploy/sample-app/policies.yaml

.PHONY: netpol
netpol: ## Restrict Envoy ingress to cloudflared only
	kubectl apply -f deploy/cloudflared/networkpolicy.yaml

# ---- tunnels ---------------------------------------------------------------------
.PHONY: tunnel-quick
tunnel-quick: ## No-account demo tunnel (random trycloudflare.com URL)
	kubectl apply -f deploy/cloudflared/quick-tunnel.yaml
	kubectl -n cloudflared rollout status deployment/cloudflared-quick --timeout=120s

.PHONY: tunnel-url
tunnel-url: ## Print the quick-tunnel URL
	@kubectl -n cloudflared logs deployment/cloudflared-quick 2>/dev/null \
	  | grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -1

.PHONY: tunnel-named
tunnel-named: ## Named tunnel (needs TUNNEL_TOKEN from the Terraform example)
	@test -n "$$TUNNEL_TOKEN" || (echo "Set TUNNEL_TOKEN first: export TUNNEL_TOKEN=\$$(terraform -chdir=terraform/cloudflare/example output -raw tunnel_token)" && exit 1)
	kubectl -n cloudflared create secret generic cloudflared-token \
	  --from-literal=token="$$TUNNEL_TOKEN" --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -f deploy/cloudflared/named-tunnel.yaml

# ---- test ----------------------------------------------------------------------------
.PHONY: smoke
smoke: ## Gateway + client-IP checks from inside the cluster
	./scripts/smoke-test.sh

.PHONY: netpol-test
netpol-test: ## Prove a non-cloudflared pod is blocked
	./scripts/netpol-test.sh

.PHONY: resilience-test
resilience-test: ## Delete an Envoy pod while sending traffic through the quick tunnel
	./scripts/resilience-test.sh

.PHONY: up
up: install-envoy deploy ## Install everything except tunnels and NetworkPolicy

# ---- quality -----------------------------------------------------------------------------
.PHONY: lint
lint: ## yamllint, terraform fmt/validate
	yamllint .
	terraform -chdir=terraform/cloudflare fmt -check -recursive
	cd terraform/cloudflare/example && terraform init -backend=false -input=false >/dev/null && terraform validate

# ---- cleanup -----------------------------------------------------------------------------------
.PHONY: clean
clean: ## Remove what this lab installed from the current cluster
	-kubectl delete -f deploy/cloudflared/ --ignore-not-found
	-kubectl delete -f deploy/sample-app/ --ignore-not-found
	-kubectl delete -f deploy/envoy-gateway/ --ignore-not-found
	-helm uninstall eg -n envoy-gateway-system

.PHONY: clean-cluster
clean-cluster: ## Delete the local minikube cluster
	minikube delete -p $(MINIKUBE_PROFILE)
