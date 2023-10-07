defmodule Ockam.Services.StaticForwarding do
  @moduledoc """
  Static forwarding service

  Subscribes workers (by return route) to a string forwarding alias

  Forwarding alias is parsed from the payload as a BARE `string` type

  New subscriptions update the forwarding route in the same forwarding alias

  Forwarder address is created from prefix and alias as <prefix>_<alias>
  e.g. if prefix is `forward_to_` and alias is `my_alias`, forwarder address will be: `forward_to_my_alias`

  Messages sent to the forwarder address will be forwarded to the forwarding route

  Options:

  `prefix` - address prefix
  """
  use Ockam.Worker

  alias __MODULE__.Forwarder
  alias Ockam.Message

  require Logger

  @spec list_running_relays() :: [{Ockam.Address.t(), map()}]
  def list_running_relays() do
    Ockam.Node.Registry.select_by_attribute(:service, :relay)
  end

  @impl true
  def setup(options, state) do
    prefix = Keyword.get(options, :prefix, state.address)

    forwarder_options = Keyword.get(options, :forwarder_options, [])

    {:ok,
     Map.merge(state, %{
       prefix: prefix,
       forwarder_options: forwarder_options
     })}
  end

  @impl true
  def handle_message(message, state) do
    payload = Message.payload(message)

    case :bare.decode(payload, :string) do
      {:ok, alias_str, ""} ->
        return_route = Message.return_route(message)
        target_identifier = Message.local_metadata_value(message, :identity_id)
        subscribe(alias_str, return_route, target_identifier, state)

      err ->
        Logger.error("Invalid message format: #{inspect(payload)}, reason #{inspect(err)}")
    end
  end

  def subscribe(alias_str, route, target_identifier, state) do
    with {:ok, worker, attrs_to_update} <-
           ensure_alias_worker(alias_str, target_identifier, state) do
      ## NOTE: Non-ockam message routing here
      :ok = Forwarder.update_route(worker, route, updated_attrs: attrs_to_update)
      {:ok, state}
    end
  end

  def ensure_alias_worker(alias_str, target_identifier, state) do
    forwarder_address = forwarder_address(alias_str, state)
    forwarder_options = Map.fetch!(state, :forwarder_options)

    {:ok, ts} = DateTime.now("Etc/UTC")

    case Ockam.Node.whereis(forwarder_address) do
      nil ->
        regitry_metadata = %{
          service: :relay,
          target_identifier: target_identifier,
          created_at: ts,
          updated_at: ts
        }

        {:ok, worker} =
          Forwarder.create(
            Keyword.merge(forwarder_options,
              alias: alias_str,
              address: forwarder_address,
              registry_metadata_attributes: regitry_metadata
            )
          )

        {:ok, worker, nil}

      _pid ->
        {:ok, forwarder_address, %{updated_at: ts, target_identifier: target_identifier}}
    end
  end

  def forwarder_address(alias_str, state) do
    Map.get(state, :prefix, "") <> "_" <> alias_str
  end
end

defmodule Ockam.Services.StaticForwarding.Forwarder do
  @moduledoc """
  Forwards all messages to the subscribed route
  """
  use Ockam.Worker

  alias Ockam.Message

  def update_route(worker, route, options \\ []) do
    ## TODO: reply to the subscriber?
    Ockam.Worker.call(worker, {:update_route, route, options})
  end

  @impl true
  def setup(options, state) do
    alias_str = Keyword.get(options, :alias)
    {:ok, Map.merge(state, %{alias: alias_str, route: []})}
  end

  @impl true
  def handle_call({:update_route, route, options}, _from, %{alias: alias_str} = state) do
    state = Map.put(state, :route, route)

    # Update metadata attributes
    case Keyword.get(options, :updated_attrs) do
      nil ->
        :ok

      updated_attrs ->
        :ok =
          Ockam.Node.update_address_metadata(
            state.address,
            fn some ->
              %{attributes: attrs} = some
              %{some | attributes: Map.merge(attrs, updated_attrs)}
            end
          )
    end

    case Keyword.get(options, :notify, true) do
      true ->
        Ockam.Router.route(%{
          onward_route: route,
          return_route: [state.address],
          payload: :bare.encode("#{alias_str}", :string)
        })

      false ->
        :ok
    end

    {:reply, :ok, state}
  end

  @impl true
  def handle_message(message, state) do
    [_me | onward_route] = Message.onward_route(message)

    route = Map.get(state, :route, [])

    Ockam.Router.route(Message.set_onward_route(message, route ++ onward_route))

    {:ok, state}
  end
end
