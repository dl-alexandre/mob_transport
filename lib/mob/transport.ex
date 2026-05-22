defmodule Mob.Transport do
  @moduledoc """
  Common behaviour and adapter helpers for `mob` transport plugins.

  Transport implementations own the carrier-specific details (BLE, WiFi,
  mesh, or another medium). `Mob.Transport` defines the small callback and
  event contract that lets `mob` attach those implementations uniformly.

  ## Behaviour

  A transport module starts an owned process with `start_link/1`, sends frames
  to peers with `send_frame/4`, and may implement `stop/1` or
  `broadcast_frame/3` when the carrier supports those operations.

  ## Events

  Transport implementations send events to the `:event_target` supplied at
  startup. `Mob.Transport.Adapter` sets itself as that target, normalizes
  carrier-specific event tuples, and forwards canonical events to the outer
  caller.
  """

  alias Mob.Transport.Event

  @type transport :: module()
  @type peer_id :: term()
  @type metadata :: term()
  @type frame :: binary()
  @type event :: Event.t()
  @type normalize_result :: {:ok, event()} | {:error, {:unknown_event, term()}}

  @callback start_link(keyword()) :: GenServer.on_start()
  @callback send_frame(pid(), peer_id(), frame(), keyword()) :: :ok | {:error, term()}

  @callback stop(pid()) :: :ok | {:error, term()}
  @callback broadcast_frame(pid(), frame(), keyword()) :: :ok | {:error, term()}

  @optional_callbacks stop: 1, broadcast_frame: 3

  @doc """
  Returns the behaviour module for runtime checks and plugin metadata.
  """
  @spec behaviour() :: module()
  def behaviour, do: __MODULE__

  @doc """
  Normalizes carrier-specific transport events into the common event contract.

  Canonical events are passed through unchanged:

    * `{:transport_up, peer_id, metadata}`
    * `{:transport_down, peer_id}`
    * `{:frame, peer_id, frame}`
    * `{:transport_error, reason}`

  The initial compatibility layer also accepts the current `mob_ble` bridge
  events:

    * `{:ble_peer_up, peer_id, metadata}`
    * `{:ble_peer_down, peer_id}`
    * `{:ble_frame, peer_id, frame}`
  """
  @spec normalize_event(term()) :: normalize_result()
  def normalize_event(event), do: Event.normalize(event)

  @doc """
  Same as `normalize_event/1`, but raises on unknown event shapes.
  """
  @spec normalize_event!(term()) :: event()
  def normalize_event!(event) do
    case normalize_event(event) do
      {:ok, normalized} -> normalized
      {:error, reason} -> raise ArgumentError, "unknown transport event: #{inspect(reason)}"
    end
  end
end
