from prefect import flow, get_run_logger, task


@task
def download_flow_task(url: str) -> None:
    logger = get_run_logger()
    logger.info("download_flow_task started")


@flow(name="task-flow", log_prints=True)
def task_flow(url: str = "http://localhost:8080/api/flows/") -> None:
    download_flow_task(url)
