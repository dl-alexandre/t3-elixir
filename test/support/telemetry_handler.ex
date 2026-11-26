defmodule T3.TelemetryTestHandler do
  @moduledoc false

  def handle(event, measurements, metadata, owner) do
    send(owner, {:telemetry_event, event, measurements, metadata})
  end
end
