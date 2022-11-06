from __future__ import annotations

from time import sleep
from typing import List

from prefect import allow_failure, flow, get_run_logger, task  # pyright: ignore[reportPrivateImportUsage]


@task
def fail() -> int:
    logger = get_run_logger()
    logger.info("Starting fail task")
    # sleep to demonstrate this runs concurrently
    sleep(3)
    raise Exception("halt and catch fire")


@task
def success() -> int:
    logger = get_run_logger()
    logger.info("Success!")
    return 42


@task
def the_end(scores: List[int]) -> None:
    logger = get_run_logger()
    logger.info(f"Final score is {sum(scores)} 🏆")


@task
def the_end_handle_ex(scores: List[int | Exception]) -> None:
    logger = get_run_logger()
    logger.info(f"Final score is {sum(s for s in scores if isinstance(s, int))} 🏆")


@flow
def handle_failure() -> None:
    logger = get_run_logger()
    logger.info("Starting handle failure flow")

    # start tasks asynchronously
    f = fail.submit()
    s = success.submit()

    # this will run regardless of upstream failure and receive an exception for failed tasks
    the_end_handle_ex.submit([allow_failure(f), allow_failure(s)])  # type: ignore

    # an alternative way

    # wait() will block and return the task state
    # we then filter to completed (ie: successful) states
    completed_states = [s for s in [f.wait(), s.wait()] if s.is_completed()]

    # this will run regardless of upstream failure and only receive the completed tasks
    the_end.submit(completed_states)  # type: ignore

    # NB: unlike @task(trigger=any_successful) in Prefect 1 the dag is dynamically
    # constructed at runtime and so the_end / the_end_handle_ex will not have an upstream edge to the failed task


if __name__ == "__main__":
    handle_failure()
