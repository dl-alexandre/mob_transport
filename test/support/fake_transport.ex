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

  def crash(transport, reason \\ :boom), do: GenServer.cast(transport, {:crash, reason})

  def event_target(transport), do: GenServer.call(transport, :event_target)

  @impl true
  def init(opts) do
    {:ok,
     %{
       event_target: Keyword.fetch!(opts, :event_target),
       test_pid: Keyword.get(opts, :test_pid),
       send_reply: Keyword.get(opts, :send_reply, :ok),
       broadcast_reply: Keyword.get(opts, :broadcast_reply, :ok),
       latency_ms: Keyword.get(opts, :latency_ms, 0),
       echo?: Keyword.get(opts, :echo?, false)
     }}
  end

  @impl true
  def handle_call(:event_target, _from, state) do
    {:reply, state.event_target, state}
  end

  def handle_call({:send_frame, peer_id, frame, opts}, _from, state) do
    maybe_sleep(state)
    send_test_message(state, {:sent_frame, peer_id, frame, opts})
    if state.echo?, do: send(state.event_target, {:frame, peer_id, frame})
    {:reply, state.send_reply, state}
  end

  def handle_call({:broadcast_frame, frame, opts}, _from, state) do
    maybe_sleep(state)
    send_test_message(state, {:broadcast_frame, frame, opts})
    if state.echo?, do: send(state.event_target, {:frame, :broadcast, frame})
    {:reply, state.broadcast_reply, state}
  end

  @impl true
  def handle_cast({:emit, event}, state) do
    send(state.event_target, event)
    {:noreply, state}
  end

  def handle_cast({:crash, reason}, state) do
    {:stop, reason, state}
  end

  defp maybe_sleep(%{latency_ms: latency_ms}) when latency_ms > 0, do: Process.sleep(latency_ms)
  defp maybe_sleep(_state), do: :ok

  defp send_test_message(%{test_pid: nil}, _message), do: :ok
  defp send_test_message(%{test_pid: test_pid}, message), do: send(test_pid, message)
end

defmodule Mob.Transport.MinimalTransport do
  @moduledoc false

  @behaviour Mob.Transport

  use GenServer

  @impl true
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def send_frame(transport, peer_id, frame, opts) do
    GenServer.call(transport, {:send_frame, peer_id, frame, opts})
  end

  def event_target(transport), do: GenServer.call(transport, :event_target)

  @impl true
  def init(opts), do: {:ok, %{event_target: Keyword.fetch!(opts, :event_target)}}

  @impl true
  def handle_call(:event_target, _from, state) do
    {:reply, state.event_target, state}
  end

  def handle_call({:send_frame, peer_id, frame, _opts}, _from, state) do
    send(state.event_target, {:frame, peer_id, frame})
    {:reply, :ok, state}
  end
end

defmodule Mob.Transport.MissingSendFrameTransport do
  @moduledoc false

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
end
