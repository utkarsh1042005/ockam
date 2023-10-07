defmodule Ockam.Services.API.StaticForwarding do
  @moduledoc """
  API for static forwarding service

  See `Ockam.Services.StaticForwarding`

  Methods:
  :post, path: "", body: alias - register a forwarding alias
  """
  use Ockam.Services.API

  alias Ockam.API.Request
  alias Ockam.Services.API
  alias Ockam.Services.StaticForwarding, as: Base

  @impl true
  def setup(options, state) do
    Base.setup(options, state)
  end

  @impl true
  def handle_request(
        %Request{method: :post, path: "", from_route: from_route, body: alias_str} = req,
        state
      )
      when is_binary(alias_str) and is_list(from_route) do
    case subscribe(alias_str, from_route, Request.caller_identity_id(req), state) do
      {:ok, worker} ->
        {:reply, :ok, worker, state}

      {:error, reason} ->
        {:error, reason}

      other ->
        {:error, {:unexpected_return, other}}
    end
  end

  def handle_request(%Request{method: :post}, _state) do
    {:error, :bad_request}
  end

  def handle_request(%Request{}, _state) do
    {:error, :method_not_allowed}
  end

  def subscribe(alias_str, route, target_identifier, state) do
    with {:ok, worker, attrs_to_update} <-
           Base.ensure_alias_worker(alias_str, target_identifier, state),
         :ok <-
           Base.Forwarder.update_route(worker, route,
             notify: false,
             updated_attrs: attrs_to_update
           ) do
      {:ok, worker}
    end
  end
end
