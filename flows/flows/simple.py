from tg.cloud.task.datagram import Task
from tg.cloud.task.factory import AbsTask


class SimpleTask(AbsTask):
    def __init__(self, context: any, task: Task):
        super(SimpleTask, self).__init__(context, task)

    def main(self) -> dict:
        logger = self.context.logger
        logger.info("ATask.execute.main")
        logger.debug(self.context.provider)
        logger.debug(self.context.client)
        logger.debug(self.task.instance)
        return {}

    def post(self) -> None:
        logger = self.context.logger
        logger.info("ATask.execute.post")
