from time import sleep

from prefect import flow, get_run_logger, task


@task
def hello_task() -> None:
    logger = get_run_logger()
    logger.info("Hello hello_task!")
    logger.info("Sleeping.....")
    sleep(60)
    logger.info("Awake!")


@flow
def hello_flow() -> None:
    hello_task()


if __name__ == "__main__":
    flow()
