defmodule AshPlanningCenter do
  @moduledoc """
  Ash-native integration surface for Planning Center.

  The public domain is `AshPlanningCenter.Domain`. The low-level public request
  boundary is observation-only: only GET is admitted. Mutating Planning Center
  operations must be introduced as explicit Ash actions with their own
  authority, consequence, receipt, and replay contract.
  """

  @type method :: :get | :post | :put | :patch | :delete

  @spec request(method(), String.t(), keyword()) ::
          {:ok, AshPlanningCenter.Client.Response.t()}
          | {:error, AshPlanningCenter.Client.Error.t()}
  def request(:get, path, opts \\ []) do
    AshPlanningCenter.Client.request(:get, path, opts)
  end

  def request(method, _path, _opts) do
    {:error,
     %AshPlanningCenter.Client.Error{
       message: "Planning Center mutation is not admitted by the public request boundary",
       reason: {:unsupported_operation, method}
     }}
  end
end
