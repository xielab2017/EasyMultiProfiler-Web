# Background analyses and reviewed Agent actions

Analysis and preparation requests listed by `GET /api/tasks/capabilities` are submitted through `POST /api/tasks/submit`. The client sends a registered route and its existing JSON payload. The server checks session ownership and runs the original trusted handler in a callr worker. User input cannot select a function, script or file path. Existing endpoints that already return a background job keep that contract. Uploads, model calls and unregistered routes are not converted by this bridge.

Workers acquire a session lock before loading large analysis libraries. Tasks writing to the same session wait for earlier tasks; separate sessions can run independently. State files retain PID, timestamps, progress and errors. The tray uses the normal authenticated API, refreshes immediately after submission, distinguishes queued/running/failed/cancelled tasks, and offers cancellation while the API owns the process handle. Completed results can be downloaded as JSON after a page reload. An API restart can lose the cancellation handle; the tray then hides cancellation. A dead worker is reported as an error rather than remaining marked running indefinitely. Existing synchronous requests cannot be migrated into a worker while running.

The analysis chat can search public sources and draft a count workflow through tools. It can additionally request a typed `submit_current` or `refresh_tasks` action. A submission is accepted only when the current page is in the local action registry, an experiment is selected, the user has reviewed current settings and enabled Agent mode for that turn, and the page context has not changed. The model cannot supply selectors, new sample groups, parameters or R code for these actions. Current Agent submission supports the six preparation tabs and alpha/differential/dimension/correlation/cluster/marker analysis tabs. Unsupported pages remain manual or use the count-workbench proposal/review flow.

The local grant expires after each reply or page-setting change. A model tool response is a request to the UI, not proof of execution. The chat records the job ID only after the R API accepts a job. “Refresh tasks” reads local task state; recent sanitized status summaries can inform subsequent turns. Scientific review remains necessary; the agent does not infer grouping, pairing or count provenance.

Reproduction:

```sh
Rscript webapp/tests/test_background_tasks.R
node --test webapp/tests/test_background_requests.mjs webapp/tests/test_agent_actions.mjs webapp/tests/test_agent_chat.mjs
python -m unittest discover -s webapp/tests -p 'test_agent*.py'
```

The R test uses synthetic data and an isolated temporary data root to verify a real worker, results, session queueing, cancellation and owner filtering. Agent tests mock model responses; live provider behavior is a separate check requiring a configured model. Do not interpret these tests as validation of every scientific analysis method.
