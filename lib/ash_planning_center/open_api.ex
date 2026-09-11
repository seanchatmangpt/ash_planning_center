defmodule AshPlanningCenter.OpenAPI do
  @moduledoc """
  Deterministic uplift from the pinned Planning Center People OpenAPI document
  into the RDF input consumed by `ggen_igniter`.

  The current projection ceiling is deliberately narrow: `person_attributes`.
  The source OpenAPI document remains authoritative; generated Ash code is only
  a projection of that admitted schema.
  """

  @source_url "https://api.planningcenteronline.com/people/v2/open_api/2026-06-04"
  @openapi_version "3.1.1"
  @api_version "2026-06-04"
  @server_url "https://api.planningcenteronline.com/people/v2"
  @schema_key "person_attributes"
  @ontology_base "https://seanchatmangpt.github.io/ash_planning_center/openapi/"

  def source_url, do: @source_url
  def api_version, do: @api_version
  def schema_key, do: @schema_key

  def fetch! do
    @source_url
    |> Req.get!(headers: [{"accept", "application/json"}])
    |> Map.fetch!(:body)
    |> normalize_document!()
    |> validate!()
  end

  def load_file!(path) do
    path
    |> File.read!()
    |> Jason.decode!()
    |> validate!()
  end

  def validate!(document) when is_map(document) do
    assert_equal!(Map.get(document, "openapi"), @openapi_version, "OpenAPI version")
    assert_equal!(get_in(document, ["info", "version"]), @api_version, "People API version")

    server_urls =
      document
      |> Map.get("servers", [])
      |> Enum.map(&Map.get(&1, "url"))

    unless @server_url in server_urls do
      raise ArgumentError,
            "Planning Center OpenAPI server mismatch: expected #{@server_url}, got #{inspect(server_urls)}"
    end

    case get_in(document, ["components", "schemas", @schema_key]) do
      %{"type" => "object", "properties" => properties} when is_map(properties) -> document
      other -> raise ArgumentError, "missing #{@schema_key} object schema: #{inspect(other)}"
    end
  end

  def validate!(other) do
    raise ArgumentError, "Planning Center OpenAPI must decode to an object, got: #{inspect(other)}"
  end

  def to_turtle(document) do
    document = validate!(document)
    schema = get_in(document, ["components", "schemas", @schema_key])
    resource_name = Map.fetch!(schema, "title")
    resource_iri = @ontology_base <> "schema/" <> @schema_key
    module_name = "AshPlanningCenter.People." <> resource_name
    file_stem = Macro.underscore(resource_name)

    document_ttl = """
    @prefix pco: <#{@ontology_base}ontology#> .
    @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

    pco:document a pco:OpenApiDocument ;
      pco:sourceUrl #{literal(@source_url)} ;
      pco:openapiVersion #{literal(@openapi_version)} ;
      pco:apiVersion #{literal(@api_version)} ;
      pco:serverUrl #{literal(@server_url)} .

    <#{resource_iri}> a pco:Resource ;
      pco:schemaKey #{literal(@schema_key)} ;
      pco:name #{literal(resource_name)} ;
      pco:moduleName #{literal(module_name)} ;
      pco:fileStem #{literal(file_stem)} .
    """

    attributes_ttl =
      schema
      |> Map.fetch!("properties")
      |> Enum.sort_by(fn {name, _schema} -> name end)
      |> Enum.map_join("\n", fn {name, attribute_schema} ->
        attribute_iri = resource_iri <> "/attribute/" <> URI.encode(name)
        json_type = Map.get(attribute_schema, "type", "string")
        format = Map.get(attribute_schema, "format", "")

        """
        <#{attribute_iri}> a pco:Attribute ;
          pco:resource <#{resource_iri}> ;
          pco:name #{literal(name)} ;
          pco:jsonType #{literal(json_type)} ;
          pco:format #{literal(format)} ;
          pco:ashType #{literal(ash_type(json_type))} .
        """
        |> String.trim_trailing()
      end)

    String.trim_trailing(document_ttl) <> "\n\n" <> attributes_ttl <> "\n"
  end

  def write_turtle!(document, path) do
    turtle = to_turtle(document)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, turtle)

    digest =
      :sha256
      |> :crypto.hash(turtle)
      |> Base.encode16(case: :lower)

    %{path: path, sha256: digest, bytes: byte_size(turtle)}
  end

  defp normalize_document!(document) when is_map(document), do: document
  defp normalize_document!(document) when is_binary(document), do: Jason.decode!(document)

  defp normalize_document!(other) do
    raise ArgumentError, "unexpected Planning Center OpenAPI response body: #{inspect(other)}"
  end

  defp assert_equal!(actual, expected, label) do
    unless actual == expected do
      raise ArgumentError, "#{label} mismatch: expected #{inspect(expected)}, got #{inspect(actual)}"
    end
  end

  defp ash_type("boolean"), do: ":boolean"
  defp ash_type("integer"), do: ":integer"
  defp ash_type("number"), do: ":float"
  defp ash_type("object"), do: ":map"
  defp ash_type("array"), do: "{:array, :map}"
  defp ash_type(_), do: ":string"

  defp literal(value) do
    escaped =
      value
      |> to_string()
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
      |> String.replace("\r", "\\r")
      |> String.replace("\n", "\\n")
      |> String.replace("\t", "\\t")

    "\"#{escaped}\""
  end
end
