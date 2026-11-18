root <- normalizePath('.')
target <- tempfile('emp-job-queue-')
dir.create(target)
Sys.setenv(EMP_DATA_DIR = target, EMP_BACKEND_DIR = file.path(root,'webapp/backend'),
           API_HOST = '127.0.0.1', EMP_ANALYSIS_WORKERS = '1')
Sys.unsetenv(c('EMP_SESSION_DIR', 'EMP_JOB_DIR', 'EMP_PROJECT_DIR', 'EMP_API_TOKEN', 'EMP_API_TOKEN_SHA256S'))
for (file in c('utils.R', 'storage.R', 'auth.R', 'jobs.R')) {
  source(file.path('webapp/backend/helpers', file))
}
task <- function(label, on_progress) {
  Sys.sleep(0.4)
  list(label = label)
}
first <- submit_job('count_workbench', task, list(label = 'one'))
second <- submit_job('count_workbench', task, list(label = 'two'))
third <- submit_job('count_workbench', task, list(label = 'cancelled'))
stopifnot(identical(ls(.JOB_PROCESSES), first),
          identical(names(.JOB_QUEUE$entries), c(second, third)),
          get_job_status(second)$status == 'queued',
          .job_summary(get_job_status(third))$cancellable)
stopifnot(cancel_job(third)$status == 'cancelled', get_job_status(third)$status == 'cancelled')
for (attempt in seq_len(300)) {
  later::run_now(0.05)
  if (.read_state(second)$status %in% .job_terminal) break
}
stopifnot(get_job_status(second)$status == 'done',
          get_job_status(first)$status == 'done',
          get_job_result(first)$label == 'one', get_job_result(second)$label == 'two',
          get_job_status(third)$message == 'Cancelled before starting',
          is.null(get_job_result(third)))
# Saturation returns one classified error and never launches the excess task.
holding <- submit_job('count_workbench', function(on_progress) Sys.sleep(30))
backlog <- vapply(1:16, function(i) submit_job('count_workbench', task, list(label = i)), character(1))
stopifnot(length(.JOB_QUEUE$entries) == 16L, length(ls(.JOB_PROCESSES)) == 1L)
response <- new.env()
refused <- safe_api(submit_job('count_workbench', task, list(label = 'excess')), response)
stopifnot(!refused$success, response$status == 429L, length(.JOB_QUEUE$entries) == 16L)
for (id in backlog) stopifnot(cancel_job(id)$status == 'cancelled')
stopifnot(cancel_job(holding)$status == 'cancelled')
# Reap a worker which dies before it can publish its PID, even via cancel.
failed_id <- .job_id()
.write_state(failed_id, list(id = failed_id, status = "queued", dispatcher_pid = Sys.getpid()))
assign(failed_id, list(is_alive = function() FALSE), envir = .JOB_PROCESSES)
stopifnot(cancel_job(failed_id)$status == 'already_finished', get_job_status(failed_id)$status == 'error')
# A second process must not invalidate a live dispatcher's waiting jobs.
neighbor <- callr::r_bg(function() Sys.sleep(30))
neighbor_id <- .job_id()
.write_state(neighbor_id, list(id = neighbor_id, status = "queued", dispatcher_pid = neighbor$get_pid()))
stopifnot(get_job_status(neighbor_id)$status == 'queued')
neighbor$kill()
# Across a service restart an in-memory queued payload is unavailable.
orphan_id <- .job_id()
.write_state(orphan_id, list(id = orphan_id, status = "queued", dispatcher_pid = -1L))
stopifnot(get_job_status(orphan_id)$status == 'error', grepl('restarted', get_job_status(orphan_id)$error))
cat("Bounded queue, cancellation, automatic dispatch, results and restart state passed.\n")
unlink(target, recursive = TRUE)
