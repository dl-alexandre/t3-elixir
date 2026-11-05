defmodule T3.Catalog do
  @moduledoc """
  Versioned inventory of T3 MCP helpers, including context-only operations.

  The inventory is the union of 66 tools advertised in the development session and
  five additional upstream definitions at `337c5858c33bc7f8f6dfd391a2c279fa0f7e4d17`.
  It is not a claim that an outside OAuth client can invoke all tools. Use
  `discover/1` to inspect the authenticated server and `compare/1` to find
  version differences. Every canonical function is available in `T3.Tools`.
  Input arguments retain T3's string keys; server discovery supplies input schemas.
  """
  @upstream_ref "337c5858c33bc7f8f6dfd391a2c279fa0f7e4d17"
  @tools [
    %{
      name: "create_threads",
      category: :threads,
      module: T3.Threads,
      function: :create_many,
      canonical_function: :create_threads,
      advertised_in_session: true,
      description:
        "Create new top-level threads in this checkout. Not delegation. One thread or its own worktree: `t3_thread_launch`. Project, branch, and worktree inherit.",
      context:
        "Availability is server-, permission-, and context-dependent; outside clients must supply explicit project/thread targets when required."
    },
    %{
      name: "delegate_task",
      category: :tasks,
      module: T3.Tasks,
      function: :delegate,
      canonical_function: :delegate_task,
      advertised_in_session: true,
      description:
        "Start one child agent with only `task`. No parent history. Separate checkout or PR per child: `isolation:'worktree'`. Keep `taskId` for `task_status` and `task_cancel`.",
      context:
        "Some operations require a T3-launched agent/thread context. The server enforces tool visibility and permissions."
    },
    %{
      name: "delete_scheduled_task",
      category: :schedules,
      module: T3.Schedules,
      function: :delete,
      canonical_function: :delete_scheduled_task,
      advertised_in_session: true,
      description:
        "Delete one scheduled task by `scheduledTaskId`. It stops at once. To pause instead, use `schedule_task` with `enabled=false`.",
      context:
        "Some operations require a T3-launched agent/thread context. The server enforces tool visibility and permissions."
    },
    %{
      name: "device_close",
      category: :devices,
      module: T3.Devices,
      function: :close,
      canonical_function: :device_close,
      advertised_in_session: true,
      description:
        "Remove a device from this thread's Device panel. `shutdown=true` also turns it off.",
      context:
        "Requires a compatible T3 agent/thread context and runtime; not generally exposed to outside OAuth clients."
    },
    %{
      name: "device_list",
      category: :devices,
      module: T3.Devices,
      function: :list,
      canonical_function: :device_list,
      advertised_in_session: true,
      description:
        "List iOS Simulators and Android Emulators on every device host, what each host can run, and what is open in this thread's Device panel. Call before `device_open` when you do not know a device id.",
      context:
        "Requires a compatible T3 agent/thread context and runtime; not generally exposed to outside OAuth clients."
    },
    %{
      name: "device_open",
      category: :devices,
      module: T3.Devices,
      function: :open,
      canonical_function: :device_open,
      advertised_in_session: true,
      description:
        "Open a simulator or emulator for this thread. Pass `deviceId` and `hostId` from `device_list`. Boots it if needed and shows it in the user's Device panel. Returns the `agent-device` CLI call pinned to that device. Drive the device with that CLI.",
      context:
        "Requires a compatible T3 agent/thread context and runtime; not generally exposed to outside OAuth clients."
    },
    %{
      name: "device_screenshot",
      category: :devices,
      module: T3.Devices,
      function: :screenshot,
      canonical_function: :device_screenshot,
      advertised_in_session: true,
      description:
        "Get a PNG of an open device's screen. For taps and text, use the `agent-device` CLI.",
      context:
        "Requires a compatible T3 agent/thread context and runtime; not generally exposed to outside OAuth clients."
    },
    %{
      name: "html_preview",
      category: :html,
      module: T3.HTML,
      function: :preview,
      canonical_function: :html_preview,
      advertised_in_session: true,
      description:
        "Check an HTML page before html_render. Returns PNG, contentHeight, and console output. If it says the browser is still installing, call again in a minute. Inline <style> and <script>. Local images as absolute paths are inlined. Remote URLs load as-is. Theme and layout rules are in html_render.",
      context:
        "Requires a compatible T3 agent/thread context and runtime; not generally exposed to outside OAuth clients."
    },
    %{
      name: "html_render",
      category: :html,
      module: T3.HTML,
      function: :render,
      canonical_function: :html_render,
      advertised_in_session: true,
      description:
        "Show a finished HTML page (chart, diagram, mockup) inline in this thread, above your final reply. Do not announce or restate the page. Frame fits height to 20000px. On mobile, content past the given height scrolls. Frame width is reply width (728px desktop, about 360px phones), on the thread background. Leave html, body, and the outer element with no background color, no outer card, border, banner title, or side padding. This wins over any rule that sets a page background. T3 adds an overridable 8px html gutter for selection rings and shadows. Use fluid widths within it. A box that needs its own background gets 16px padding and var(--radius) corners. Give charts fixed pixel heights. Let content set the height. Do not use vh units or height:100% on html or body. Both are rejected or loop. Use theme CSS variables on :root, not fixed colors: --background, --foreground, --muted, --card, --popover, --secondary, --border, --ring, --primary, --accent, --destructive, --warning, --success, --info, --code-background (most have a matching -foreground; accent, destructive, and warning also have -surface), --chart-1 to --chart-6, --radius, --font-sans, --font-mono. The base sheet sets background, text, and font.",
      context:
        "Requires a compatible T3 agent/thread context and runtime; not generally exposed to outside OAuth clients."
    },
    %{
      name: "link_pull_request",
      category: :pull_requests,
      module: T3.PullRequests,
      function: :link,
      canonical_function: :link_pull_request,
      advertised_in_session: true,
      description:
        "Link a PR to this thread. T3 shows its status and settles the thread on merge.",
      context:
        "Availability is server-, permission-, and context-dependent; outside clients must supply explicit project/thread targets when required."
    },
    %{
      name: "link_pull_requests",
      category: :pull_requests,
      module: T3.PullRequests,
      function: :link_many,
      canonical_function: :link_pull_requests,
      advertised_in_session: false,
      description:
        "Link several pull requests to a thread in one call. Invalid pull request URLs are returned separately.",
      context:
        "Availability is server-, permission-, and context-dependent; outside clients must supply explicit project/thread targets when required."
    },
    %{
      name: "list_scheduled_tasks",
      category: :schedules,
      module: T3.Schedules,
      function: :list,
      canonical_function: :list_scheduled_tasks,
      advertised_in_session: true,
      description:
        "List scheduled tasks. Omit `projectId` for this thread's project. Pass a `scheduledTaskId` to `schedule_task` or `delete_scheduled_task`. In a scheduled run, do not call this to find your task. Do the prompt.",
      context:
        "Some operations require a T3-launched agent/thread context. The server enforces tool visibility and permissions."
    },
    %{
      name: "list_thread_pull_requests",
      category: :pull_requests,
      module: T3.PullRequests,
      function: :list,
      canonical_function: :list_thread_pull_requests,
      advertised_in_session: true,
      description:
        "List PRs linked to a thread, with last known state and stack order (bottom to top). Call only when you need that list. Never as an end-of-work check.",
      context:
        "Availability is server-, permission-, and context-dependent; outside clients must supply explicit project/thread targets when required."
    },
    %{
      name: "orchestrator_capabilities",
      category: :tasks,
      module: T3.Tasks,
      function: :capabilities,
      canonical_function: :orchestrator_capabilities,
      advertised_in_session: true,
      description:
        "List providers, models, options, and runtime modes for `delegate_task`. Short list. `search` finds others. Any catalog model works.",
      context:
        "Some operations require a T3-launched agent/thread context. The server enforces tool visibility and permissions."
    },
    %{
      name: "preview_act",
      category: :previews,
      module: T3.Previews,
      function: :act,
      canonical_function: :preview_act,
      advertised_in_session: true,
      description:
        "Act on the chosen tab. Target with `locator='aria-ref=<ref>'` from `preview_snapshot`; `x` and `y` go together. `timeoutMs` defaults to 15000. click: `button`, `clickCount` 1 to 3. type: literal `text`, `clear=true` replaces it. hover: shows menus or tooltips. select: `values` in one native <select>, by value or label; for a custom dropdown, click it open, then click the option. drag: `source` onto `target`. upload: absolute `paths` answer the file picker `preview_status` reports, [] cancels it, or a `locator` sets an <input type=file>. press: one `key`, such as 'Enter', with `modifiers`, to the focused element; click a field first to focus it. scroll: the tab, or one container with a locator; positive `deltaY` scrolls down, positive `deltaX` right.",
      context:
        "Requires a compatible T3 agent/thread context and runtime; not generally exposed to outside OAuth clients."
    },
    %{
      name: "preview_dialog",
      category: :previews,
      module: T3.Previews,
      function: :dialog,
      canonical_function: :preview_dialog,
      advertised_in_session: true,
      description:
        "Accept or dismiss the dialog `preview_status` reports. Pass `promptText` to accept a prompt. Needs your own tab, or an unclaimed one. Desktop hosts may not support this.",
      context:
        "Requires a compatible T3 agent/thread context and runtime; not generally exposed to outside OAuth clients."
    },
    %{
      name: "preview_evaluate",
      category: :previews,
      module: T3.Previews,
      function: :evaluate,
      canonical_function: :preview_evaluate,
      advertised_in_session: true,
      description:
        "Run JavaScript in the page. It can change page state. Returns `{value}`, up to 64 KB. Needs your tab, or an unclaimed one. To read a tab the user drives, use `preview_snapshot`. Page tools reached here: read data only, never create, save, or display. Show results with `html_render`.",
      context:
        "Requires a compatible T3 agent/thread context and runtime; not generally exposed to outside OAuth clients."
    },
    %{
      name: "preview_navigate",
      category: :previews,
      module: T3.Previews,
      function: :navigate,
      canonical_function: :preview_navigate,
      advertised_in_session: true,
      description:
        "Navigate the chosen tab. Pass `url` for a website, or `target:{kind:'environment-port',port}` for a dev server. Exactly one of `url` and `target`.",
      context:
        "Requires a compatible T3 agent/thread context and runtime; not generally exposed to outside OAuth clients."
    },
    %{
      name: "preview_open",
      category: :previews,
      module: T3.Previews,
      function: :open,
      canonical_function: :preview_open,
      advertised_in_session: true,
      description:
        "Open a preview tab in this thread and show it. `open=false` keeps it in the background. Reuses your current tab unless `tabId` or `reuseExistingTab=false` says otherwise. Parallel subagents in one session must each use `reuseExistingTab=false`, then their own returned `tabId`.",
      context:
        "Requires a compatible T3 agent/thread context and runtime; not generally exposed to outside OAuth clients."
    },
    %{
      name: "preview_recording_start",
      category: :previews,
      module: T3.Previews,
      function: :start_recording,
      canonical_function: :preview_recording_start,
      advertised_in_session: true,
      description: "Start recording the chosen tab.",
      context:
        "Requires a compatible T3 agent/thread context and runtime; not generally exposed to outside OAuth clients."
    },
    %{
      name: "preview_recording_stop",
      category: :previews,
      module: T3.Previews,
      function: :stop_recording,
      canonical_function: :preview_recording_stop,
      advertised_in_session: true,
      description:
        "Stop recording the chosen tab. Returns a local path to the recording file (max 50 MiB).",
      context:
        "Requires a compatible T3 agent/thread context and runtime; not generally exposed to outside OAuth clients."
    },
    %{
      name: "preview_resize",
      category: :previews,
      module: T3.Previews,
      function: :resize,
      canonical_function: :preview_resize,
      advertised_in_session: true,
      description:
        "Resize the chosen tab: {mode:'fill'}, {mode:'freeform',width,height}, or {mode:'preset',preset,orientation}. Changes CSS size only, not the user agent.",
      context:
        "Requires a compatible T3 agent/thread context and runtime; not generally exposed to outside OAuth clients."
    },
    %{
      name: "preview_set_appearance",
      category: :previews,
      module: T3.Previews,
      function: :set_appearance,
      canonical_function: :preview_set_appearance,
      advertised_in_session: true,
      description:
        "Set `prefers-color-scheme` for the chosen tab: 'dark', 'light', or 'system' to clear the override.",
      context:
        "Requires a compatible T3 agent/thread context and runtime; not generally exposed to outside OAuth clients."
    },
    %{
      name: "preview_snapshot",
      category: :previews,
      module: T3.Previews,
      function: :snapshot,
      canonical_function: :preview_snapshot,
      advertised_in_session: true,
      description:
        "Use it only when the current request asks for browser work, including checking an edit in the browser. Never use it unasked to verify your own edit, or to repeat a snapshot from an earlier turn. Works on a tab the user is driving. Returns page state, elements, diagnostics, and screenshot size. Target one element with `locator='aria-ref=<ref>'` from `accessibilityTree`, even in frames. Refs die on navigation, a new snapshot, or handoff. Text caps near 20 KB; on your own or an unclaimed tab, `preview_evaluate` reads more. To show a screenshot when asked: `save=true`, then embed ![alt](screenshotPath).",
      context:
        "Requires a compatible T3 agent/thread context and runtime; not generally exposed to outside OAuth clients."
    },
    %{
      name: "preview_status",
      category: :previews,
      module: T3.Previews,
      function: :status,
      canonical_function: :preview_status,
      advertised_in_session: true,
      description:
        "Report preview tab state: owner, pending dialog, URL, title, loading, viewport, and size. `tabs` lists this thread's tabs. `profiles` lists logins for `preview_open`. Read any listed tab. Act only on your tab, or an unclaimed tab with no human in control.",
      context:
        "Requires a compatible T3 agent/thread context and runtime; not generally exposed to outside OAuth clients."
    },
    %{
      name: "preview_wait_for",
      category: :previews,
      module: T3.Previews,
      function: :wait_for,
      canonical_function: :preview_wait_for,
      advertised_in_session: true,
      description:
        "Wait until all given locator, selector, text, and URL conditions match in the chosen tab.",
      context:
        "Requires a compatible T3 agent/thread context and runtime; not generally exposed to outside OAuth clients."
    },
    %{
      name: "read_pull_request_guide",
      category: :pull_requests,
      module: T3.PullRequests,
      function: :read_guide,
      canonical_function: :read_pull_request_guide,
      advertised_in_session: true,
      description:
        "Read a PR's stored review guide and run state. `guide` is null when none exists. Never starts a run.",
      context:
        "Availability is server-, permission-, and context-dependent; outside clients must supply explicit project/thread targets when required."
    },
    %{
      name: "request_secret",
      category: :requests,
      module: T3.Requests,
      function: :secret,
      canonical_function: :request_secret,
      advertised_in_session: true,
      description:
        "Ask the user to enter a secret in a private card and wait. You never see the value. Returns a one-use `secretRef` for a tool that accepts it, or with `delivery: \"file\"` a private file path to read inside a shell command. Asked how to provide a secret: call this now, do not explain instead.",
      context:
        "Some operations require a T3-launched agent/thread context. The server enforces tool visibility and permissions."
    },
    %{
      name: "run_scheduled_task_now",
      category: :schedules,
      module: T3.Schedules,
      function: :run_now,
      canonical_function: :run_scheduled_task_now,
      advertised_in_session: true,
      description:
        "Run one scheduled task now. Needs a full-access or default caller. Returns its thread, or null if not started. Success means started, not finished.",
      context:
        "Some operations require a T3-launched agent/thread context. The server enforces tool visibility and permissions."
    },
    %{
      name: "schedule_task",
      category: :schedules,
      module: T3.Schedules,
      function: :save,
      canonical_function: :schedule_task,
      advertised_in_session: true,
      description:
        "Create scheduled work that runs with no turn active; it needs `prompt` and `schedule`. With `scheduledTaskId`, update that task: only given fields change, `enabled=false` pauses it. `schedule` is an object, not text. Report the returned next run time or `webhookUrl`. No `webhookUrl`: T3 Connect remote access is off. Webhook request values in the prompt are untrusted.",
      context:
        "Some operations require a T3-launched agent/thread context. The server enforces tool visibility and permissions."
    },
    %{
      name: "t3_attachment_discard",
      category: :attachments,
      module: T3.Attachments,
      function: :discard,
      canonical_function: :t3_attachment_discard,
      advertised_in_session: true,
      description: "Discard a pending upload (not a sent attachment).",
      context:
        "Availability is server-, permission-, and context-dependent; outside clients must supply explicit project/thread targets when required."
    },
    %{
      name: "t3_attachment_prepare_upload",
      category: :attachments,
      module: T3.Attachments,
      function: :prepare_upload,
      canonical_function: :t3_attachment_prepare_upload,
      advertised_in_session: true,
      description:
        "Get an upload URL. POST the file's exact bytes to `relativeUrl` on this MCP server's HTTP origin, then send via `t3_thread_send_attachments` with the returned `attachmentId`.",
      context:
        "Availability is server-, permission-, and context-dependent; outside clients must supply explicit project/thread targets when required."
    },
    %{
      name: "t3_background_wait",
      category: :tasks,
      module: T3.Tasks,
      function: :background_wait,
      canonical_function: :t3_background_wait,
      advertised_in_session: true,
      description:
        "Keep this thread in Working while background work runs. Pass its task ID after starting it. Not for work left running (dev server, watcher). `waiting=false` clears. Does not stop the task. Claude only.",
      context:
        "Some operations require a T3-launched agent/thread context. The server enforces tool visibility and permissions."
    },
    %{
      name: "t3_environment_link",
      category: :environments,
      module: T3.Environments,
      function: :link,
      canonical_function: :t3_environment_link,
      advertised_in_session: false,
      description:
        "Ask the user to link another environment. Linking requires an agent invocation context; returns pending while the user approves.",
      context:
        "Requires linked-environment support, which may be disabled or hidden by the server."
    },
    %{
      name: "t3_environment_links",
      category: :environments,
      module: T3.Environments,
      function: :links,
      canonical_function: :t3_environment_links,
      advertised_in_session: false,
      description:
        "List linked environments and whether each answers now. Pass environmentId to supported tools to act there.",
      context:
        "Requires linked-environment support, which may be disabled or hidden by the server."
    },
    %{
      name: "t3_environment_preferences_update",
      category: :environments,
      module: T3.Environments,
      function: :update_preferences,
      canonical_function: :t3_environment_preferences_update,
      advertised_in_session: true,
      description:
        "Update environment-wide preferences. Live full-access or default caller thread only. Omitted fields are unchanged; `customInstructions: ''` clears it.",
      context: "Requires a live full-access/default caller thread."
    },
    %{
      name: "t3_environment_read",
      category: :environments,
      module: T3.Environments,
      function: :read,
      canonical_function: :t3_environment_read,
      advertised_in_session: true,
      description:
        "Read this server's identity and preferences. Providers and models: `orchestrator_capabilities`.",
      context:
        "Availability is server-, permission-, and context-dependent; outside clients must supply explicit project/thread targets when required."
    },
    %{
      name: "t3_environment_unlink",
      category: :environments,
      module: T3.Environments,
      function: :unlink,
      canonical_function: :t3_environment_unlink,
      advertised_in_session: false,
      description: "Forget a linked environment. The remote session remains until revoked there.",
      context:
        "Requires linked-environment support, which may be disabled or hidden by the server."
    },
    %{
      name: "t3_pending_request",
      category: :requests,
      module: T3.Requests,
      function: :manage,
      canonical_function: :t3_pending_request,
      advertised_in_session: true,
      description:
        "Pending user questions in a thread. Omit `threadId` for this thread. list: their ids; approvals are not listed. read: one by `requestId`. respond: answer one with `answers`; this cannot approve a permission request.",
      context:
        "Some operations require a T3-launched agent/thread context. The server enforces tool visibility and permissions."
    },
    %{
      name: "t3_preview_close",
      category: :previews,
      module: T3.Previews,
      function: :close,
      canonical_function: :t3_preview_close,
      advertised_in_session: true,
      description:
        "Close one preview tab this thread owns. Use it on a tab you opened for your own check when you finish.",
      context:
        "Requires a compatible T3 agent/thread context and runtime; not generally exposed to outside OAuth clients."
    },
    %{
      name: "t3_preview_list",
      category: :previews,
      module: T3.Previews,
      function: :list,
      canonical_function: :t3_preview_list,
      advertised_in_session: true,
      description:
        "List this thread's preview tabs. Only `runtime:'server'` entries can be automated here. Others are in the user's local desktop app. Never pass a non-server `tabId` to a `preview_*` tool. Tell the user that tab is on their local desktop and this environment cannot reach it.",
      context:
        "Requires a compatible T3 agent/thread context and runtime; not generally exposed to outside OAuth clients."
    },
    %{
      name: "t3_project_clone",
      category: :projects,
      module: T3.Projects,
      function: :clone,
      canonical_function: :t3_project_clone,
      advertised_in_session: true,
      description:
        "Clone a repository (`destinationPath` new or empty). Register after with `t3_project_create`, with the same `environmentId`.",
      context:
        "Availability is server-, permission-, and context-dependent; outside clients must supply explicit project/thread targets when required."
    },
    %{
      name: "t3_project_create",
      category: :projects,
      module: T3.Projects,
      function: :create,
      canonical_function: :t3_project_create,
      advertised_in_session: true,
      description:
        "Register a project folder. `createWorkspaceRootIfMissing` creates it; a registered folder is rejected. No `workspaceRoot`: makes a git repo from `title` with README, icon, first commit (`commitError` on failure; project still exists). Clone first with `t3_project_clone` if needed.",
      context:
        "Availability is server-, permission-, and context-dependent; outside clients must supply explicit project/thread targets when required."
    },
    %{
      name: "t3_project_delete",
      category: :projects,
      module: T3.Projects,
      function: :delete,
      canonical_function: :t3_project_delete,
      advertised_in_session: true,
      description: "Delete one project. Nonempty needs `force: true`. Folder on disk stays.",
      context:
        "Availability is server-, permission-, and context-dependent; outside clients must supply explicit project/thread targets when required."
    },
    %{
      name: "t3_project_list",
      category: :projects,
      module: T3.Projects,
      function: :list,
      canonical_function: :t3_project_list,
      advertised_in_session: true,
      description: "List projects. Pages can shift.",
      context:
        "Availability is server-, permission-, and context-dependent; outside clients must supply explicit project/thread targets when required."
    },
    %{
      name: "t3_project_read",
      category: :projects,
      module: T3.Projects,
      function: :read,
      canonical_function: :t3_project_read,
      advertised_in_session: true,
      description: "Read one project: workspace and saved scripts.",
      context:
        "Availability is server-, permission-, and context-dependent; outside clients must supply explicit project/thread targets when required."
    },
    %{
      name: "t3_project_update",
      category: :projects,
      module: T3.Projects,
      function: :update,
      canonical_function: :t3_project_update,
      advertised_in_session: true,
      description: "Update one project's settings. Omitted fields are unchanged.",
      context:
        "Availability is server-, permission-, and context-dependent; outside clients must supply explicit project/thread targets when required."
    },
    %{
      name: "t3_queue",
      category: :queues,
      module: T3.Queues,
      function: :manage,
      canonical_function: :t3_queue,
      advertised_in_session: true,
      description:
        "Manage a thread's queued messages. Omit `threadId` for this thread. list: send order, paged by `cursor` and `limit`. read: up to 16,000 chars of one. edit: replace its `text`; attachments stay. cancel. reorder: before `beforeRunId`, or to the end with null. promote_to_steer: send it now as steering to active `targetRunId`. Writes fail once the run is no longer queued.",
      context:
        "Availability is server-, permission-, and context-dependent; outside clients must supply explicit project/thread targets when required."
    },
    %{
      name: "t3_thread_configure",
      category: :threads,
      module: T3.Threads,
      function: :configure,
      canonical_function: :t3_thread_configure,
      advertised_in_session: true,
      description:
        "Read a thread's provider, model, and modes, or set its provider, model, and options with `modelSelection`. Omit `threadId` for this thread. Permission modes stay. Values from `orchestrator_capabilities`.",
      context:
        "Availability is server-, permission-, and context-dependent; outside clients must supply explicit project/thread targets when required."
    },
    %{
      name: "t3_thread_interrupt",
      category: :threads,
      module: T3.Threads,
      function: :interrupt,
      canonical_function: :t3_thread_interrupt,
      advertised_in_session: true,
      description:
        "Interrupt a top-level thread's running turn. No `runId`: newest running turn. No effect when idle. For a delegate, use `task_cancel`.",
      context:
        "Availability is server-, permission-, and context-dependent; outside clients must supply explicit project/thread targets when required."
    },
    %{
      name: "t3_thread_launch",
      category: :threads,
      module: T3.Threads,
      function: :launch,
      canonical_function: :t3_thread_launch,
      advertised_in_session: true,
      description:
        "Create one new top-level thread, bound to its workspace before the agent starts. Task in `message`. Omit `projectId`, model and modes to inherit yours (outside a thread, pass `projectId` or `scratch`); modes cannot exceed yours. After an error or lost reply, retry with the same `clientRequestId`. Follow it with `t3_thread_read` or `t3_thread_wait`. Mention it with its `link`.",
      context:
        "Availability is server-, permission-, and context-dependent; outside clients must supply explicit project/thread targets when required."
    },
    %{
      name: "t3_thread_list",
      category: :threads,
      module: T3.Threads,
      function: :list,
      canonical_function: :t3_thread_list,
      advertised_in_session: true,
      description:
        "List threads newest first, in one project or with `allProjects`. Page with `cursor`.",
      context:
        "Availability is server-, permission-, and context-dependent; outside clients must supply explicit project/thread targets when required."
    },
    %{
      name: "t3_thread_organize",
      category: :threads,
      module: T3.Threads,
      function: :organize,
      canonical_function: :t3_thread_organize,
      advertised_in_session: true,
      description:
        "Pin, snooze, settle, archive, or mark a thread unread. Omit `threadId` for this thread. `snooze` needs `snoozedUntil`. Settling this thread applies at turn end. A failed turn or queued message leaves it active.",
      context:
        "Availability is server-, permission-, and context-dependent; outside clients must supply explicit project/thread targets when required."
    },
    %{
      name: "t3_thread_read",
      category: :threads,
      module: T3.Threads,
      function: :read,
      canonical_function: :t3_thread_read,
      advertised_in_session: true,
      description:
        "Read any thread by id. `messages` (default): user and assistant messages and plans. `activity`: all timeline items. Keep reads small: low `limit` and `maxCharsPerItem`. Page with `afterPosition=nextPosition`. Cut-off text: `itemId` with `textOffset=nextTextOffset`. Reading a child's final result marks it delivered. In your reply, name it as its `link` verbatim.",
      context:
        "Availability is server-, permission-, and context-dependent; outside clients must supply explicit project/thread targets when required."
    },
    %{
      name: "t3_thread_search",
      category: :threads,
      module: T3.Threads,
      function: :search,
      canonical_function: :t3_thread_search,
      advertised_in_session: true,
      description:
        "Search active threads by title, branch, PR, project, then message text. Skips subagent threads. `projectId`: one project, else yours, else all outside a thread. Not exhaustive.",
      context:
        "Availability is server-, permission-, and context-dependent; outside clients must supply explicit project/thread targets when required."
    },
    %{
      name: "t3_thread_send",
      category: :threads,
      module: T3.Threads,
      function: :send,
      canonical_function: :t3_thread_send,
      advertised_in_session: true,
      description:
        "Send a message to any thread. The target cannot run with broader modes than yours. `mode:'auto'` starts an idle thread, steers a running turn, or queues. `queue`: new turn. `steer`: mid-turn update. `restart`: interrupt and restart. A send to a finished child thread starts a fresh task and returns its `taskId`. In your reply, name it as its `link` verbatim.",
      context:
        "Availability is server-, permission-, and context-dependent; outside clients must supply explicit project/thread targets when required."
    },
    %{
      name: "t3_thread_send_attachments",
      category: :attachments,
      module: T3.Attachments,
      function: :send,
      canonical_function: :t3_thread_send_attachments,
      advertised_in_session: true,
      description:
        "Send uploaded attachments as a new message to a thread. No retry key. Target modes cannot exceed yours. Success does not mean the provider read them or finished.",
      context:
        "Availability is server-, permission-, and context-dependent; outside clients must supply explicit project/thread targets when required."
    },
    %{
      name: "t3_thread_transfer",
      category: :threads,
      module: T3.Threads,
      function: :transfer,
      canonical_function: :t3_thread_transfer,
      advertised_in_session: true,
      description:
        "Move context between threads. Omit `threadId` for this thread. fork: copy it from `sourcePoint` (default latest stable run) into a new thread with the same setup; no turn runs yet. merge_back: merge it from `sourcePoint` into a related `targetThreadId` in the same project. status: its context transfers.",
      context:
        "Availability is server-, permission-, and context-dependent; outside clients must supply explicit project/thread targets when required."
    },
    %{
      name: "t3_thread_update",
      category: :threads,
      module: T3.Threads,
      function: :update,
      canonical_function: :t3_thread_update,
      advertised_in_session: true,
      description:
        "Rename a thread (`action:'rename'` with `title`) or regenerate its title. Omit `threadId` for this thread. Workspace and branch cannot change here.",
      context:
        "Availability is server-, permission-, and context-dependent; outside clients must supply explicit project/thread targets when required."
    },
    %{
      name: "t3_thread_wait",
      category: :threads,
      module: T3.Threads,
      function: :wait,
      canonical_function: :t3_thread_wait,
      advertised_in_session: true,
      description:
        "Wait for a thread's run to finish. No `runId`: latest. Idle: at once. On timeout, with `next` end your turn; without, call again.",
      context:
        "Availability is server-, permission-, and context-dependent; outside clients must supply explicit project/thread targets when required."
    },
    %{
      name: "t3_workflow_stop",
      category: :tasks,
      module: T3.Tasks,
      function: :stop_workflow,
      canonical_function: :t3_workflow_stop,
      advertised_in_session: true,
      description:
        "Stop a running Claude workflow in a thread. `subagentId`: coordinator from `t3_thread_read` 'activity'. Stops only the workflow, not the thread.",
      context:
        "Some operations require a T3-launched agent/thread context. The server enforces tool visibility and permissions."
    },
    %{
      name: "t3_worktree_handoff",
      category: :worktrees,
      module: T3.Worktrees,
      function: :handoff,
      canonical_function: :t3_worktree_handoff,
      advertised_in_session: true,
      description:
        "Move THIS thread into a new git worktree on a new branch. Runs the setup script by default. A separate agent in a worktree: `t3_thread_launch` with `workspaceStrategy`. Call last in your turn. The move ends the live session. `continuationPrompt` resumes work there next turn. Without it, the thread waits. The worktree stays after the thread is deleted. Fails if this thread has a worktree.",
      context:
        "Some operations require a T3-launched agent/thread context. The server enforces tool visibility and permissions."
    },
    %{
      name: "t3_worktree_list",
      category: :worktrees,
      module: T3.Worktrees,
      function: :list,
      canonical_function: :t3_worktree_list,
      advertised_in_session: true,
      description:
        "List branch refs and checkout paths for a thread's workspace. Omit `threadId` for this thread. Detached worktrees with no branch are left out.",
      context:
        "Some operations require a T3-launched agent/thread context. The server enforces tool visibility and permissions."
    },
    %{
      name: "t3_worktree_status",
      category: :worktrees,
      module: T3.Worktrees,
      function: :status,
      canonical_function: :t3_worktree_status,
      advertised_in_session: true,
      description:
        "Report this thread's worktree: attached or not, path, branch, project root, and the `startFromOrigin` default. Check before `t3_worktree_handoff`.",
      context:
        "Some operations require a T3-launched agent/thread context. The server enforces tool visibility and permissions."
    },
    %{
      name: "task_cancel",
      category: :tasks,
      module: T3.Tasks,
      function: :cancel,
      canonical_function: :task_cancel,
      advertised_in_session: true,
      description:
        "Stop one delegated task by `taskId`. Stops its running and queued turns, its delegates, and its PR watches, including later runs in its child thread. A finished task keeps its result.",
      context:
        "Some operations require a T3-launched agent/thread context. The server enforces tool visibility and permissions."
    },
    %{
      name: "task_status",
      category: :tasks,
      module: T3.Tasks,
      function: :status,
      canonical_function: :task_status,
      advertised_in_session: true,
      description:
        "Read one delegated task you started. Do not call it on a running task before its completion wakes you. `workState`: working, waiting_for_children, result_available. A finished turn with live child work is not done. `summary`: final result. Reading it marks it delivered.",
      context:
        "Some operations require a T3-launched agent/thread context. The server enforces tool visibility and permissions."
    },
    %{
      name: "unlink_pull_request",
      category: :pull_requests,
      module: T3.PullRequests,
      function: :unlink,
      canonical_function: :unlink_pull_request,
      advertised_in_session: true,
      description:
        "Remove a PR link from this thread. Succeeds with `wasLinked=false` when it was not linked.",
      context:
        "Availability is server-, permission-, and context-dependent; outside clients must supply explicit project/thread targets when required."
    },
    %{
      name: "unlink_pull_requests",
      category: :pull_requests,
      module: T3.PullRequests,
      function: :unlink_many,
      canonical_function: :unlink_pull_requests,
      advertised_in_session: false,
      description:
        "Unlink every pull request on a thread whose last known state is in the supplied states.",
      context:
        "Availability is server-, permission-, and context-dependent; outside clients must supply explicit project/thread targets when required."
    },
    %{
      name: "unwatch_pull_request",
      category: :pull_requests,
      module: T3.PullRequests,
      function: :unwatch,
      canonical_function: :unwatch_pull_request,
      advertised_in_session: true,
      description: "Stop watching a PR for this thread. It stays linked.",
      context:
        "Availability is server-, permission-, and context-dependent; outside clients must supply explicit project/thread targets when required."
    },
    %{
      name: "watch_pull_request",
      category: :pull_requests,
      module: T3.PullRequests,
      function: :watch,
      canonical_function: :watch_pull_request,
      advertised_in_session: true,
      description:
        "Watch an open PR for this thread, linking it first if needed. T3 wakes you on failed checks, passed required checks, new comments or reviews, or conflicts. Handle old comments first. Only later ones wake you. After this call, end your turn. The watch stays on after each wake, so do not call this again on a wake. A wake is not a merge decision. Check readiness yourself.",
      context:
        "Availability is server-, permission-, and context-dependent; outside clients must supply explicit project/thread targets when required."
    },
    %{
      name: "write_pull_request_guides",
      category: :pull_requests,
      module: T3.PullRequests,
      function: :write_guides,
      canonical_function: :write_pull_request_guides,
      advertised_in_session: true,
      description:
        "Write review guides for up to 20 PRs (the tour in the PR Guide tab). Returns once runs start. Each run takes minutes in a temporary checkout. A run for the same head is joined. Read with `read_pull_request_guide`. Fails while guides are off.",
      context:
        "Availability is server-, permission-, and context-dependent; outside clients must supply explicit project/thread targets when required."
    }
  ]
  def upstream_ref, do: @upstream_ref
  @doc "Return all known tool descriptors, or one category's descriptors."
  def tools, do: @tools
  def tools(category), do: Enum.filter(@tools, &(&1.category == category))
  def names, do: Enum.map(@tools, & &1.name)

  def fetch(name) do
    case Enum.find(@tools, &(&1.name == name)) do
      nil -> :error
      tool -> {:ok, tool}
    end
  end

  @doc "Discover all advertised tools, following pagination with cycle and page bounds."
  def discover(client), do: discover(client, %{}, [], MapSet.new(), 0)

  defp discover(_client, _args, _acc, _seen, pages) when pages >= 100,
    do: {:error, %T3.Error{kind: :protocol, message: "tool discovery exceeded 100 pages"}}

  defp discover(client, args, acc, seen, pages) do
    with {:ok, %{"tools" => tools} = result} when is_list(tools) <-
           T3.Client.list_tools(client, args) do
      case result["nextCursor"] do
        nil ->
          {:ok, acc ++ tools}

        cursor ->
          if MapSet.member?(seen, cursor) do
            {:error, %T3.Error{kind: :protocol, message: "tool discovery repeated a cursor"}}
          else
            discover(
              client,
              %{"cursor" => cursor},
              acc ++ tools,
              MapSet.put(seen, cursor),
              pages + 1
            )
          end
      end
    else
      {:error, _} = error -> error
      _ -> {:error, %T3.Error{kind: :protocol, message: "invalid tool discovery response"}}
    end
  end

  @doc "Compare this SDK inventory with the authenticated server's actual tool list."
  def compare(client) do
    with {:ok, definitions} <- discover(client) do
      advertised = Enum.map(definitions, & &1["name"])
      known = names()

      {:ok,
       %{
         available: Enum.filter(@tools, &(&1.name in advertised)),
         unavailable: Enum.reject(@tools, &(&1.name in advertised)),
         unwrapped: Enum.reject(definitions, &(&1["name"] in known)),
         definitions: definitions
       }}
    end
  end
end
