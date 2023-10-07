defmodule Test.Services.StaticForwardingTest do
  use ExUnit.Case

  # Fail after 200ms of retrying with time between attempts 10ms
  use AssertEventually, timeout: 200, interval: 10

  alias Ockam.Services.StaticForwarding, as: StaticForwardingService

  alias Ockam.Message
  alias Ockam.Node
  alias Ockam.Router

  test "static forwarding" do
    {:ok, service_address} = StaticForwardingService.create(prefix: "forward_to")

    {:ok, test_address} = Node.register_random_address()

    alias_str = "test_static_forwarding_alias"

    encoded_alias_str = :bare.encode(alias_str, :string)

    forwarder_address = "forward_to_" <> alias_str

    on_exit(fn ->
      Node.stop(service_address)
      Node.stop(forwarder_address)
      Node.unregister_address(test_address)
    end)

    register_message = %Message{
      onward_route: [service_address],
      payload: encoded_alias_str,
      return_route: [test_address]
    }

    Router.route(register_message)

    assert_receive(
      %Message{
        payload: ^encoded_alias_str,
        onward_route: [^test_address],
        return_route: [^forwarder_address]
      },
      5_000
    )

    forwarded_message = %Message{
      onward_route: [forwarder_address, "smth"],
      payload: "hello",
      return_route: [test_address]
    }

    Router.route(forwarded_message)

    assert_receive(%Message{payload: "hello", onward_route: [^test_address, "smth"]}, 5_000)

    [{forwarder_address, %{service: :relay, target_identifier: nil, created_at: _}}] =
      StaticForwardingService.list_running_relays()

    Ockam.Node.stop(forwarder_address)
    assert_eventually([] = StaticForwardingService.list_running_relays())
  end

  test "forwarding route override" do
    {:ok, service_address} = StaticForwardingService.create(prefix: "forward_to")

    {:ok, test_address} = Node.register_random_address()

    alias_str = "test_route_override_alias"

    encoded_alias_str = :bare.encode(alias_str, :string)

    forwarder_address = "forward_to_" <> alias_str

    on_exit(fn ->
      Node.stop(service_address)
      Node.stop(forwarder_address)
      Node.unregister_address(test_address)
    end)

    register_message = %Message{
      onward_route: [service_address],
      payload: encoded_alias_str,
      return_route: [test_address]
    }

    Router.route(register_message)

    assert_receive(
      %Message{
        payload: ^encoded_alias_str,
        onward_route: [^test_address],
        return_route: [^forwarder_address]
      },
      5_000
    )

    [{forwarder_address, %{service: :relay, created_at: t1, updated_at: t2}}] =
      StaticForwardingService.list_running_relays()

    assert t1 == t2

    {:ok, test_address2} = Node.register_random_address()

    register_message2 = %Message{
      onward_route: [service_address],
      payload: encoded_alias_str,
      return_route: [test_address2]
    }

    Router.route(register_message2)

    assert_receive(
      %Message{
        payload: ^encoded_alias_str,
        onward_route: [^test_address2],
        return_route: [^forwarder_address]
      },
      5_000
    )

    assert_eventually(
      (
        [{forwarder_address, %{service: :relay, created_at: ^t1, updated_at: t3}}] =
          StaticForwardingService.list_running_relays()

        :lt == DateTime.compare(t1, t3)
      )
    )

    forwarded_message = %Message{
      onward_route: [forwarder_address, "smth"],
      payload: "hello",
      return_route: [test_address]
    }

    Router.route(forwarded_message)

    assert_receive(%Message{payload: "hello", onward_route: [^test_address2, "smth"]}, 5_000)

    refute_receive(%Message{payload: "hello", onward_route: [^test_address, "smth"]}, 100)
  end
end
