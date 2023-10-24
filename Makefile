include *.mk

export KUBECONFIG=$(HOME)/.kube/config

## create cluster and install minio and prefect
kubes: kubes-minio kubes-prefect

## install minio
kubes-minio:
	helm repo add bitnami https://charts.bitnami.com/bitnami
# root user and password is stored in the minio secret
	helm upgrade --install minio bitnami/minio --set auth.rootUser=minioadmin --set auth.rootPassword=minioadmin \
		--wait --debug > /dev/null
	kubectl apply -f infra/lb-minio.yaml
	kubectl exec deploy/minio -- mc mb -p local/minio-flows

## install kuberay operator using quickstart manifests
kubes-ray: KUBERAY_VERSION=v0.6.0
kubes-ray:
# install CRDs
	kubectl apply --server-side -k "github.com/ray-project/kuberay/manifests/cluster-scope-resources?ref=${KUBERAY_VERSION}&timeout=90s"
# install kuberay operator
	kubectl apply -k "github.com/ray-project/kuberay/manifests/base?ref=${KUBERAY_VERSION}&timeout=90s"
	kubectl apply -f infra/ray-cluster.complete.yaml
	kubectl apply -f infra/lb-ray.yaml
	@echo -e "\nProbing for the ray cluster to be available (~3 mins)..." && \
		while ! $(venv)/bin/python -m flows.ping_ray; do sleep 10; done

## upgrade prefect helm chart repo
prefect-helm-repo:
	helm repo add prefect https://prefecthq.github.io/prefect-helm
	helm repo update prefect

## install prefect server, worker and agent into kubes cluster
kubes-prefect: prefect-helm-repo
	kubectl apply -f infra/rbac-dask.yaml
	kubectl apply -f infra/sa-flows.yaml
	helm upgrade --install prefect-server prefect/prefect-server --version=2023.09.07 \
		--values infra/values-server.yaml --wait --debug > /dev/null
	helm upgrade --install prefect-worker prefect/prefect-worker --version=2023.09.07 \
		--values infra/values-worker.yaml --wait --debug > /dev/null
	helm upgrade --install prefect-agent prefect/prefect-agent --version=2023.09.07 \
		--values infra/values-agent.yaml --wait --debug > /dev/null
	@echo -e "\nProbing for the prefect API to be available (~30 secs)..." && \
		while ! curl -fsS http://localhost:4200/api/admin/version ; do kubectl port-forward service/prefect-server 4200:4200 & ; done && echo

## restart prefect server (delete all flows)
server-restart:
	kubectl rollout restart deploy/prefect-server

## delete objects in minio bucket
minio-empty:
	kubectl exec deploy/minio -- mc rm local/minio-flows/ --recursive --force

## show the prefect job manifest
prefect-job-manifest:
	prefect kubernetes manifest flow-run-job

## run parameterised flow
param-flow: export PREFECT_API_URL=http://localhost/api
param-flow: $(venv)
	$(venv)/bin/python -m flows.param_flow

## run dask flow
dask-flow: export PREFECT_API_URL=http://localhost/api
dask-flow: $(venv)
	$(venv)/bin/python -m flows.dask_flow

## run ray flow
ray-flow: export PREFECT_LOCAL_STORAGE_PATH=/tmp/prefect/storage # see https://github.com/PrefectHQ/prefect-ray/issues/26
# PREFECT_API_URL needs to be accessible from the process running the flow and within the ray cluster
# to make this work locally, add 127.0.0.1 prefect-server to /etc/hosts TODO: find a better fix
dask-flow: export PREFECT_API_URL=http://localhost/api
ray-flow: $(venv)
	$(venv)/bin/python -m flows.ray_flow

## run sub flow
sub-flow: $(venv)
	$(venv)/bin/python -m flows.sub_flow

## build and push docker image
publish:
	docker buildx bake --push

## deploy flows to run on kubernetes
deploy: export PREFECT_API_URL=http://localhost/api
deploy: export AWS_ACCESS_KEY_ID=minioadmin
deploy: export AWS_SECRET_ACCESS_KEY=minioadmin
deploy: $(venv) publish
	kubectl port-forward service/prefect-server 4200:4200 > /dev/null &
	kubectl port-forward service/minio 9000:9000 > /dev/null &
	kubectl port-forward service/minio 9001:9001 > /dev/null &
	kubectl port-forward service/raycluster-complete-head-svc 6379:6379 > /dev/null &
	kubectl port-forward service/raycluster-complete-head-svc 8265:8265 > /dev/null &
	kubectl port-forward service/raycluster-complete-head-svc 10001:10001 > /dev/null &

# use minio as the s3 remote file system & deploy flows via python
	set -e && . config/fsspec-env.sh && $(venv)/bin/python -m flows.deploy
# deploy flows via prefect.yaml
	$(venv)/bin/prefect --no-prompt deploy --all
	$(venv)/bin/prefect deployment ls
	for deployment in param/yaml retry/yaml dask-kubes/python parent/python; do
		@echo deployment run $$deployment
		$(venv)/bin/prefect deployment run $$deployment;
	done
	$(venv)/bin/prefect flow-run ls
	@echo Visit http://localhost:4200

## start prefect ui
ui: $(venv)
	PATH="$(venv)/bin:$$PATH" prefect server start

## show kube logs for the server and worker
kubes-logs:
	kubectl logs -l "app.kubernetes.io/name in (prefect-server, prefect-worker, prefect-agent)" -f --tail=-1

## show kube logs for flows
kubes-logs-jobs:
	kubectl logs -l "job-name" -f --tail=-1

## show kube logs for dask scheduler and workers
kubes-logs-dask:
	kubectl logs -l "app=dask" -f --tail=-1

## show flow run logs
logs: export PREFECT_API_URL=http://localhost:4200/api
logs: assert-id
	curl -H "Content-Type: application/json" -X POST --data '{"logs":{"flow_run_id":{"any_":["$(id)"]},"level":{"ge_":0}},"sort":"TIMESTAMP_ASC"}' -s "http://localhost:4200/api/logs/filter" | jq -r '.[] | [.timestamp,.level,.message] |@tsv'

## show flow runs
flow-runs: export PREFECT_API_URL=http://localhost:4200/api
flow-runs:
	$(venv)/bin/prefect flow-run ls

## access .db in kubes
kubes-db:
	kubectl exec -i -t deploy/prefect-server -- /bin/bash -c 'hash sqlite3 || (apt-get update && apt-get install sqlite3) && sqlite3 ~/.prefect/prefect.db'

## upgrade to latest version of prefect
upgrade:
	latest=$$(PIP_REQUIRE_VIRTUALENV=false pip index versions prefect | tail -n +1 | head -n1 | sed -E 's/.*\(([0-9.]+)\)/\1/') && \
		rg -l 2.13.0 | xargs sed -i '' "s/2.13.0/$$latest/g"
	make install

## forward traefik dashboard
tdashboard:
	@echo Forwarding traefik dashboard to http://localhost:8999/dashboard/
	tpod=$$(kubectl get pod -n kube-system -l app.kubernetes.io/name=traefik -o custom-columns=:metadata.name --no-headers=true) && \
		kubectl -n kube-system port-forward $$tpod 8999:9000

## inspect block document
api-block-doc: assert-id
	@curl -s "http://localhost:4200/api/block_documents/$(id)" | jq -r 'if .message then .message else {data, block_type:{ name: .block_type.name }} end'

assert-id:
ifndef id
	@echo Missing id variable, eg: make $(MAKECMDGOALS) id=3af1d9d7-d52b-4251-87a0-dfe9c82daa3f
	@exit 42
endif
