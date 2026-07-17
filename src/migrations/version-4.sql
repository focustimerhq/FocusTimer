-- Add a task name to time-blocks and stats entries.
-- Tasks are identified by their name. An empty string means no task.

ALTER TABLE "timeblocks" ADD COLUMN "task" TEXT NOT NULL DEFAULT '';
ALTER TABLE "stats" ADD COLUMN "task" TEXT NOT NULL DEFAULT '';

CREATE INDEX "stats-date-task" ON "stats" ("date", "task") WHERE "task" != '';
