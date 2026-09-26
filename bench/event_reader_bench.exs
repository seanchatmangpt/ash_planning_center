# Deterministic timing benchmark for AshPlanningCenter.EventReader.
#
#   mix run bench/event_reader_bench.exs [out.json]
#
# Uses a real in-process implementation of the AshPlanningCenter.Client
# behaviour that serves deterministic full pages (100 records each) for all
# three admitted products, so the measurement covers pagination, page
# admission (id checks + duplicate detection), PII-dropping normalization,
# ordering and the observation digest. No network is involved: a live Planning
# Center tenant is a paid external system holding youth PII.

defmodule EventReaderBench.SyntheticClient do
  @behaviour AshPlanningCenter.Client
  alias AshPlanningCenter.Client.Response

  @impl true
  def request(:get, path, opts) do
    params = Keyword.fetch!(opts, :params)
    offset = Map.fetch!(params, "offset")
    total = :persistent_term.get({__MODULE__, :total})
    count = max(min(100, total - offset), 0)

    data =
      for i <- 1..count//1 do
        n = offset + i

        %{
          "id" => "r-#{n}",
          "attributes" => %{
            "active" => true,
            "status" => "C",
            "team_position_name" => "Volunteer",
            "confirmed_at" => "2026-09-23T19:03:00-07:00",
            "name" => "dropped PII #{n}"
          },
          "relationships" => %{
            "person" => %{"data" => %{"id" => "p-#{rem(n, 997)}-#{path_tag(path)}"}}
          }
        }
      end

    {:ok,
     %Response{
       status: 200,
       body: %{"data" => data, "meta" => %{"total_count" => total}},
       headers: %{}
     }}
  end

  defp path_tag("/services" <> _), do: "s"
  defp path_tag("/registrations" <> _), do: "r"
  defp path_tag(_), do: "c"
end

defmodule EventReaderBench do
  alias AshPlanningCenter.EventReader

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

  def run_case(records_per_source, iterations) do
    :persistent_term.put({EventReaderBench.SyntheticClient, :total}, records_per_source)
    pages = div(records_per_source + 99, 100)
    opts = [client: EventReaderBench.SyntheticClient, max_pages: max(pages, 1)]

    {:ok, warm} = EventReader.read(@attrs, opts)

    times =
      for _ <- 1..iterations do
        {us, {:ok, _}} = :timer.tc(fn -> EventReader.read(@attrs, opts) end)
        us
      end
      |> Enum.sort()

    %{
      records_per_source: records_per_source,
      total_records: records_per_source * 3,
      pages: warm.receipt.pages,
      iterations: iterations,
      median_us: Enum.at(times, div(iterations, 2)),
      min_us: hd(times),
      max_us: List.last(times),
      observation_digest: warm.receipt.observation_digest
    }
  end

  def main(args) do
    cases = [{100, 50}, {1_000, 30}, {10_000, 10}]
    results = Enum.map(cases, fn {n, it} -> run_case(n, it) end)
    [small, _mid, large] = results

    report = %{
      schema: "ash_planning_center/event-reader-bench/1",
      subject: "AshPlanningCenter.EventReader",
      module_md5: AshPlanningCenter.EventReader.module_info(:md5) |> Base.encode16(case: :lower),
      otp_release: System.otp_release(),
      elixir: System.version(),
      results: results,
      scaling_ratio_100x: Float.round(large.median_us / max(small.median_us, 1), 2),
      authority: "NONE"
    }

    json = Jason.encode!(report, pretty: true)
    IO.puts(json)

    case args do
      [out] -> File.write!(out, json <> "\n")
      _ -> :ok
    end
  end
end

EventReaderBench.main(System.argv())
