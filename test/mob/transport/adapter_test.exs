defmodule Mob.Transport.AdapterTest do
  use ExUnit.Case, async: true

  alias Mob.Transport.Adapter
  alias Mob.Transport.FakeTransport

  test "starts a transport with the adapter as the transport event target" do
    {:ok, adapter} = Adapter.start_link(transport: FakeTransport, event_target: self())
    %{transport_pid: transport_pid} = :sys.get_state(adapter)

    assert FakeTransport.event_target(transport_pid) == adapter
  end

  test "forwards normalized events to the outer event target" do
    {:ok, adapter} = Adapter.start_link(transport: FakeTransport, event_target: self())
    %{transport_pid: transport_pid} = :sys.get_state(adapter)

    FakeTransport.emit(transport_pid, {:ble_peer_up, "peer", %{name: "device"}})
    FakeTransport.emit(transport_pid, {:ble_frame, "peer", "hello"})
    FakeTransport.emit(transport_pid, {:ble_peer_down, "peer"})

    assert_receive {:transport_up, "peer", %{name: "device"}}
    assert_receive {:frame, "peer", "hello"}
    assert_receive {:transport_down, "peer"}
  end

  test "emits telemetry for normalized events" do
    attach_telemetry([
      [:mob, :transport, :up],
      [:mob, :transport, :frame, :received],
      [:mob, :transport, :down]
    ])

    {:ok, adapter} = Adapter.start_link(transport: FakeTransport, event_target: self())
    %{transport_pid: transport_pid} = :sys.get_state(adapter)

    FakeTransport.emit(transport_pid, {:transport_up, "peer", %{}})
    FakeTransport.emit(transport_pid, {:frame, "peer", "hello"})
    FakeTransport.emit(transport_pid, {:transport_down, "peer"})

    assert_receive {:telemetry_event, [:mob, :transport, :up], %{count: 1}, %{peer_id: "peer"}}

    assert_receive {:telemetry_event, [:mob, :transport, :frame, :received], %{bytes: 5},
                    %{peer_id: "peer"}}

    assert_receive {:telemetry_event, [:mob, :transport, :down], %{count: 1}, %{peer_id: "peer"}}
  end

  test "delegates send_frame and broadcast_frame to the transport" do
    {:ok, adapter} =
      Adapter.start_link(transport: FakeTransport, event_target: self(), test_pid: self())

    assert :ok = Adapter.send_frame(adapter, "peer", "payload", priority: :high)
    assert :ok = Adapter.broadcast_frame(adapter, "broadcast", ttl: 1)

    assert_receive {:sent_frame, "peer", "payload", priority: :high}
    assert_receive {:broadcast_frame, "broadcast", ttl: 1}
  end

  test "emits telemetry for sent frames" do
    attach_telemetry([[:mob, :transport, :frame, :sent]])

    {:ok, adapter} =
      Adapter.start_link(transport: FakeTransport, event_target: self(), test_pid: self())

    assert :ok = Adapter.send_frame(adapter, "peer", "payload")

    assert_receive {:telemetry_event, [:mob, :transport, :frame, :sent], %{bytes: 7},
                    %{peer_id: "peer"}}
  end

  test "can forward unknown events as transport errors" do
    {:ok, adapter} =
      Adapter.start_link(
        transport: FakeTransport,
        event_target: self(),
        on_unknown_event: :forward_error
      )

    %{transport_pid: transport_pid} = :sys.get_state(adapter)
    FakeTransport.emit(transport_pid, {:carrier_specific, :event})

    assert_receive {:transport_error, {:unknown_event, {:carrier_specific, :event}}}
  end

  test "forwards malformed frame errors when configured" do
    {:ok, adapter} =
      Adapter.start_link(
        transport: FakeTransport,
        event_target: self(),
        on_unknown_event: :forward_error
      )

    %{transport_pid: transport_pid} = :sys.get_state(adapter)
    FakeTransport.emit(transport_pid, {:frame, "peer", :not_binary})

    assert_receive {:transport_error, {:invalid_frame, :not_binary}}
  end

  test "stops when the owned transport exits" do
    Process.flag(:trap_exit, true)

    {:ok, adapter} = Adapter.start_link(transport: FakeTransport, event_target: self())
    %{transport_pid: transport_pid} = :sys.get_state(adapter)

    FakeTransport.crash(transport_pid, :boom)

    assert_receive {:EXIT, ^adapter, {:transport_exit, :boom}}
  after
    Process.flag(:trap_exit, false)
  end

  defp attach_telemetry(events) do
    test_pid = self()
    ref = make_ref()

    :ok =
      :telemetry.attach_many(
        "adapter-test-#{inspect(ref)}",
        events,
        &__MODULE__.handle_telemetry/4,
        test_pid
      )

    on_exit(fn -> :telemetry.detach("adapter-test-#{inspect(ref)}") end)
  end

  def handle_telemetry(event, measurements, metadata, test_pid) do
    send(test_pid, {:telemetry_event, event, measurements, metadata})
  end
end
