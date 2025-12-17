defmodule Imagecaption.Exif.Reader do
  @moduledoc """
  Reads EXIF metadata from image files using the exiftool command-line tool.
  """

  alias Imagecaption.Metadata

  @doc """
  Reads the EXIF description and keywords from an image file.

  ## Examples

      iex> Imagecaption.ExifReader.read_exif("/path/to/image.jpg")
      {:ok, %Metadata{description: "A beautiful sunset", keywords: ["sunset", "nature", "sky"]}}

      iex> Imagecaption.ExifReader.read_exif("/path/to/image_without_exif.jpg")
      {:ok, %Metadata{description: nil, keywords: []}}

  """
  @spec read_exif(String.t()) :: {:ok, Metadata.t()} | {:error, String.t()}
  def read_exif(image_path) do
    case System.cmd("exiftool", [
           "-Description",
           "-Keywords",
           "-json",
           image_path
         ]) do
      {output, 0} ->
        parse_exiftool_output(output)

      {error, _exit_code} ->
        {:error, "Failed to read EXIF data: #{error}"}
    end
  rescue
    e ->
      {:error, "Failed to run exiftool command: #{Exception.message(e)}"}
  end

  defp parse_exiftool_output(json_string) do
    case Jason.decode(json_string) do
      {:ok, [data | _]} when is_map(data) ->
        description = Map.get(data, "Description")
        keywords = parse_keywords(Map.get(data, "Keywords"))

        {:ok, %Metadata{description: description, keywords: keywords}}

      {:ok, _} ->
        {:ok, %{description: nil, keywords: []}}

      {:error, _} ->
        {:error, "Failed to parse exiftool JSON output"}
    end
  end

  defp parse_keywords(nil), do: []

  defp parse_keywords(keywords) when is_binary(keywords) do
    keywords
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_keywords(keywords) when is_list(keywords) do
    keywords
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_keywords(_), do: []
end
