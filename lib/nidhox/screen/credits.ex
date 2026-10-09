defmodule Nidhox.Screen.Credits do
  @moduledoc """
  The credits over `rCredits`: the copy's own `credits.txt`, from beside its data file,
  in `fMenu`, wrapped to `@wrap` pixels and rising from the bottom of the view at
  `@speed` pixels a step until it has gone off the top.
  """

  alias Nidhox.Screen.Art

  @wrap 280
  @speed 0.35
  @bottom 200
  @centre 160

  @doc "The credits beside the data file at `path`, found whatever the case of its name; empty when the copy has none."
  @spec read(Path.t()) :: String.t()
  def read(path) do
    folder = Path.dirname(path)

    with {:ok, files} <- File.ls(folder),
         name when is_binary(name) <- Enum.find(files, &(String.downcase(&1) == "credits.txt")),
         {:ok, text} <- File.read(Path.join(folder, name)) do
      text
    else
      _missing -> ""
    end
  end

  @doc "Whether `text` has risen off the top by step `timer` of the screen."
  @spec done?(String.t(), non_neg_integer()) :: boolean()
  def done?(text, timer), do: top(timer) + Art.text_height("fMenu", text, wrap: @wrap) < 0

  @doc "The credits' GUI items at step `timer` of the screen."
  @spec items(String.t(), non_neg_integer(), {number(), number()}) :: [map()]
  def items(text, timer, window),
    do: Art.text("fMenu", text, {@centre, top(timer)}, window, halign: :center, wrap: @wrap)

  defp top(timer), do: @bottom - timer * @speed
end
