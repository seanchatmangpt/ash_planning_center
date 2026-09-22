defmodule Mix.Tasks.AshPlanningCenter.ZoeProbeTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias AshPlanningCenter.Client.Response

  @producer_sha String.duplicate("f", 40)

  defmodule ProbeClient do
    @behaviour AshPlanningCenter.Client

    @impl true
    def request(:get, "/registrations/v2/signups/signup-1/attendees", _opts) do
      {:ok,
       %Response{
         status: 200,
         body: %{
           "data" => [
             %{
               "id" => "att-1",
               "attributes" => %{"active" => true},
               "relationships" => %{"person" => %{"data" => %{"id" => "p-1"}}}
             }
           ],
           "meta" => %{"total_count" => 1}
         },
         headers: %{}
       }}
    end

    def request(method, path, _opts),
      do: raise("unexpected #{inspect(method)} provider call #{path}")
  end

  setup do
    previous_client = Application.get_env(:ash_planning_center, :client)
    previous_sha = System.get_env("ASH_PLANNING_CENTER_PRODUCER_SHA")

    Application.put_env(:ash_planning_center, :client, ProbeClient)
    System.put_env("ASH_PLANNING_CENTER_PRODUCER_SHA", @producer_sha)

    on_exit(fn ->
      if is_nil(previous_client) do
        Application.delete_env(:ash_planning_center, :client)
      else
        Application.put_env(:ash_planning_center, :client, previous_client)
      end

      if is_nil(previous_sha) do
        System.delete_env("ASH_PLANNING_CENTER_PRODUCER_SHA")
      else
        System.put_env("ASH_PLANNING_CENTER_PRODUCER_SHA", previous_sha)
      end
    end)

    :ok
  end

  test "probe emits a producer-bound OBSERVE receipt without secret arguments" do
    out =
      Path.join(
        System.tmp_dir!(),
        "ash-planning-center-zoe-probe-#{System.unique_integer([:positive])}.json"
      )

    Mix.Task.reenable("ash_planning_center.zoe_probe")

    output =
      capture_io(fn ->
        Mix.Tasks.AshPlanningCenter.ZoeProbe.run([
          "--event-ref",
          "event:youth-001",
          "--event-name",
          "Youth Night",
          "--starts-at",
          "2026-09-23T19:00:00-07:00",
          "--signup-id",
          "signup-1",
          "--out",
          out
        ])
      end)

    assert output =~ "wrote #{out}"

    payload = out |> File.read!() |> Jason.decode!()

    assert payload["contract"]["contract_version"] == "zoe-event-ops/v1"
    assert payload["contract"]["authority_boundary"] == "OBSERVE"
    assert payload["contract"]["do_authority"] == false
    assert payload["contract"]["standing"] == "PARTIAL_ALIVE"
    assert payload["contract"]["counts"] == %{
             "roster" => 0,
             "registrations" => 1,
             "check_ins" => 0
           }

    assert payload["receipt"]["kind"] == "PLANNING_CENTER_OBSERVATION"
    assert payload["receipt"]["producer_sha"] == @producer_sha
    assert payload["receipt"]["contract_version"] == "zoe-event-ops/v1"
    assert payload["receipt"]["authority_boundary"] == "OBSERVE"
    assert payload["receipt"]["do_authority"] == false

    refute inspect(payload) =~ "authorization"
    refute inspect(payload) =~ "secret"
    refute inspect(payload) =~ "token"

    File.rm(out)
  end

  test "probe refuses malformed explicit producer identity" do
    System.put_env("ASH_PLANNING_CENTER_PRODUCER_SHA", "not-a-sha")
    Mix.Task.reenable("ash_planning_center.zoe_probe")

    assert_raise Mix.Error, ~r/must be an exact 40-hex SHA/, fn ->
      capture_io(fn ->
        Mix.Tasks.AshPlanningCenter.ZoeProbe.run([
          "--event-ref",
          "event:youth-001",
          "--event-name",
          "Youth Night",
          "--starts-at",
          "2026-09-23T19:00:00-07:00",
          "--signup-id",
          "signup-1"
        ])
      end)
    end
  end

  test "probe has no CLI switches for credentials or mutation" do
    Mix.Task.reenable("ash_planning_center.zoe_probe")

    assert_raise Mix.Error, ~r/unsupported arguments/, fn ->
      capture_io(fn ->
        Mix.Tasks.AshPlanningCenter.ZoeProbe.run([
          "--event-ref",
          "event:youth-001",
          "--event-name",
          "Youth Night",
          "--starts-at",
          "2026-09-23T19:00:00-07:00",
          "--signup-id",
          "signup-1",
          "--token",
          "must-not-be-accepted"
        ])
      end)
    end
  end
end
