defmodule Imagecaption.Captioning.Caption do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:filename, :string)
    # Base64 encoded image data, for previewing
    field(:data, :string)
    field(:tags, {:array, :string}, default: [])
    field(:description, :string)
    # Virtual field for form display - tags as newline-delimited string
    field(:tags_string, :string, virtual: true)
  end

  @doc false
  def changeset(caption, attrs) do
    # Convert tags array to newline-delimited string for display
    attrs_with_tags_string =
      if caption.tags && !Map.get(attrs, "tags_string") do
        Map.put(attrs, "tags_string", Enum.join(caption.tags, "\n"))
      else
        attrs
      end

    caption
    |> cast(attrs_with_tags_string, [:filename, :tags_string, :description])
    |> convert_tags_string_to_array()
  end

  defp convert_tags_string_to_array(changeset) do
    case get_change(changeset, :tags_string) do
      nil ->
        changeset

      tags_string when is_binary(tags_string) ->
        tags =
          tags_string
          |> String.split("\n", trim: true)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        put_change(changeset, :tags, tags)

      _ ->
        changeset
    end
  end
end
