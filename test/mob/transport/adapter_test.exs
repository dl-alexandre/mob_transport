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

  test "delegates send_frame and broadcast_frame to the transport" do
    {:ok, adapter} =
      Adapter.start_link(transport: FakeTransport, event_target: self(), test_pid: self())

    assert :ok = Adapter.send_frame(adapter, "peer", "payload", priority: :high)
    assert :ok = Adapter.broadcast_frame(adapter, "broadcast", ttl: 1)

    assert_receive {:sent_frame, "peer", "payload", priority: :high}
    assert_receive {:broadcast_frame, "broadcast", ttl: 1}
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
end
