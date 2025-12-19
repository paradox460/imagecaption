defmodule ImagecaptionWeb.CaptionLive do
  use ImagecaptionWeb, :live_view

  alias Imagecaption.Captioning
  alias Imagecaption.Captioning.Caption
  alias Imagecaption.Exif.Reader
  alias Imagecaption.Exif.Writer
  alias Imagecaption.LlamaCpp
  alias Imagecaption.Metadata

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="container">
        <div class="path-input-container">
          <.form for={@path_form} phx-submit="search_images" id="path-search-form">
            <.input
              type="text"
              field={@path_form[:path]}
              placeholder="/path/to/images"
            />
            <.button type="submit" phx-disable-with="Searching...">Search for Images</.button>
          </.form>
        </div>
        <.form for={@form} phx-submit="accept" class="left-panel">
          <div class="status">
            <%= if @current_index && @total_images do %>
              Processing:
              <input
                type="number"
                value={@current_index}
                min="1"
                max={@total_images}
                phx-change="jump_to_index"
                name="index"
                class="jump-to-index"
                phx-debounce="blur"
              /> / {@total_images}
              <%= if @caption_source do %>
                | Source: {format_caption_source(@caption_source)}
              <% end %>
            <% else %>
              Ready
            <% end %>
          </div>
          <div class="filename">Filename: {@form[:filename].value}</div>
          <.input type="textarea" field={@form[:description]} label="Description" />
          <.input type="textarea" field={@form[:tags_string]} label="Tags" sublabel="One per line" />
          <div class="actions">
            <.button type="submit" phx-disable-with="Accepting…" class="accept">
              Accept/Write
            </.button>
            <.button type="button" phx-click="reject" class="reject">Reject/Skip</.button>
            <.button type="button" phx-click="regen" class="regen">Regenerate</.button>
          </div>
        </.form>

        <div class="right-panel">
          <picture class="image-container" id="previewContainer">
            <%= if @caption.data do %>
              <img
                src={"data:image/jpeg;base64,#{@caption.data}"}
                alt="Image preview"
                id="previewImage"
              />
            <% else %>
              <div class="no-image">No Image Loaded</div>
            <% end %>
          </picture>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp format_caption_source(:exif), do: "EXIF"
  defp format_caption_source(:llm), do: "LLM"
  defp format_caption_source(:llm_regenerating), do: "LLM (regenerating)"
  defp format_caption_source(:error), do: "Error"
  defp format_caption_source(_), do: "Unknown"

  def mount(_params, _session, socket) do
    caption = %Caption{}
    changeset = Captioning.change_caption(caption, %{})
    form = Phoenix.Component.to_form(changeset)
    path_form = Phoenix.Component.to_form(%{"path" => ""}, as: :path)

    {:ok,
     assign(socket,
       caption: caption,
       form: form,
       path_form: path_form,
       image_files: [],
       current_index: nil,
       total_images: nil,
       status: nil,
       is_regenerating: false,
       caption_source: nil
     )}
  end

  def handle_event("search_images", %{"path" => %{"path" => path}}, socket) do
    Task.async(fn ->
      find_jpeg_images(path)
    end)

    {:noreply, assign(socket, status: "Searching for images...")}
  end

  def handle_event("accept", %{"caption" => caption_params}, socket) do
    changeset = Captioning.change_caption(socket.assigns.caption, caption_params)

    case Ecto.Changeset.apply_action(changeset, :update) do
      {:ok, caption} ->
        # Write EXIF data to the image file
        image_files = socket.assigns.image_files

        image_path =
          Enum.find(image_files, fn path -> Path.basename(path) == caption.filename end)

        socket =
          if image_path do
            case Writer.write_exif(image_path, caption.description, caption.tags) do
              :ok ->
                assign(socket,
                  caption: caption,
                  status: "Accepted and saved #{caption.filename}. Moving to next image...",
                  is_regenerating: false,
                  caption_source: nil
                )

              {:error, reason} ->
                assign(socket,
                  caption: caption,
                  status:
                    "Accepted #{caption.filename} but failed to write EXIF: #{reason}. Moving to next image...",
                  is_regenerating: false,
                  caption_source: nil
                )
            end
          else
            assign(socket,
              caption: caption,
              status: "Accepted #{caption.filename} (image not found). Moving to next image...",
              is_regenerating: false,
              caption_source: nil
            )
          end

        send(self(), :process_next_image)
        {:noreply, socket}

      {:error, changeset} ->
        form = Phoenix.Component.to_form(changeset)
        {:noreply, assign(socket, form: form, status: "Invalid caption data")}
    end
  end

  def handle_event("reject", _params, socket) do
    # Skip current image and move to next
    send(self(), :process_next_image)

    {:noreply,
     assign(socket,
       status: "Rejected #{socket.assigns.caption.filename}. Moving to next image..."
     )}
  end

  def handle_event("regen", _params, socket) do
    caption = socket.assigns.caption

    if caption.filename do
      # Re-process the current image
      image_files = socket.assigns.image_files

      # Find the current image path
      image_path = Enum.find(image_files, fn path -> Path.basename(path) == caption.filename end)

      if image_path do
        Task.async(fn ->
          # Always use LLM for regeneration
          result = LlamaCpp.describe_image(image_path)
          {:caption_result, image_path, result, :from_llm}
        end)

        {:noreply,
         assign(socket,
           status: "Regenerating caption for #{caption.filename}...",
           is_regenerating: true,
           caption_source: :llm_regenerating
         )}
      else
        {:noreply, assign(socket, status: "Could not find image to regenerate")}
      end
    else
      {:noreply, assign(socket, status: "No image to regenerate")}
    end
  end

  def handle_event("jump_to_index", %{"index" => index_str}, socket) do
    case Integer.parse(index_str) do
      {index, _} when index >= 1 and index <= socket.assigns.total_images ->
        # Set the index (subtract 1 because we store 0-based internally but display 1-based)
        socket = assign(socket, current_index: index - 1)
        send(self(), :process_next_image)
        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({ref, {:search_complete, files}}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    socket =
      assign(socket,
        image_files: files,
        total_images: length(files),
        current_index: 0,
        status: "Found #{length(files)} images. Starting captioning..."
      )

    # Start processing the first image
    if length(files) > 0 do
      send(self(), :process_next_image)
    end

    {:noreply, socket}
  end

  def handle_info({ref, {:search_error, reason}}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, assign(socket, status: "Error: #{reason}")}
  end

  def handle_info({ref, {:caption_result, image_path, result, source}}, socket)
      when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    case result do
      {:ok, %Metadata{description: description, keywords: keywords}} ->
        # Update the existing caption with the results
        %Caption{} = existing_caption = socket.assigns.caption

        caption = %{
          existing_caption
          | description: description,
            tags: keywords,
            tags_string: Enum.join(keywords, "\n")
        }

        changeset = Captioning.change_caption(caption, %{})
        form = Phoenix.Component.to_form(changeset)

        # Only auto-advance if this wasn't a regeneration
        socket =
          if socket.assigns.is_regenerating do
            assign(socket,
              caption: caption,
              form: form,
              status: "Caption regenerated for #{Path.basename(image_path)}",
              is_regenerating: false,
              caption_source: :llm
            )
          else
            status_text =
              case source do
                :from_exif -> "Caption loaded from EXIF for #{Path.basename(image_path)}"
                :from_llm -> "Caption generated for #{Path.basename(image_path)}"
                _ -> "Caption generated for #{Path.basename(image_path)}"
              end

            caption_source_atom =
              case source do
                :from_exif -> :exif
                :from_llm -> :llm
                _ -> nil
              end

            assign(socket,
              caption: caption,
              form: form,
              status: status_text,
              caption_source: caption_source_atom
            )
          end

        {:noreply, socket}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           status: "Error captioning #{Path.basename(image_path)}: #{reason}",
           is_regenerating: false,
           caption_source: :error
         )}
    end
  end

  def handle_info(:process_next_image, socket) do
    current_index = socket.assigns.current_index
    image_files = socket.assigns.image_files

    if current_index < length(image_files) do
      image_path = Enum.at(image_files, current_index)

      # Read and encode the image data before processing
      image_data =
        case File.read(image_path) do
          {:ok, binary} -> Base.encode64(binary)
          {:error, _} -> nil
        end

      # Create a temporary caption to show the image and filename
      temp_caption = %Caption{
        filename: Path.basename(image_path),
        data: image_data
      }

      temp_changeset = Captioning.change_caption(temp_caption, %{})
      temp_form = Phoenix.Component.to_form(temp_changeset)

      # Update UI with image before starting captioning
      socket =
        assign(socket,
          caption: temp_caption,
          form: temp_form,
          current_index: current_index + 1,
          status: "Processing image #{current_index + 1} of #{length(image_files)}..."
        )

      Task.async(fn ->
        # Try reading EXIF data first
        case Reader.read_exif(image_path) do
          {:ok, %Metadata{description: description, keywords: keywords}}
          when not is_nil(description) and keywords != [] ->
            # Use EXIF data if both description and keywords exist
            {:caption_result, image_path,
             {:ok, %Metadata{description: description, keywords: keywords}}, :from_exif}

          _ ->
            # Fall back to LLM
            result = LlamaCpp.describe_image(image_path)
            {:caption_result, image_path, result, :from_llm}
        end
      end)

      {:noreply, socket}
    else
      {:noreply, assign(socket, status: "All images processed")}
    end
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    {:noreply, socket}
  end

  defp find_jpeg_images(path) do
    if path =~ ~r/\.jpe?g$/i do
      {:search_complete, [path]}
    else
      try do
        case System.cmd("fd", [
               "-e",
               "jpg",
               "-e",
               "jpeg",
               "-e",
               "JPG",
               "-e",
               "JPEG",
               "-t",
               "f",
               ".",
               path
             ]) do
          {output, 0} ->
            files =
              output
              |> String.trim()
              |> String.split("\n", trim: true)
              |> Enum.sort()

            {:search_complete, files}

          {error, _} ->
            {:search_error, "Failed to search directory: #{error}"}
        end
      rescue
        e ->
          {:search_error, "Failed to run fd command: #{Exception.message(e)}"}
      end
    end
  end
end
