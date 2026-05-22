defmodule Mob.Transport.Adapter do
  @moduledoc """
  GenServer wrapper for a single transport implementation.

  The adapter owns the carrier process, sets itself as the transport's
  `:event_target`, normalizes inbound events, and forwards canonical events to
  the outer `:event_target`.
  """

  use GenServer

  alias Mob.Transport.Telemetry

  require Logger

  @type option ::
          {:transport, module()}
          | {:event_target, pid()}
          | {:on_unknown_event, :drop | :forward_error}
          | {:transport_opts, keyword()}

  @type state :: %{
          transport: module(),
          transport_pid: pid(),
          event_target: pid(),
          on_unknown_event: :drop | :forward_error
        }

  @doc """
  Starts an adapter for a transport module.

  Required options:

    * `:transport` - module implementing `Mob.Transport`
    * `:event_target` - process that receives normalized events

  Adapter-specific options are removed before startup. Any `:transport_opts`
  are merged into the remaining options and passed to the transport with
  `:event_target` set to the adapter process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc """
  Sends a frame through the wrapped transport.
  """
  @spec send_frame(GenServer.server(), term(), binary(), keyword()) :: :ok | {:error, term()}
  def send_frame(adapter, peer_id, frame, opts \\ []) when is_binary(frame) do
    GenServer.call(adapter, {:send_frame, peer_id, frame, opts})
  end

  @doc """
  Broadcasts a frame when the wrapped transport supports broadcast.
  """
  @spec broadcast_frame(GenServer.server(), binary(), keyword()) :: :ok | {:error, term()}
  def broadcast_frame(adapter, frame, opts \\ []) when is_binary(frame) do
    GenServer.call(adapter, {:broadcast_frame, frame, opts})
  end

  @doc """
  Stops the adapter and its owned transport.
  """
  @spec stop(GenServer.server()) :: :ok
  def stop(adapter), do: GenServer.stop(adapter)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    with {:ok, transport} <- fetch_transport(opts),
         :ok <- ensure_callback(transport, :start_link, 1),
         {:ok, event_target} <- fetch_event_target(opts),
         {:ok, on_unknown_event} <- fetch_unknown_event_policy(opts),
         transport_opts = transport_opts(opts),
         {:ok, transport_pid} <- start_transport(transport, transport_opts) do
      Logger.debug("Mob.Transport.Adapter started transport #{inspect(transport)}")

      {:ok,
       %{
         transport: transport,
         transport_pid: transport_pid,
         event_target: event_target,
         on_unknown_event: on_unknown_event
       }}
    end
  end

  @impl true
  def handle_call({:send_frame, peer_id, frame, opts}, _from, state) do
    reply = state.transport.send_frame(state.transport_pid, peer_id, frame, opts)
    emit_send_telemetry(reply, peer_id, frame, state)
    {:reply, reply, state}
  end

  def handle_call({:broadcast_frame, frame, opts}, _from, state) do
    reply =
      if function_exported?(state.transport, :broadcast_frame, 3) do
        state.transport.broadcast_frame(state.transport_pid, frame, opts)
      else
        {:error, :broadcast_not_supported}
      end

    emit_send_telemetry(reply, :broadcast, frame, state)
    {:reply, reply, state}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, %{transport_pid: pid} = state) do
    Telemetry.emit(:error, %{count: 1}, %{
      reason: {:transport_exit, reason},
      transport: state.transport
    })

    Logger.warning(
      "Mob.Transport.Adapter transport #{inspect(state.transport)} exited: #{inspect(reason)}"
    )

    {:stop, {:transport_exit, reason}, state}
  end

  def handle_info(event, state) do
    case Mob.Transport.normalize_event(event) do
      {:ok, normalized} ->
        emit_event_telemetry(normalized, state)
        send(state.event_target, normalized)

      {:error, _reason} = error ->
        handle_unknown_event(error, event, state)
    end

    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    stop_transport(state)
    :ok
  end

  defp fetch_transport(opts) do
    case Keyword.fetch(opts, :transport) do
      {:ok, transport} when is_atom(transport) -> {:ok, transport}
      {:ok, other} -> {:error, {:invalid_transport, other}}
      :error -> {:error, {:missing_required_option, :transport}}
    end
  end

  defp ensure_callback(module, function, arity) do
    with {:module, ^module} <- Code.ensure_loaded(module),
         true <- function_exported?(module, function, arity) do
      :ok
    else
      false -> {:error, {:missing_callback, module, function, arity}}
      {:error, reason} -> {:error, {:transport_not_loaded, module, reason}}
    end
  end

  defp fetch_event_target(opts) do
    case Keyword.fetch(opts, :event_target) do
      {:ok, pid} when is_pid(pid) -> {:ok, pid}
      {:ok, other} -> {:error, {:invalid_event_target, other}}
      :error -> {:error, {:missing_required_option, :event_target}}
    end
  end

  defp fetch_unknown_event_policy(opts) do
    case Keyword.get(opts, :on_unknown_event, :drop) do
      policy when policy in [:drop, :forward_error] -> {:ok, policy}
      other -> {:error, {:invalid_unknown_event_policy, other}}
    end
  end

  defp transport_opts(opts) do
    base_opts =
      Keyword.drop(opts, [:transport, :event_target, :on_unknown_event, :transport_opts])

    extra_opts = Keyword.get(opts, :transport_opts, [])

    base_opts
    |> Keyword.merge(extra_opts)
    |> Keyword.put(:event_target, self())
  end

  defp start_transport(transport, opts) do
    case transport.start_link(opts) do
      {:ok, pid} when is_pid(pid) -> {:ok, pid}
      {:error, reason} -> {:error, {:transport_start_failed, reason}}
      other -> {:error, {:invalid_transport_start_return, other}}
    end
  end

  defp handle_unknown_event({:error, reason}, event, %{on_unknown_event: :forward_error} = state) do
    Telemetry.emit(:error, %{count: 1}, %{
      reason: reason,
      event: event,
      transport: state.transport
    })

    send(state.event_target, {:transport_error, reason})
    Logger.debug("Mob.Transport.Adapter forwarded unknown event: #{inspect(event)}")
  end

  defp handle_unknown_event({:error, reason}, event, state) do
    Telemetry.emit(:error, %{count: 1}, %{
      reason: reason,
      event: event,
      transport: state.transport
    })

    Logger.debug(
      "Mob.Transport.Adapter dropped unknown event #{inspect(event)}: #{inspect(reason)}"
    )
  end

  defp emit_event_telemetry({:transport_up, peer_id, metadata}, state) do
    Telemetry.emit(:up, %{count: 1}, %{
      peer_id: peer_id,
      metadata: metadata,
      transport: state.transport
    })
  end

  defp emit_event_telemetry({:transport_down, peer_id}, state) do
    Telemetry.emit(:down, %{count: 1}, %{
      peer_id: peer_id,
      transport: state.transport
    })
  end

  defp emit_event_telemetry({:frame, peer_id, frame}, state) do
    Telemetry.emit([:frame, :received], %{bytes: byte_size(frame)}, %{
      peer_id: peer_id,
      transport: state.transport
    })
  end

  defp emit_event_telemetry({:transport_error, reason}, state) do
    Telemetry.emit(:error, %{count: 1}, %{
      reason: reason,
      transport: state.transport
    })
  end

  defp emit_send_telemetry(:ok, peer_id, frame, state) do
    Telemetry.emit([:frame, :sent], %{bytes: byte_size(frame)}, %{
      peer_id: peer_id,
      transport: state.transport
    })
  end

  defp emit_send_telemetry({:error, reason}, peer_id, _frame, state) do
    Telemetry.emit(:error, %{count: 1}, %{
      reason: reason,
      peer_id: peer_id,
      transport: state.transport
    })
  end

  defp emit_send_telemetry(_other, _peer_id, _frame, _state), do: :ok

  defp stop_transport(%{transport: transport, transport_pid: pid}) do
    cond do
      not Process.alive?(pid) ->
        :ok

      function_exported?(transport, :stop, 1) ->
        _ = transport.stop(pid)
        :ok

      true ->
        Process.exit(pid, :shutdown)
        :ok
    end
  end
end
