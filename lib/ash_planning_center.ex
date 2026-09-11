defmodule AshPlanningCenter do
  @moduledoc """
  Ash-native integration surface for Planning Center.

  The public domain is `AshPlanningCenter.Domain`. Low-level callers can use
  `request/3`, although product modules should normally expose remote behavior
  through Ash actions instead.
  """

  @type method :: :get | :post | :put | :patch | :delete

  @spec request(method(), String.t(), keyword()) ::
          {:ok, AshPlanningCenter.Client.Response.t()}
          | {:error, AshPlanningCenter.Client.Error.t()}
  def request(method, path, opts \\ []) do
    AshPlanningCenter.Client.request(method, path, opts)
  end
end
