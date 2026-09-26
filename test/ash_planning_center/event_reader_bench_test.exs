defmodule AshPlanningCenter.EventReaderBenchTest do
  @moduledoc """
  Regression bounds for the bounded reader's cost.

  Bounds are deliberately loose absolute ceilings (well above the recorded
  medians in bench/receipts/event_reader.json) plus a scaling-shape bound: a
  100x larger observation must cost far less than 100^2/10 = 1000x, which
  falsifies an accidental quadratic accumulation in pagination or dedupe.
  The provider is a real in-process `AshPlanningCenter.Client` implementation
  serving deterministic pages; no network is involved.
  """
  use ExUnit.Case, async: false

  alias AshPlanningCenter.Client.Response
  alias AshPlanningCenter.EventReader

  defmodule PagedClient do
    @behaviour AshPlanningCenter.Client

    @impl true
    def request(:get, _path, opts) do
      offset = opts |> Keyword.fetch!(:params) |> Map.fetch!("offset")
      total = :persistent_term.get({__MODULE__, :total})
      count = max(min(100, total - offset), 0)

      data =
        for i <- 1..count//1 do
          n = offset + i

          %{
            "id" => "r-#{n}",
            "attributes" => %{"active" => true, "name" => "dropped #{n}"},
            "relationships" => %{"person" => %{"data" => %{"id" => "p-#{n}"}}}
          }
        end

      {:ok,
       %Response{
         status: 200,
         body: %{"data" => data, "meta" => %{"total_count" => total}},
         headers: %{}
       }}
    end
  end

  @attrs %{
    event_ref: "event:bench",
    event_name: "Bench",
    starts_at: "2026-09-23T19:00:00-07:00",
    sources: %{
      services: %{service_type_id: "st-1", plan_id: "plan-1"},
      registrations: %{signup_id: "signup-1"},
      check_ins: %{event_id: "ev-1"}
    }
  }

  defp median_us(records, iterations) do
    :persistent_term.put({PagedClient, :total}, records)
    opts = [client: PagedClient, max_pages: max(div(records + 99, 100), 1)]
    {:ok, result} = EventReader.read(@attrs, opts)
    assert result.receipt.records.registrations == records

    times =
      for _ <- 1..iterations do
        {us, {:ok, _}} = :timer.tc(fn -> EventReader.read(@attrs, opts) end)
        us
      end

    times |> Enum.sort() |> Enum.at(div(iterations, 2))
  end

  test "full 100-page read of 3 x 10_000 records stays inside the regression ceiling" do
    small = median_us(100, 21)
    large = median_us(10_000, 5)

    # Absolute ceiling: 30_000 records through admission + normalization + digest.
    assert large < 3_000_000, "median #{large}us exceeded 3s ceiling"

    # Shape bound: linear cost gives ~100x; quadratic would give ~1000x+.
    assert large / max(small, 1) < 400,
           "scaling ratio #{Float.round(large / max(small, 1), 1)} suggests superlinear cost"
  end
end
