"""
See https://docs.prefect.io/2.13.0/concepts/deployments/#create-a-deployment-from-a-python-object
"""

from prefect.deployments.deployments import Deployment
from prefect.infrastructure import KubernetesJob

import examples.child_flow
import examples.dask_kubes_flow
import examples.param_flow
import examples.parent_flow
import tools.storage

dask_kubes: Deployment = Deployment.build_from_flow(
    name="python",
    flow=examples.dask_kubes_flow.dask_kubes,
    # output to disk is optional, but we save the yaml representation so we can compare across versions
    output="deployments/deployment-dask-kubes.yaml",
    description="dask kubes",
    version="snapshot",
    work_pool_name="kubes-pool",
    infrastructure=KubernetesJob(),  # type: ignore
    infra_overrides=dict(
        image="prefect-registry:5000/flow:latest",
        image_pull_policy="Always",
        service_account_name="prefect-flows",
        finished_job_ttl=300,
    ),
    parameters={"names": ["arthur", "trillian", "ford", "marvin"]},
)


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


parent: Deployment = Deployment.build_from_flow(
    name="python",
    flow=examples.parent_flow.parent,
    output="deployments/deployment-parent.yaml",
    description="deployment using s3 storage",
    version="snapshot",
    tags=["s3"],
    work_pool_name="default-agent-pool",
    storage=tools.storage.minio_flows(),
    path="parent",
    infrastructure=KubernetesJob(),  # type: ignore
    infra_overrides=dict(
        image="prefect-registry:5000/flow:latest",
        image_pull_policy="Always",
        # used to download the stored flow from minio when the job starts
        customizations=aws_creds_customizations,
        service_account_name="prefect-flows",
        finished_job_ttl=300,
    ),
)

child: Deployment = Deployment.build_from_flow(
    name="python",
    flow=examples.child_flow.child,
    output="deployments/deployment-child.yaml",
    description="deployment using local storage",
    version="snapshot",
    work_pool_name="kubes-pool",
    infrastructure=KubernetesJob(),  # type: ignore
    infra_overrides=dict(
        image="prefect-registry:5000/flow:latest",
        image_pull_policy="Always",
        service_account_name="prefect-flows",
        finished_job_ttl=300,
    ),
)


def apply(deployment: Deployment) -> None:
    did = deployment.apply()
    print(f"Created deployment 'examples/{deployment.flow_name}/{deployment.name}' ({did})")


if __name__ == "__main__":
    apply(dask_kubes)
    apply(parent)
    apply(child)
