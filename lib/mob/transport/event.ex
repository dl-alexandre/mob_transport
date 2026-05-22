defmodule Mob.Transport.Event do
  @moduledoc """
  Canonical event contract for `mob` transport plugins.

  The contract intentionally stays tuple-based so transport plugins can emit
  events without depending on any struct versioning or router modules.
  """

  @type peer_id :: term()
  @type metadata :: term()
  @type frame :: binary()
  @type t ::
          {:transport_up, peer_id(), metadata()}
          | {:transport_down, peer_id()}
          | {:frame, peer_id(), frame()}
          | {:transport_error, term()}

  @doc """
  Normalizes canonical and known carrier-specific event tuples.
  """
  @spec normalize(term()) :: {:ok, t()} | {:error, {:unknown_event, term()}}
  def normalize({:transport_up, _peer_id, _metadata} = event), do: {:ok, event}
  def normalize({:transport_down, _peer_id} = event), do: {:ok, event}
  def normalize({:frame, _peer_id, frame} = event) when is_binary(frame), do: {:ok, event}
  def normalize({:transport_error, _reason} = event), do: {:ok, event}

  def normalize({:ble_peer_up, peer_id, metadata}), do: {:ok, {:transport_up, peer_id, metadata}}
  def normalize({:ble_peer_down, peer_id}), do: {:ok, {:transport_down, peer_id}}

  def normalize({:ble_frame, peer_id, frame}) when is_binary(frame),
    do: {:ok, {:frame, peer_id, frame}}

  def normalize(event), do: {:error, {:unknown_event, event}}
end
