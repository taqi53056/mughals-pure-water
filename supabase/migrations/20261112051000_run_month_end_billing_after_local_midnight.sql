-- Run month-end billing after Pakistan local midnight.
-- The billing function selects the current month only when local date is the last day;
-- at 23:55 PKT that would close the month five minutes too early.
DO $migration$
DECLARE
  v_job_id bigint;
BEGIN
  SELECT jobid INTO v_job_id
  FROM cron.job
  WHERE jobname = 'mughal-month-end-billing'
    AND active = true;

  IF v_job_id IS NULL THEN
    RAISE EXCEPTION 'Active mughal-month-end-billing cron job was not found.';
  END IF;

  PERFORM cron.alter_job(v_job_id, schedule := '5 19 * * *');
END;
$migration$;
