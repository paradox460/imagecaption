defmodule Imagecaption.Captioning do
  alias Imagecaption.Captioning.Caption

  def change_caption(%Caption{} = caption, attrs \\ %{}) do
    Caption.changeset(caption, attrs)
  end
end
