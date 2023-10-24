"""
See https://docs.prefect.io/2.13.0/concepts/deployments/#create-a-deployment-from-a-python-object
"""

from prefect.deployments.deployments import Deployment
from prefect.infrastructure import KubernetesJob

import flows.hello
import tools.storage

# read aws creds from the minio secret
aws_creds_customizations = [
    {
        "op": "add",
        "path": "/spec/template/spec/containers/0/env/-",
        "value": {
            "name": "AWS_ACCESS_KEY_ID",
            "valueFrom": {
                "secretKeyRef": {
                    "name": "minio",
                    "key": "root-user",
                }
            },
        },
    },
    {
        "op": "add",
        "path": "/spec/template/spec/containers/0/env/-",
        "value": {
            "name": "AWS_SECRET_ACCESS_KEY",
            "valueFrom": {
                "secretKeyRef": {
                    "name": "minio",
                    "key": "root-password",
                }
            },
        },
    },
]


hello_minio_deployment: Deployment = Deployment.build_from_flow(
    name="minio",
    flow=flows.hello.hello_flow,
    output="deployments/deployment-hello-minio.yaml",
    description="deployment using s3 storage",
    version="snapshot",
    # example of adding tags
    tags=["s3"],
    # must run on an agent because workers only support local storage
    # see https://github.com/PrefectHQ/prefect/discussions/10277
    work_pool_name="default-agent-pool",
    # every deployment will overwrite the files in this location
    storage=tools.storage.minio_flows(),
    path="flows/hello",
    infrastructure=KubernetesJob(),  # type: ignore
    infra_overrides=dict(
        image="localhost:32000/flow:latest",
        image_pull_policy="Always",
        customizations=aws_creds_customizations,
        service_account_name="prefect-flows",
        finished_job_ttl=300,
    ),
)


hello_local_deployment: Deployment = Deployment.build_from_flow(
    name="local",
    flow=flows.hello.hello_flow,
    output="deployments/deployment-hello-local.yaml",
    description="deployment using local storage",
    version="snapshot",
    work_pool_name="kubes-pool",
    infrastructure=KubernetesJob(),
    infra_overrides=dict(
        image="localhost:32000/flow:latest",
        image_pull_policy="Always",
        service_account_name="prefect-flows",
        finished_job_ttl=300,
    ),
)


def apply(deployment: Deployment) -> None:
    did = deployment.apply()
    print(f"Created deployment 'tg-tasks/{deployment.flow_name}/{deployment.name}' ({did})")


if __name__ == "__main__":
    apply(hello_minio_deployment)
    apply(hello_local_deployment)
