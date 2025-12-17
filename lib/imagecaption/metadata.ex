defmodule Imagecaption.Metadata do
  @moduledoc """
  A struct representing image metadata with regards to descriptions and tags
  """

  defstruct description: nil,
            keywords: []

  @type t :: %__MODULE__{
          description: String.t() | nil,
          keywords: [String.t()]
        }
end
