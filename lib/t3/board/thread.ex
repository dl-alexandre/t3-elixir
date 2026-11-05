defmodule T3.Board.Thread do
  @moduledoc """
  Small board row, independent of T3's wire projection.

  `state` is a T3 run status string, `"idle"`, or `"archived"`. Timestamps retain
  their original ISO 8601 strings; no timezone or display formatting is applied.
  `__meta__` is internal reducer bookkeeping; retain it when caching rows. It is
  excluded from Inspect and is not a board display field.
  `host` is the caller's stable environment label, never inferred from a payload.
  """
  @derive {Inspect, except: [:__meta__]}
  @type t :: %__MODULE__{
          thread_id: String.t() | nil,
          title: String.t() | nil,
          state: String.t() | nil,
          last_turn_at: String.t() | nil,
          last_message_snippet: String.t() | nil,
          host: term(),
          __meta__: map()
        }
  defstruct [
    :thread_id,
    :title,
    :state,
    :last_turn_at,
    :last_message_snippet,
    :host,
    __meta__: %{}
  ]
end
