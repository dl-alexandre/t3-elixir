defmodule T3.HTTP.Catalog do
  @moduledoc """
  HTTP routes declared by T3's `EnvironmentHttpApi` contract.

  Payloads and query values use their original string-keyed wire maps. This
  catalog describes transport routing, not complete payload schema validation.
  OAuth token exchanges are form encoded. Voice uploads use raw request bodies.
  Orchestration reads send protocol 2.
  Authentication capabilities depend on credential scopes and server version;
  MCP OAuth credentials are not assumed to grant access to every HTTP route.
  """

  @routes [
    {:metadata, :descriptor, :get, "/.well-known/t3/environment", :none},
    {:auth, :session, :get, "/api/auth/session", :none},
    {:auth, :browser_session, :post, "/api/auth/browser-session", :json},
    {:auth, :token, :post, "/oauth/token", :form},
    {:auth, :web_socket_ticket, :post, "/api/auth/websocket-ticket", :none},
    {:auth, :web_socket_ticket_for, :post, "/api/auth/websocket-ticket/:use", :none},
    {:auth, :pairing_credential, :post, "/api/auth/pairing-token", :json},
    {:auth, :revoke_pairing_link, :post, "/api/auth/pairing-links/revoke", :json},
    {:auth, :revoke_client, :post, "/api/auth/clients/revoke", :json},
    {:auth, :revoke_other_clients, :post, "/api/auth/clients/revoke-others", :none},
    {:auth, :approve_connect_device, :post, "/api/auth/connect-devices/approve", :json},
    {:auth, :revoke_connect_device, :post, "/api/auth/connect-devices/revoke", :json},
    {:oauth, :protected_resource, :get, "/.well-known/oauth-protected-resource", :none},
    {:oauth, :mcp_protected_resource, :get, "/.well-known/oauth-protected-resource/mcp", :none},
    {:oauth, :authorization_server, :get, "/.well-known/oauth-authorization-server", :none},
    {:oauth, :register, :post, "/oauth/mcp/register", :json},
    {:oauth, :authorize, :get, "/oauth/mcp/authorize", :none},
    {:oauth, :approval, :post, "/oauth/mcp/approval", :json},
    {:oauth, :decision, :post, "/oauth/mcp/decision", :json},
    {:oauth, :token, :post, "/oauth/mcp/token", :form},
    {:oauth, :revoke, :post, "/oauth/mcp/revoke", :json},
    {:orchestration, :shell_snapshot, :get, "/api/orchestration/shell", :none},
    {:orchestration, :thread_snapshot, :get, "/api/orchestration/threads/:threadId", :none},
    {:orchestration, :thread_transcript, :get, "/api/orchestration/threads/:threadId/transcript",
     :none},
    {:orchestration, :thread_bounded_snapshot, :get,
     "/api/orchestration/threads/:threadId/bounded", :none},
    {:orchestration, :thread_history_page, :get, "/api/orchestration/threads/:threadId/history",
     :none},
    {:projects, :snapshot, :get, "/api/projects", :none},
    {:projects, :mutate, :post, "/api/projects/mutate", :json},
    {:pull_requests, :diff, :post, "/api/pull-requests/diff", :json},
    {:voice, :cloud_keys, :get, "/api/voice/cloud/keys", :none},
    {:voice, :set_cloud_key, :post, "/api/voice/cloud/:provider/key", :json},
    {:voice, :cloud_models, :get, "/api/voice/cloud/openrouter/models", :none},
    {:voice, :transcribe_cloud, :post, "/api/voice/cloud/:provider/transcribe", :body},
    {:voice, :status, :get, "/api/voice/status", :none},
    {:voice, :prepare_model, :post, "/api/voice/models/prepare", :none},
    {:voice, :models, :get, "/api/voice/models", :none},
    {:voice, :download_model, :post, "/api/voice/models/download", :json},
    {:voice, :select_model, :post, "/api/voice/models/select", :json},
    {:voice, :cancel_model_download, :post, "/api/voice/models/cancel", :json},
    {:voice, :remove_model, :post, "/api/voice/models/remove", :json},
    {:voice, :link_models, :post, "/api/voice/models/link", :json},
    {:voice, :update_acceleration, :post, "/api/voice/acceleration", :json},
    {:voice, :update_model_unload_timeout, :post, "/api/voice/model-unload-timeout", :json},
    {:voice, :transcribe, :post, "/api/voice/transcribe", :body},
    {:voice, :post_process, :post, "/api/voice/post-process", :json},
    {:connect, :link_proof, :post, "/api/connect/link-proof", :json},
    {:connect, :relay_config, :post, "/api/connect/relay-config", :json},
    {:connect, :link_state, :get, "/api/connect/link-state", :none},
    {:connect, :check_reachability, :post, "/api/connect/reachability", :none},
    {:connect, :unlink, :post, "/api/connect/unlink", :none},
    {:connect, :preferences, :post, "/api/connect/preferences", :json},
    {:connect, :live_activity_preference, :post, "/api/connect/live-activity-preference", :json},
    {:connect, :health, :post, "/api/t3-connect/health", :json},
    {:connect, :mint_credential, :post, "/api/t3-connect/mint-credential", :json},
    {:peer_link, :client_pairing, :post, "/api/peer-link/client-pairing", :json},
    {:webhooks, :post, :post, "/api/hooks/:hookId/:token", :raw},
    {:webhooks, :put, :put, "/api/hooks/:hookId/:token", :raw},
    {:webhooks, :patch, :patch, "/api/hooks/:hookId/:token", :raw},
    {:webhooks, :get, :get, "/api/hooks/:hookId/:token", :raw}
  ]

  @doc "All route specifications, with stable atom identifiers and path parameter names."
  def all do
    Enum.map(@routes, fn {group, name, method, path, encoding} ->
      %{
        id: String.to_atom("#{group}_#{name}"),
        group: group,
        name: name,
        method: method,
        path: path,
        encoding: encoding,
        path_params:
          Regex.scan(~r/:([A-Za-z][A-Za-z0-9]*)/, path, capture: :all_but_first) |> List.flatten(),
        orchestration_protocol: group == :orchestration
      }
    end)
  end

  @doc "Find a known endpoint without converting untrusted strings to atoms."
  def fetch(id), do: Enum.find(all(), &(&1.id == id or Atom.to_string(&1.id) == id))
end
