# Interface inventory
Contract revision: `337c5858c33bc7f8f6dfd391a2c279fa0f7e4d17` ([upstream source](https://github.com/pingdotgg/t3code/tree/337c5858c33bc7f8f6dfd391a2c279fa0f7e4d17)). Captured 2026-11-05.
This SDK covers the pinned wire operations through named helpers and generic
transports. It does not guarantee server-version support, credential permissions
or a T3 agent context. Payloads retain the original JSON/string-keyed format;
TypeScript schemas are enforced by T3, not duplicated as Elixir structs.

Use `mix t3.interfaces --json` for the programmatic inventory. Generic calls also
permit new operation names absent from the static catalogs.

## MCP

71 known tools: 66 advertised to the development agent and five additional
upstream definitions. Use `T3.discover(client)` to inspect a connected external
client's actual surface. MCP protocol 2025-06-18; ConduitMCP manages transport and
OAuth. A category helper and `T3.Tools.<wire_name>/2` exist for every entry.

Permission and context checks remain on the server. Browser/device/UI rendering,
worktree handoff and delegated-agent operations generally require agent context;
adding a wrapper does not make an external OAuth client an agent session.

| Wire tool | Category helper | Inventory source |
|---|---|---|
| `create_threads` | `T3.Threads.create_many` | Session + upstream |
| `delegate_task` | `T3.Tasks.delegate` | Session + upstream |
| `delete_scheduled_task` | `T3.Schedules.delete` | Session + upstream |
| `device_close` | `T3.Devices.close` | Session + upstream |
| `device_list` | `T3.Devices.list` | Session + upstream |
| `device_open` | `T3.Devices.open` | Session + upstream |
| `device_screenshot` | `T3.Devices.screenshot` | Session + upstream |
| `html_preview` | `T3.HTML.preview` | Session + upstream |
| `html_render` | `T3.HTML.render` | Session + upstream |
| `link_pull_request` | `T3.PullRequests.link` | Session + upstream |
| `link_pull_requests` | `T3.PullRequests.link_many` | Upstream only |
| `list_scheduled_tasks` | `T3.Schedules.list` | Session + upstream |
| `list_thread_pull_requests` | `T3.PullRequests.list` | Session + upstream |
| `orchestrator_capabilities` | `T3.Tasks.capabilities` | Session + upstream |
| `preview_act` | `T3.Previews.act` | Session + upstream |
| `preview_dialog` | `T3.Previews.dialog` | Session + upstream |
| `preview_evaluate` | `T3.Previews.evaluate` | Session + upstream |
| `preview_navigate` | `T3.Previews.navigate` | Session + upstream |
| `preview_open` | `T3.Previews.open` | Session + upstream |
| `preview_recording_start` | `T3.Previews.start_recording` | Session + upstream |
| `preview_recording_stop` | `T3.Previews.stop_recording` | Session + upstream |
| `preview_resize` | `T3.Previews.resize` | Session + upstream |
| `preview_set_appearance` | `T3.Previews.set_appearance` | Session + upstream |
| `preview_snapshot` | `T3.Previews.snapshot` | Session + upstream |
| `preview_status` | `T3.Previews.status` | Session + upstream |
| `preview_wait_for` | `T3.Previews.wait_for` | Session + upstream |
| `read_pull_request_guide` | `T3.PullRequests.read_guide` | Session + upstream |
| `request_secret` | `T3.Requests.secret` | Session + upstream |
| `run_scheduled_task_now` | `T3.Schedules.run_now` | Session + upstream |
| `schedule_task` | `T3.Schedules.save` | Session + upstream |
| `t3_attachment_discard` | `T3.Attachments.discard` | Session + upstream |
| `t3_attachment_prepare_upload` | `T3.Attachments.prepare_upload` | Session + upstream |
| `t3_background_wait` | `T3.Tasks.background_wait` | Session + upstream |
| `t3_environment_link` | `T3.Environments.link` | Upstream only |
| `t3_environment_links` | `T3.Environments.links` | Upstream only |
| `t3_environment_preferences_update` | `T3.Environments.update_preferences` | Session + upstream |
| `t3_environment_read` | `T3.Environments.read` | Session + upstream |
| `t3_environment_unlink` | `T3.Environments.unlink` | Upstream only |
| `t3_pending_request` | `T3.Requests.manage` | Session + upstream |
| `t3_preview_close` | `T3.Previews.close` | Session + upstream |
| `t3_preview_list` | `T3.Previews.list` | Session + upstream |
| `t3_project_clone` | `T3.Projects.clone` | Session + upstream |
| `t3_project_create` | `T3.Projects.create` | Session + upstream |
| `t3_project_delete` | `T3.Projects.delete` | Session + upstream |
| `t3_project_list` | `T3.Projects.list` | Session + upstream |
| `t3_project_read` | `T3.Projects.read` | Session + upstream |
| `t3_project_update` | `T3.Projects.update` | Session + upstream |
| `t3_queue` | `T3.Queues.manage` | Session + upstream |
| `t3_thread_configure` | `T3.Threads.configure` | Session + upstream |
| `t3_thread_interrupt` | `T3.Threads.interrupt` | Session + upstream |
| `t3_thread_launch` | `T3.Threads.launch` | Session + upstream |
| `t3_thread_list` | `T3.Threads.list` | Session + upstream |
| `t3_thread_organize` | `T3.Threads.organize` | Session + upstream |
| `t3_thread_read` | `T3.Threads.read` | Session + upstream |
| `t3_thread_search` | `T3.Threads.search` | Session + upstream |
| `t3_thread_send` | `T3.Threads.send` | Session + upstream |
| `t3_thread_send_attachments` | `T3.Attachments.send` | Session + upstream |
| `t3_thread_transfer` | `T3.Threads.transfer` | Session + upstream |
| `t3_thread_update` | `T3.Threads.update` | Session + upstream |
| `t3_thread_wait` | `T3.Threads.wait` | Session + upstream |
| `t3_workflow_stop` | `T3.Tasks.stop_workflow` | Session + upstream |
| `t3_worktree_handoff` | `T3.Worktrees.handoff` | Session + upstream |
| `t3_worktree_list` | `T3.Worktrees.list` | Session + upstream |
| `t3_worktree_status` | `T3.Worktrees.status` | Session + upstream |
| `task_cancel` | `T3.Tasks.cancel` | Session + upstream |
| `task_status` | `T3.Tasks.status` | Session + upstream |
| `unlink_pull_request` | `T3.PullRequests.unlink` | Session + upstream |
| `unlink_pull_requests` | `T3.PullRequests.unlink_many` | Upstream only |
| `unwatch_pull_request` | `T3.PullRequests.unwatch` | Session + upstream |
| `watch_pull_request` | `T3.PullRequests.watch` | Session + upstream |
| `write_pull_request_guides` | `T3.PullRequests.write_guides` | Session + upstream |

## HTTP JSON

All 38 routes in `EnvironmentHttpApi` are represented. Group modules live under
`T3.HTTP`; `T3.HTTP.call/3` routes an endpoint identifier and `request/4` handles
new same-origin paths. HTTP credentials are separate from MCP credentials. JSON,
form and raw body encodings are preserved. The app starts a Finch pool; caller
options can select another. Responses expose status, headers and decoded/raw body.

The body limit is 16 MiB by default, with bounded pool/request/receive timeouts.
Redirects and automatic retries are disabled. Cookie storage and renewal are not
automatic; caller-supplied cookie headers or tokens must have appropriate scopes.
DPoP proofs may be supplied; proof generation and signing remain caller-owned.

| Method | Path |
|---|---|
| GET | `/.well-known/t3/environment` |
| GET | `/api/auth/session` |
| POST | `/api/auth/browser-session` |
| POST | `/oauth/token` |
| POST | `/api/auth/websocket-ticket` |
| POST | `/api/auth/websocket-ticket/:use` |
| POST | `/api/auth/pairing-token` |
| POST | `/api/auth/pairing-links/revoke` |
| POST | `/api/auth/clients/revoke` |
| POST | `/api/auth/clients/revoke-others` |
| GET | `/.well-known/oauth-protected-resource` |
| GET | `/.well-known/oauth-protected-resource/mcp` |
| GET | `/.well-known/oauth-authorization-server` |
| POST | `/oauth/mcp/register` |
| GET | `/oauth/mcp/authorize` |
| POST | `/oauth/mcp/approval` |
| POST | `/oauth/mcp/decision` |
| POST | `/oauth/mcp/token` |
| GET | `/api/orchestration/shell` |
| GET | `/api/orchestration/threads/:threadId` |
| GET | `/api/orchestration/threads/:threadId/transcript` |
| GET | `/api/orchestration/threads/:threadId/bounded` |
| GET | `/api/orchestration/threads/:threadId/history` |
| GET | `/api/projects` |
| POST | `/api/projects/mutate` |
| POST | `/api/pull-requests/diff` |
| POST | `/api/connect/link-proof` |
| POST | `/api/connect/relay-config` |
| GET | `/api/connect/link-state` |
| POST | `/api/connect/reachability` |
| POST | `/api/connect/unlink` |
| POST | `/api/connect/preferences` |
| POST | `/api/t3-connect/health` |
| POST | `/api/t3-connect/mint-credential` |
| POST | `/api/hooks/:hookId/:token` |
| PUT | `/api/hooks/:hookId/:token` |
| PATCH | `/api/hooks/:hookId/:token` |
| GET | `/api/hooks/:hookId/:token` |

Named helper and endpoint identifiers are available from `T3.HTTP.endpoints/0`.
Attachment upload URLs can include signed query strings; `T3.HTTP.upload/4`
preserves them and refuses cross-origin destinations.

## WebSocket RPC

211 methods, including 27 streams, use orchestration protocol 2 over `/ws`.
`T3.RPC.Methods` provides named wrappers; arbitrary names work through
`T3.RPC.call/4` or `subscribe/4`. Each stream delivers chunks to its subscriber,
which calls `ack/2` after consumption. `unsubscribe/2` sends an interrupt. The
transport handles Effect Request/Chunk/Ack/Exit/Ping/Pong/Interrupt framing,
server-originated replies, deadlines and disconnect cleanup without replay.

Use a permitted environment access token or a single-use RPC ticket from
`T3.HTTP.Auth.web_socket_ticket_for(http, "rpc")`. MCP OAuth client tokens are
rejected by T3 on this surface. TLS/loopback policy and token redaction apply.
Subscriptions may be long-lived; supply a total timeout when desired. Unary calls
have finite defaults and the pending-request limit is bounded.

| Method | Response |
|---|---|
| `agentSessions.import` | Unary |
| `agentSessions.scan` | Unary |
| `assets.createUrl` | Unary |
| `assets.persistChatAttachments` | Unary |
| `attachments.createUploadUrl` | Unary |
| `attachments.delete` | Unary |
| `cloud.getRelayClientStatus` | Unary |
| `cloud.installRelayClient` | Stream |
| `device.action` | Unary |
| `device.close` | Unary |
| `device.configure` | Unary |
| `device.detail` | Unary |
| `device.easAccount` | Unary |
| `device.list` | Unary |
| `device.open` | Unary |
| `device.shutdown` | Unary |
| `device.simlockIdentity` | Unary |
| `device.testHost` | Unary |
| `filesystem.browse` | Unary |
| `filesystem.getMetadata` | Unary |
| `git.preparePullRequestThread` | Unary |
| `git.resolvePullRequest` | Unary |
| `git.runStackedAction` | Stream |
| `guestShare.create` | Unary |
| `mcpApps.callTool` | Unary |
| `mcpApps.readResource` | Unary |
| `mcpApps.toolInfo` | Unary |
| `mcpApps.updateModelContext` | Unary |
| `orchestration.dispatchCommand` | Unary |
| `orchestration.forceStopThread` | Unary |
| `orchestration.getArchivedShellSnapshot` | Unary |
| `orchestration.getFullThreadDiff` | Unary |
| `orchestration.getNativeChildWork` | Unary |
| `orchestration.getOlderSettledThreads` | Unary |
| `orchestration.getThreadFamily` | Unary |
| `orchestration.getThreadProjection` | Unary |
| `orchestration.getThreadTitles` | Unary |
| `orchestration.getTurnDiff` | Unary |
| `orchestration.getTurnItem` | Unary |
| `orchestration.getWorkflowScript` | Unary |
| `orchestration.getWorktreeThreadIds` | Unary |
| `orchestration.launchThread` | Unary |
| `orchestration.searchThread` | Unary |
| `orchestration.searchThreadStream` | Stream |
| `orchestration.searchThreads` | Unary |
| `orchestration.stopWorkflow` | Unary |
| `orchestration.subscribeCommandOutput` | Stream |
| `orchestration.subscribeShell` | Stream |
| `orchestration.subscribeThread` | Stream |
| `peerLinks.answerRequest` | Unary |
| `peerLinks.link` | Unary |
| `peerLinks.list` | Unary |
| `peerLinks.unlink` | Unary |
| `preview.adjust` | Unary |
| `preview.clearProfile` | Unary |
| `preview.close` | Unary |
| `preview.list` | Unary |
| `preview.open` | Unary |
| `preview.reportProfiles` | Unary |
| `preview.reportStatus` | Unary |
| `preview.resize` | Unary |
| `preview.stopLocalServer` | Unary |
| `projectClone.cancel` | Unary |
| `projectClone.retry` | Unary |
| `projectClone.start` | Unary |
| `projects.createFromThread` | Unary |
| `projects.createNew` | Unary |
| `projects.ensureScratch` | Unary |
| `projects.listEntries` | Unary |
| `projects.listIgnoredFiles` | Unary |
| `projects.mutate` | Unary |
| `projects.readFile` | Unary |
| `projects.searchContents` | Unary |
| `projects.searchEntries` | Unary |
| `projects.writeFile` | Unary |
| `provider.auth.cancel` | Unary |
| `provider.auth.complete` | Unary |
| `provider.auth.logout` | Unary |
| `provider.auth.respond` | Unary |
| `provider.auth.start` | Unary |
| `provider.auth.subscribe` | Stream |
| `provider.chatgpt.handoff.subscribe` | Stream |
| `provider.chatgpt.import-profile` | Unary |
| `provider.chatgpt.reconnect-profile` | Unary |
| `provider.consumeResetCredit` | Unary |
| `provider.install.cancel` | Unary |
| `provider.install.remove` | Unary |
| `provider.install.start` | Unary |
| `provider.install.subscribe` | Stream |
| `provider.uploadFeedback` | Unary |
| `pullRequests.activity` | Unary |
| `pullRequests.changeBreakdown` | Unary |
| `pullRequests.checks` | Unary |
| `pullRequests.comment` | Unary |
| `pullRequests.detail` | Unary |
| `pullRequests.diffFileContents` | Unary |
| `pullRequests.filesViewed` | Unary |
| `pullRequests.filterOptions` | Unary |
| `pullRequests.generateReviewGuide` | Unary |
| `pullRequests.invalidate` | Unary |
| `pullRequests.labelCandidates` | Unary |
| `pullRequests.linkedThreads` | Unary |
| `pullRequests.list` | Unary |
| `pullRequests.listStats` | Unary |
| `pullRequests.preview` | Unary |
| `pullRequests.replyToThread` | Unary |
| `pullRequests.reportState` | Unary |
| `pullRequests.requestReviewers` | Unary |
| `pullRequests.reviewGuide` | Unary |
| `pullRequests.reviewerCandidates` | Unary |
| `pullRequests.routing` | Unary |
| `pullRequests.routingIdentity` | Unary |
| `pullRequests.runAction` | Unary |
| `pullRequests.setFilesViewed` | Unary |
| `pullRequests.setLabels` | Unary |
| `pullRequests.setReaction` | Unary |
| `pullRequests.setThreadResolution` | Unary |
| `pullRequests.stack` | Unary |
| `pullRequests.submitReview` | Unary |
| `pullRequests.subscribeRefreshes` | Stream |
| `pullRequests.summary` | Unary |
| `pullRequests.threadComments` | Unary |
| `pullRequests.update` | Unary |
| `pullRequests.updateComment` | Unary |
| `review.getBranchCommits` | Unary |
| `review.getDiffFileContents` | Unary |
| `review.getDiffPreview` | Unary |
| `scheduledTasks.delete` | Unary |
| `scheduledTasks.getWebhookDelivery` | Unary |
| `scheduledTasks.listWebhookDeliveries` | Unary |
| `scheduledTasks.rotateWebhookToken` | Unary |
| `scheduledTasks.runNow` | Unary |
| `scheduledTasks.setEnabled` | Unary |
| `scheduledTasks.subscribe` | Stream |
| `scheduledTasks.upsert` | Unary |
| `secrets.answerRequest` | Unary |
| `server.acceptAcpRegistryUrlAuth` | Unary |
| `server.checkOtlpEndpoint` | Unary |
| `server.commitDesktopUpdate` | Unary |
| `server.deleteAcpRegistrySession` | Unary |
| `server.disableAcpRegistryProvider` | Unary |
| `server.discoverSourceControl` | Unary |
| `server.getConfig` | Unary |
| `server.getDatabaseStorage` | Stream |
| `server.getHostResources` | Unary |
| `server.getNpmRelease` | Unary |
| `server.getProcessDiagnostics` | Unary |
| `server.getProcessResourceHistory` | Unary |
| `server.getResourceTelemetryHistory` | Unary |
| `server.getStorageCleanupReport` | Stream |
| `server.getTraceDiagnostics` | Unary |
| `server.getUsageSummary` | Unary |
| `server.importAcpRegistrySession` | Unary |
| `server.listAcpRegistryProviders` | Unary |
| `server.listAcpRegistrySessions` | Unary |
| `server.logoutAcpRegistry` | Unary |
| `server.prepareAcpRegistryAgent` | Unary |
| `server.prepareTriage` | Unary |
| `server.probe` | Unary |
| `server.refreshProviders` | Unary |
| `server.refreshUsageRates` | Unary |
| `server.removeKeybinding` | Unary |
| `server.reportClientActivity` | Unary |
| `server.retryResourceTelemetry` | Unary |
| `server.runStorageCleanup` | Unary |
| `server.searchAcpRegistry` | Unary |
| `server.setAcpRegistryProvider` | Unary |
| `server.signalProcess` | Unary |
| `server.uninstallAcpRegistryManagedBinary` | Unary |
| `server.updateProvider` | Unary |
| `server.updateServer` | Unary |
| `server.updateServerWithProgress` | Stream |
| `server.updateSettings` | Unary |
| `server.upsertKeybinding` | Unary |
| `shell.openInEditor` | Unary |
| `sourceControl.appAccess` | Unary |
| `sourceControl.cloneRepository` | Unary |
| `sourceControl.lookupRepository` | Unary |
| `sourceControl.publishRepository` | Unary |
| `sourceControl.signInCancel` | Unary |
| `sourceControl.signInStart` | Unary |
| `sourceControl.signInWait` | Unary |
| `sourceControl.star` | Unary |
| `sourceControl.starred` | Unary |
| `subscribeAuthAccess` | Stream |
| `subscribeDeviceState` | Stream |
| `subscribeDiscoveredLocalServers` | Stream |
| `subscribePreviewEvents` | Stream |
| `subscribeProjectClones` | Stream |
| `subscribeResourceTelemetry` | Stream |
| `subscribeServerConfig` | Stream |
| `subscribeServerLifecycle` | Stream |
| `subscribeTerminalMetadata` | Stream |
| `subscribeVcsStatus` | Stream |
| `subscribeWorktreeSetup` | Stream |
| `terminal.attach` | Stream |
| `terminal.clear` | Unary |
| `terminal.close` | Unary |
| `terminal.observe` | Stream |
| `terminal.open` | Unary |
| `terminal.resize` | Unary |
| `terminal.write` | Unary |
| `vcs.createRef` | Unary |
| `vcs.createWorktree` | Unary |
| `vcs.init` | Unary |
| `vcs.listRefs` | Unary |
| `vcs.pull` | Unary |
| `vcs.refreshStatus` | Unary |
| `vcs.removeWorktree` | Unary |
| `vcs.switchRef` | Unary |
| `worktreeSetup.cancel` | Unary |

## Additional HTTP routes and streaming

45 additional operations cover the raw routes outside EnvironmentHttpApi. Their
methods, patterns and authentication audiences are listed below. Device proxy
methods/payloads may be further constrained by the installed upstream hub. HEAD
and other supported proxy methods can use the generic request interface.

`T3.HTTP.Raw.call/3` buffers a bounded result; `Raw.stream/4`, `HTTP.stream/5` and
`HTTP.start_stream/5` consume bytes with callback backpressure and cancellation.
SSE uses Conduit's incremental decoder. The stream deadline applies even to a
blocked callback, and finite byte/event/per-event limits apply. Binary MJPEG,
AVCC and downloads remain unchanged. `T3.HTTP.multipart/2` delegates MIME encoding
to Multipart. Cookies, media tickets, Range and proof headers are explicit.

| ID | Method | Path | Encoding | Authentication |
|---|---|---|---|---|
| `asset` | GET | `/api/assets/:token/:fileName` | binary | asset_capability |
| `attachment_upload` | POST | `/api/attachments/upload/:token` | raw | upload_capability |
| `otlp_traces` | POST | `/api/observability/v1/traces` | json | orchestration_operate |
| `guest_redeem` | POST | `/api/guest/redeem` | json | share_credential |
| `guest_messages` | POST | `/api/guest/messages` | json_or_multipart | guest_cookie |
| `guest_session` | GET | `/api/guest/session` | none | guest_cookie |
| `guest_stream` | GET | `/api/guest/stream` | sse | guest_cookie |
| `guest_render` | GET | `/api/guest/render` | binary | guest_cookie |
| `guest_item` | GET | `/api/guest/item` | none | guest_cookie |
| `guest_history` | GET | `/api/guest/history` | none | guest_cookie |
| `guest_command_output` | GET | `/api/guest/command-output` | sse | guest_cookie |
| `guest_attachment` | GET | `/api/guest/attachment` | binary | guest_cookie |
| `guest_media` | GET | `/api/guest/media` | binary | guest_cookie |
| `preview_download` | GET | `/api/preview-stream/download` | binary | orchestration_read |
| `preview_upload` | POST | `/api/preview-stream/upload` | multipart | preview_operate |
| `device_list` | GET | `/api/device-hub/api/devices` | none | orchestration_read |
| `sim_api` | GET | `/api/device-hub/vendor/serve-sim/api` | none | orchestration_read |
| `sim_screenshot` | GET | `/api/device-hub/vendor/serve-sim/api/screenshot` | binary | orchestration_read |
| `sim_capture_screenshot` | POST | `/api/device-hub/vendor/serve-sim/api/screenshot` | json | orchestration_read |
| `sim_event_log` | GET | `/api/device-hub/vendor/serve-sim/api/event-log` | none | orchestration_read |
| `sim_event_log_events` | GET | `/api/device-hub/vendor/serve-sim/api/event-log/events` | sse | orchestration_read |
| `sim_mjpeg` | GET | `/api/device-hub/vendor/serve-sim/helper/:deviceId/stream.mjpeg` | binary_stream | orchestration_read |
| `sim_avcc` | GET | `/api/device-hub/vendor/serve-sim/helper/:deviceId/stream.avcc` | binary_stream | orchestration_read |
| `sim_panel_avcc` | GET | `/api/device-hub/vendor/serve-sim/helper/:deviceId/panel/:panel/stream.avcc` | binary_stream | orchestration_read |
| `sim_config` | GET | `/api/device-hub/vendor/serve-sim/helper/:deviceId/config` | none | orchestration_read |
| `sim_health` | GET | `/api/device-hub/vendor/serve-sim/helper/:deviceId/health` | none | orchestration_read |
| `sim_accessibility` | GET | `/api/device-hub/vendor/serve-sim/helper/:deviceId/ax` | none | orchestration_read |
| `sim_foreground` | GET | `/api/device-hub/vendor/serve-sim/helper/:deviceId/foreground` | none | orchestration_read |
| `sim_webrtc_offer` | POST | `/api/device-hub/vendor/serve-sim/helper/:deviceId/webrtc/offer` | json | orchestration_read |
| `sim_webrtc_close` | POST | `/api/device-hub/vendor/serve-sim/helper/:deviceId/webrtc/close` | json | orchestration_read |
| `sim_appstate` | GET | `/api/device-hub/vendor/serve-sim/appstate` | none | orchestration_read |
| `emu_api` | GET | `/api/device-hub/vendor/serve-emu/api` | none | orchestration_read |
| `emu_devices` | GET | `/api/device-hub/vendor/serve-emu/api/devices` | none | orchestration_read |
| `emu_screenshot` | GET | `/api/device-hub/vendor/serve-emu/api/screenshot` | binary | orchestration_read |
| `emu_capture_screenshot` | POST | `/api/device-hub/vendor/serve-emu/api/screenshot` | json | orchestration_read |
| `emu_stream_mode` | GET | `/api/device-hub/vendor/serve-emu/api/stream-mode` | none | orchestration_read |
| `emu_set_stream_mode` | POST | `/api/device-hub/vendor/serve-emu/api/stream-mode` | json | orchestration_operate |
| `emu_stream_settings` | GET | `/api/device-hub/vendor/serve-emu/api/stream-settings` | none | orchestration_read |
| `emu_set_stream_settings` | POST | `/api/device-hub/vendor/serve-emu/api/stream-settings` | json | orchestration_operate |
| `emu_accessibility` | GET | `/api/device-hub/vendor/serve-emu/api/accessibility` | none | orchestration_read |
| `emu_fold` | GET | `/api/device-hub/vendor/serve-emu/api/fold` | none | orchestration_read |
| `emu_set_fold` | POST | `/api/device-hub/vendor/serve-emu/api/fold` | json | orchestration_operate |
| `emu_health` | GET | `/api/device-hub/vendor/serve-emu/health` | none | orchestration_read |
| `emu_webrtc_offer` | POST | `/api/device-hub/vendor/serve-emu/webrtc/offer` | json | orchestration_read |
| `emu_webrtc_close` | POST | `/api/device-hub/vendor/serve-emu/webrtc/close` | json | orchestration_read |

## Raw WebSocket media routes

These four routes are distinct from Effect RPC. `T3.WebSocket.Routes` provides
helpers for each; `T3.WebSocket.start_link/1` accepts new route paths. Text and
binary data stay unchanged. A local delivery reference must be acknowledged to
release bounded backlog memory. Preview's `preview_ack/2` also sends the server's
JSON ACK. A raw frame API is not a video codec, WebRTC stack or PTY renderer.

| Helper | Path | Scope |
|---|---|---|
| `preview` | `/api/preview-stream/ws` | `orchestration:read` |
| `devices` | `/api/device-hub/api/devices/ws` | `orchestration:read` |
| `simulator` | `/api/device-hub/vendor/serve-sim/helper/ws` | `orchestration:operate` |
| `emulator` | `/api/device-hub/vendor/serve-emu/ws` | `orchestration:operate` |

Use a media-bound ticket or permitted environment/media credential, not an MCP
OAuth token. The adapter does not follow redirects or reconnect automatically.
Frame bytes, incomplete fragments and unacknowledged deliveries are bounded;
idle and total lifetime limits are configurable. Owner death closes the transport.

## Local CLI

`T3.CLI.run/2` accepts every command implemented by the installed executable,
passing an argument vector without a shell. `commands/2` discovers the actual
version's help tree; it does not assume the pinned upstream CLI matches your host.
Named family helpers are available for start, serve, app, pair, auth, browser,
project, service, update, uninstall, theme, trace, doctor, triage, connect and thread.
The installed snapshot is `priv/t3/cli.json` (`t3 v0.1.1`); it lacks newer thread
commands. There is no automatic upgrade or mutation during discovery.

Exile supplies native subprocess IO and lifecycle on Linux/macOS. A C compiler
and make are required to build it. The SDK supports finite stdin and interactive
stdin write/EOF, merged stdout/stderr, deadlines and output limits. It is not a
PTY and does not expose arbitrary inherited file descriptors. Cancellation kills
the directly invoked executable; detached descendant processes are outside the
SDK's ownership. As with any process, cleanup cannot survive killing the entire VM.

## Validation boundaries

The catalog completeness tests check typed HTTP routes against the pinned contract and
MCP/RPC helpers against their source inventories. Actual local HTTP and WebSocket
fixtures test protocol behavior and errors; subprocess fixtures test OS IO and
termination. This is transport/contract coverage, not proof that every operation's
business semantics work against a live T3 installation. No destructive T3 command
was run for validation. Authenticated HTTP/RPC live workflows need appropriate
credentials and remain distinct from the successful external MCP sign-in.

Included source snapshots are MIT-licensed T3 Tools Inc. code; see
`priv/t3/UPSTREAM_LICENSE`. They document the upstream contract and are not
compiled or executed by this package.
