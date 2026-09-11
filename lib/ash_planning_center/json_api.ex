defmodule AshPlanningCenter.JSONAPI do
  @moduledoc """
  Minimal JSON:API projection into Ash resource structs.

  Known Ash attributes are projected by name. The complete remote attributes,
  relationships, links, metadata, and JSON:API type are retained so that an
  upstream field can be observed without first changing this library's schema.
  """

  alias AshPlanningCenter.Client.Error

  @type document_info :: %{meta: map(), links: map()}

  @spec decode_many(map(), module()) ::
          {:ok, [struct()], document_info()} | {:error, Error.t()}
  def decode_many(%{"data" => data} = document, resource) when is_list(data) do
    {:ok, Enum.map(data, &to_resource(&1, resource)), document_info(document)}
  end

  def decode_many(_document, _resource) do
    {:error,
     %Error{
       message: "Planning Center response is not a JSON:API collection document",
       reason: :invalid_json_api_document
     }}
  end

  @spec decode_one(map(), module()) ::
          {:ok, struct(), document_info()} | {:error, Error.t()}
  def decode_one(%{"data" => data} = document, resource) when is_map(data) do
    {:ok, to_resource(data, resource), document_info(document)}
  end

  def decode_one(_document, _resource) do
    {:error,
     %Error{
       message: "Planning Center response is not a JSON:API resource document",
       reason: :invalid_json_api_document
     }}
  end

  @spec to_resource(map(), module()) :: struct()
  def to_resource(data, resource) do
    remote_attributes = Map.get(data, "attributes", %{})
    known_attributes = known_attributes(resource)

    projected =
      Enum.reduce(remote_attributes, %{}, fn {key, value}, acc ->
        case Map.fetch(known_attributes, key) do
          {:ok, attribute_name} -> Map.put(acc, attribute_name, value)
          :error -> acc
        end
      end)

    projected =
      projected
      |> Map.put(:id, Map.get(data, "id"))
      |> Map.put(:remote_type, Map.get(data, "type"))
      |> Map.put(:remote_attributes, remote_attributes)
      |> Map.put(:remote_relationships, Map.get(data, "relationships", %{}))
      |> Map.put(:links, Map.get(data, "links", %{}))
      |> Map.put(:meta, Map.get(data, "meta", %{}))

    struct(resource, projected)
  end

  defp known_attributes(resource) do
    resource
    |> Ash.Resource.Info.attributes()
    |> Map.new(fn attribute -> {Atom.to_string(attribute.name), attribute.name} end)
  end

  defp document_info(document) do
    %{
      meta: Map.get(document, "meta", %{}),
      links: Map.get(document, "links", %{})
    }
  end
end
