defmodule Imagecaption.Exif.Writer do
  @moduledoc """
  Writes EXIF metadata to image files using the exiftool command-line tool.
  """

  @doc """
  Writes EXIF description and keywords to an image file.

  ## Parameters

    * `image_path` - Path to the image file
    * `description` - Description text to write (can be nil to skip)
    * `keywords` - List of keyword strings to write (can be empty list to skip)

  ## Examples

      iex> Imagecaption.ExifWriter.write_exif("/path/to/image.jpg", "A beautiful sunset", ["sunset", "nature"])
      :ok

      iex> Imagecaption.ExifWriter.write_exif("/path/to/image.jpg", "Description only", [])
      :ok

  """
  @spec write_exif(String.t(), String.t() | nil, [String.t()]) :: :ok | {:error, String.t()}
  def write_exif(image_path, description, keywords \\ []) do
    args = build_exiftool_args(image_path, description, keywords)

    if length(args) > 1 do
      case System.cmd("exiftool", args) do
        {_output, 0} ->
          :ok

        {error, _exit_code} ->
          {:error, "Failed to write EXIF data: #{error}"}
      end
    else
      {:error, "No data to write"}
    end
  rescue
    e ->
      {:error, "Failed to run exiftool command: #{Exception.message(e)}"}
  end

  defp build_exiftool_args(image_path, description, keywords) do
    args = ["-overwrite_original"]

    args =
      if description && String.trim(description) != "" do
        ["-Description=#{description}" | args]
      else
        args
      end

    args =
      keywords
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn kw -> "-Keywords=#{kw}" end)
      |> then(&(&1 ++ args))

    # Add the image path as the last argument, as exiftool prefers to have it at the end
    args ++ [image_path]
  end
end
