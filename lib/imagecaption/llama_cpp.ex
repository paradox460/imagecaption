defmodule Imagecaption.LlamaCpp do
  @moduledoc """
  Client for interacting with a local llama.cpp server via OpenAI-compatible API.
  """

  alias Imagecaption.Metadata

  @doc """
  Generates both description and tags for an image using the llama.cpp server.

  ## Parameters

    * `image_path` - Path to the image file
    * `opts` - Optional keyword list of options:
      * `:base_url` - Base URL of the llama.cpp server (default: "http://localhost:8088")
      * `:model` - Model name to use (default: "gpt-4-vision-preview")
      * `:max_tokens` - Maximum tokens in response (default: 300)
      * `:temperature` - Temperature for generation (default: 0.7)

  ## Examples

      iex> Imagecaption.LlamaCpp.describe_image("/path/to/image.jpg")
      {:ok, %Metadata{description: "...", keywords: [...]}}

      iex> Imagecaption.LlamaCpp.describe_image("/path/to/image.jpg", base_url: "http://localhost:9000")
      {:ok, %Metadata{description: "...", keywords: [...]}}

  """
  @spec describe_image(String.t(), Keyword.t()) :: {:ok, Metadata.t()}
  def describe_image(image_path, opts \\ []) do
    with {:ok, image_data} <- read_and_encode_image(image_path),
         {:ok, description} <- generate_description(image_data, opts),
         {:ok, tags} <- generate_tags(image_data, opts) do
      {:ok, %Metadata{description: description, keywords: tags}}
    end
  end

  defp read_and_encode_image(image_path) do
    case File.read(image_path) do
      {:ok, binary} ->
        {:ok, Base.encode64(binary)}

      {:error, reason} ->
        {:error, "Failed to read image file: #{inspect(reason)}"}
    end
  end

  defp generate_description(base64_image, opts) do
    case send_request(base64_image, description_prompt(), opts) do
      {:ok, response} ->
        extract_text_content(response)

      error ->
        error
    end
  end

  defp generate_tags(base64_image, opts) do
    case send_request(base64_image, tags_prompt(), opts) do
      {:ok, response} ->
        case extract_text_content(response) do
          {:ok, tags_string} ->
            tags =
              tags_string
              |> String.split(",")
              |> Enum.map(&String.trim/1)
              |> Enum.reject(&(&1 == ""))

            {:ok, tags}

          error ->
            error
        end

      error ->
        error
    end
  end

  defp send_request(base64_image, prompt, opts) do
    base_url = Keyword.get(opts, :base_url, base_url())
    model = Keyword.get(opts, :model, model())
    max_tokens = Keyword.get(opts, :max_tokens, max_tokens())
    temperature = Keyword.get(opts, :temperature, temperature())

    url = "#{base_url}/v1/chat/completions"

    request_body = %{
      model: model,
      messages: [
        %{
          role: "user",
          content: [
            %{
              type: "text",
              text: prompt
            },
            %{
              type: "image_url",
              image_url: %{
                url: "data:image/jpeg;base64,#{base64_image}"
              }
            }
          ]
        }
      ],
      max_tokens: max_tokens,
      temperature: temperature
    }

    case Req.post(url, json: request_body) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, "Request failed with status #{status}: #{inspect(body)}"}

      {:error, exception} ->
        {:error, "Request failed: #{Exception.message(exception)}"}
    end
  end

  defp extract_text_content(response) do
    case response do
      %{"choices" => [%{"message" => %{"content" => content}} | _]} when is_binary(content) ->
        {:ok, String.trim(content)}

      %{"error" => error} ->
        {:error, "API error: #{inspect(error)}"}

      _ ->
        {:error, "Unexpected response format: #{inspect(response)}"}
    end
  end

  defp base_url do
    Application.fetch_env!(:imagecaption, :llm)[:base_url]
  end

  defp model do
    Application.fetch_env!(:imagecaption, :llm)[:model]
  end

  defp max_tokens do
    Application.fetch_env!(:imagecaption, :llm)[:max_tokens]
  end

  defp temperature do
    Application.fetch_env!(:imagecaption, :llm)[:temperature]
  end

  defp description_prompt do
    Application.fetch_env!(:imagecaption, :llm)[:description_prompt]
  end

  defp tags_prompt do
    Application.fetch_env!(:imagecaption, :llm)[:tags_prompt]
  end
end
