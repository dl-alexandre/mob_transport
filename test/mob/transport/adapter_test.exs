defmodule Mob.Transport.AdapterTest do
  use ExUnit.Case, async: true

  alias Mob.Transport.Adapter
  alias Mob.Transport.FakeTransport
  alias Mob.Transport.MinimalTransport
  alias Mob.Transport.MissingSendFrameTransport

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

  test "echo-capable test transport exercises full send and receive flow" do
    {:ok, adapter} =
      Adapter.start_link(
        transport: FakeTransport,
        event_target: self(),
        test_pid: self(),
        echo?: true
      )

    assert :ok = Adapter.send_frame(adapter, "peer", "hello")

    assert_receive {:sent_frame, "peer", "hello", []}
    assert_receive {:frame, "peer", "hello"}
  end

  test "large binary frames flow through send and receive paths" do
    large_frame = :crypto.strong_rand_bytes(256_000)

    {:ok, adapter} =
      Adapter.start_link(
        transport: FakeTransport,
        event_target: self(),
        test_pid: self(),
        echo?: true
      )

    assert :ok = Adapter.send_frame(adapter, "peer", large_frame)

    assert_receive {:sent_frame, "peer", ^large_frame, []}
    assert_receive {:frame, "peer", ^large_frame}
  end

  test "latency and failure injection return the underlying transport error" do
    {:ok, adapter} =
      Adapter.start_link(
        transport: FakeTransport,
        event_target: self(),
        test_pid: self(),
        latency_ms: 5,
        send_reply: {:error, :offline}
      )

    assert {:error, :offline} = Adapter.send_frame(adapter, "peer", "payload")
    assert_receive {:sent_frame, "peer", "payload", []}
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

  test "returns a clear error when broadcast is not implemented by the transport" do
    {:ok, adapter} = Adapter.start_link(transport: MinimalTransport, event_target: self())

    assert {:error, :broadcast_not_supported} = Adapter.broadcast_frame(adapter, "broadcast")
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

  test "drops malformed events without crashing by default" do
    {:ok, adapter} = Adapter.start_link(transport: FakeTransport, event_target: self())
    %{transport_pid: transport_pid} = :sys.get_state(adapter)

    FakeTransport.emit(transport_pid, {:frame, "peer", :not_binary})
    FakeTransport.emit(transport_pid, {:carrier_specific, :event})

    refute_receive {:transport_error, _reason}, 50
    assert Process.alive?(adapter)
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

  test "rejects transports missing required callbacks during startup" do
    assert {:error, {:missing_callback, MissingSendFrameTransport, :send_frame, 4}} =
             Adapter.start_link(transport: MissingSendFrameTransport, event_target: self())
  end

  test "multiple adapters dispatch events to their own event targets" do
    parent = self()

    target_a =
      spawn_link(fn ->
        send(parent, {:target_ready, :a, self()})

        receive do
          message -> send(parent, {:target_a_received, message})
        end
      end)

    target_b =
      spawn_link(fn ->
        send(parent, {:target_ready, :b, self()})

        receive do
          message -> send(parent, {:target_b_received, message})
        end
      end)

    assert_receive {:target_ready, :a, ^target_a}
    assert_receive {:target_ready, :b, ^target_b}

    {:ok, adapter_a} = Adapter.start_link(transport: FakeTransport, event_target: target_a)
    {:ok, adapter_b} = Adapter.start_link(transport: FakeTransport, event_target: target_b)

    %{transport_pid: transport_a} = :sys.get_state(adapter_a)
    %{transport_pid: transport_b} = :sys.get_state(adapter_b)

    FakeTransport.emit(transport_a, {:frame, "peer-a", "a"})
    FakeTransport.emit(transport_b, {:frame, "peer-b", "b"})

    assert_receive {:target_a_received, {:frame, "peer-a", "a"}}
    assert_receive {:target_b_received, {:frame, "peer-b", "b"}}
  end

  test "handles high-frequency events and peer churn without losing canonical events" do
    {:ok, adapter} = Adapter.start_link(transport: FakeTransport, event_target: self())
    %{transport_pid: transport_pid} = :sys.get_state(adapter)

    for index <- 1..50 do
      peer = "peer-#{index}"
      FakeTransport.emit(transport_pid, {:transport_up, peer, %{index: index}})
      FakeTransport.emit(transport_pid, {:frame, peer, <<index::16>>})
      FakeTransport.emit(transport_pid, {:transport_down, peer})
    end

    for index <- 1..50 do
      peer = "peer-#{index}"
      assert_receive {:transport_up, ^peer, %{index: ^index}}
      assert_receive {:frame, ^peer, <<^index::16>>}
      assert_receive {:transport_down, ^peer}
    end
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
