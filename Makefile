CLUSTER_NAME ?= cni-arp-test
CNI_PLUGINS_VERSION ?= v1.9.1
NODE_NAME = $(CLUSTER_NAME)-control-plane

ARP_POISON_IMAGE = arp-poison:latest

.PHONY: help deploy undeploy deploy-client-server install-cni-plugins configure-node build-arp-poison deploy-arp-poison undeploy-arp-poison clean-arp-poison-image client-logs arp-poison-logs clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  %-25s %s\n", $$1, $$2}'

deploy: ## Create kind cluster with bridge CNI
	kind create cluster --name $(CLUSTER_NAME) --config kind-config.yaml
	$(MAKE) install-cni-plugins
	$(MAKE) configure-node
	kubectl wait --for=condition=Ready node/$(NODE_NAME) --timeout=120s

configure-node: ## Load br_netfilter and set iptables FORWARD rules
	docker exec $(NODE_NAME) modprobe br_netfilter
	docker exec $(NODE_NAME) sysctl -w net.bridge.bridge-nf-call-iptables=1
	docker exec $(NODE_NAME) sysctl -w net.ipv4.ip_forward=1
	docker exec $(NODE_NAME) iptables -I FORWARD -s 10.10.0.0/16 -j ACCEPT
	docker exec $(NODE_NAME) iptables -I FORWARD -d 10.10.0.0/16 -j ACCEPT

install-cni-plugins: ## Install CNI plugin binaries on the kind node
	docker exec $(NODE_NAME) sh -c '\
		ARCH=$$(uname -m) && \
		case $$ARCH in x86_64) ARCH=amd64;; aarch64) ARCH=arm64;; esac && \
		curl -fsSL https://github.com/containernetworking/plugins/releases/download/$(CNI_PLUGINS_VERSION)/cni-plugins-linux-$$ARCH-$(CNI_PLUGINS_VERSION).tgz \
		| tar -xz -C /opt/cni/bin \
	'

deploy-client-server: ## Deploy agnhost server + client that curls /clientip
	kind load docker-image $(ARP_POISON_IMAGE) --name $(CLUSTER_NAME)
	kubectl apply -f deployment-server.yaml
	kubectl apply -f deployment-client.yaml
	kubectl rollout status deployment/server --timeout=120s
	kubectl rollout status deployment/client --timeout=120s

undeploy-client-server: ## Remove client and server deployments
	kubectl delete -f deployment-server.yaml
	kubectl delete -f deployment-client.yaml

build-arp-poison: ## Build the arp-poison container image
	docker build -t $(ARP_POISON_IMAGE) arp-poison/

deploy-arp-poison: build-arp-poison ## Build, load, and deploy the ARP poisoning pod
	kind load docker-image $(ARP_POISON_IMAGE) --name $(CLUSTER_NAME)
	kubectl apply -f deployment-arp-poison.yaml
	kubectl rollout status deployment/arp-poison --timeout=120s

undeploy-arp-poison: ## Remove the ARP poisoning deployment
	kubectl delete -f deployment-arp-poison.yaml

client-logs: ## Follow client pod logs
	kubectl logs -f deployment/client

arp-poison-logs: ## Follow arp-poison pod logs
	kubectl logs -f deployment/arp-poison

clean-arp-poison-image: ## Remove the arp-poison Docker image
	docker rmi $(ARP_POISON_IMAGE)

undeploy: ## Delete the kind cluster
	kind delete cluster --name $(CLUSTER_NAME)

clean: undeploy clean-arp-poison-image ## Full cleanup: delete cluster and remove images
