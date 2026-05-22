defmodule Mob.Transport.FakeTransport do
  @moduledoc false

  @behaviour Mob.Transport

  use GenServer

  @impl true
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def send_frame(transport, peer_id, frame, opts) do
    GenServer.call(transport, {:send_frame, peer_id, frame, opts})
  end

  @impl true
  def broadcast_frame(transport, frame, opts) do
    GenServer.call(transport, {:broadcast_frame, frame, opts})
  end

  @impl true
  def stop(transport), do: GenServer.stop(transport)

  def emit(transport, event), do: GenServer.cast(transport, {:emit, event})

  def event_target(transport), do: GenServer.call(transport, :event_target)

  @impl true
  def init(opts) do
    {:ok,
     %{event_target: Keyword.fetch!(opts, :event_target), test_pid: Keyword.get(opts, :test_pid)}}
  end

  @impl true
  def handle_call(:event_target, _from, state) do
    {:reply, state.event_target, state}
  end

  def handle_call({:send_frame, peer_id, frame, opts}, _from, state) do
    send_test_message(state, {:sent_frame, peer_id, frame, opts})
    {:reply, :ok, state}
  end

  def handle_call({:broadcast_frame, frame, opts}, _from, state) do
    send_test_message(state, {:broadcast_frame, frame, opts})
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:emit, event}, state) do
    send(state.event_target, event)
    {:noreply, state}
  end

  defp send_test_message(%{test_pid: nil}, _message), do: :ok
  defp send_test_message(%{test_pid: test_pid}, message), do: send(test_pid, message)
end
