from uuid import UUID

from tg.cloud.task.context import WorkflowContext
from tg.cloud.task.datagram import Task
from tg.cloud.task.factory import AbsTask
from tg.cloud.task.sample import AbsTaskFactory

from .flows.simple import SimpleTask


class TaskFactory(AbsTaskFactory):
    def __init__(self):
        super(TaskFactory, self).__init__()

    def abs_create(self, context: WorkflowContext, task: Task, descript: dict) -> AbsTask:
        """_summary_

        Args:
            context (WorkflowContext): _description_
            task (Task): _description_
            descript (dict): _description_

        Returns:
            AbsTask: _description_
        """
        task_id = task.instance["id"]
        if task_id == UUID("12345678987654323456787"):
            return SimpleTask(context, task)
