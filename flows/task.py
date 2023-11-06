from urllib.parse import ParseResult, urlparse

from prefect import Flow, flow, get_run_logger, task
from prefect.states import State
from tg.cloud.task.context import WorkflowContext
from tg.cloud.task.datagram import Task, Work
from tg.cloud.task.factory import AbsTask
from tg.cloud.task.sample import ATaskFactory

# https://docs.prefect.io/2.14.2/concepts/task-runners/


@task
def create_work_context(target: ParseResult) -> WorkflowContext:
    logger = get_run_logger()
    logger.info("create_work_context")
    context = WorkflowContext.get(target, ATaskFactory())
    logger.info("create_work_context.update")
    context.update(Work.Status.Progress)
    logger.info("create_work_context.endl")
    return context


@task
def execute_task(task: AbsTask) -> None:
    logger = get_run_logger()
    logger.info("execute_task")
    logger.debug(task)
    try:
        logger.info("execute_task.execute")
        task.execute()
    except Exception as ex:
        task.update(Task.Status.Failed)
        logger.exception(ex)
    else:
        pass


@task
def postprocess_work_context(ctx: WorkflowContext) -> None:
    logger = get_run_logger()
    logger.info("postprocess_work_context")
    logger.debug(ctx)

    has_failed = False
    for item in ctx.tasks:
        has_failed = item.status == Task.Status.Failed
        if has_failed:
            break
    if has_failed:
        ctx.update(Work.Status.Failed)
    else:
        ctx.update(Work.Status.Completed)


@flow(name="task-flow", log_prints=True)
def task_flow(url: str) -> None:
    ctx = create_work_context(urlparse(url))
    tasks = ctx.atasks
    for t in tasks:
        execute_task(t)

    postprocess_work_context(ctx)


if __name__ == "__main__":
    f: Flow = task_flow
    r: State = f("http://localhost:8000/app/workflow?id=ff75a9f6e7e04bd1b6ddd971d08545e9")
