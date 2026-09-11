defmodule AshPlanningCenter.ClientTest do
  use ExUnit.Case, async: false

  alias AshPlanningCenter.Client.Error

  setup do
    client = Application.get_env(:ash_planning_center, :client)
    auth = Application.get_env(:ash_planning_center, :auth)

    on_exit(fn ->
      restore_env(:client, client)
      restore_env(:auth, auth)
    end)

    :ok
  end

  test "default transport refuses before network access when authentication is absent" do
    Application.delete_env(:ash_planning_center, :client)
    Application.delete_env(:ash_planning_center, :auth)

    assert {:error, %Error{reason: :missing_auth}} =
             AshPlanningCenter.request(:get, "/people/v2/people")
  end

  test "query context client takes precedence over the globally configured client" do
    Application.put_env(:ash_planning_center, :client, __MODULE__.FailingClient)

    assert {:ok, %AshPlanningCenter.Client.Response{status: 200}} =
             AshPlanningCenter.request(:get, "/people/v2/people",
               context: %{planning_center_client: AshPlanningCenter.TestClient}
             )

    assert_receive {:planning_center_request, :get, "/people/v2/people", _opts}
  end

  defp restore_env(key, nil), do: Application.delete_env(:ash_planning_center, key)
  defp restore_env(key, value), do: Application.put_env(:ash_planning_center, key, value)

  defmodule FailingClient do
    @behaviour AshPlanningCenter.Client

    @impl true
    def request(_method, _path, _opts), do: raise("global client should not be called")
  end
end
