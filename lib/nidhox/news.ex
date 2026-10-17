defmodule Nidhox.News do
  @moduledoc """
  The game's news: the articles its `newsItems` builds, read from the player's copy of
  the game's executable (`Nidhox.ObjectDepths` finds it beside the data file), and
  which of them a player has opened.

      {:ok, items} = Nidhox.News.read("path/to/Nidhogg.exe")
      Nidhox.News.unread(items, "online_mode_update")

  An item is a map: `key` (what its seen state is kept under), `date`, `title`, `body`,
  and when it has them `body2`, `url` (a link the article offers), `button` (the text of
  that link's prompt) and `video` (a video file the game plays under the body). Texts
  are the game's English, with its Scribble colour tags (`[c_pink]`, `[c_aqua]`,
  `[/c]`) in them.

  The items are found in the executable's code. `newsItems` loads, in order, each text's
  localisation key (`<item>_title`, `_body`, `_body2`, `_button`) and the English beside
  it; each item's constructor (`newsItems@newsFeed` structs) loads its key, its date,
  and its link and video when it has them. A Windows `Nidhogg.exe` (64-bit) and the
  arm64 part of a macOS `Nidhogg` are read.

  A player's seen articles are a list of keys, kept with their settings; `unread/2` and
  `seen/2` work on it as the game's `newsIsSeen` and `newsMarkSeen` do on `newsSeen`.
  """

  import Bitwise

  alias Nidhox.ObjectDepths.{Image, MachO, Pe, X64}

  @fields ~w(title body body2 button)
  @constructor ~r/gml_Script____struct___(\d+)(?:@|_40_)newsItems(?:@|_40_)newsFeed/
  @date ~r/^\d{4}\.\d{2}\.\d{2}$/
  @script_symbol ~r/^__Z\d+(gml_\w+?)P9CInstanceS0_R8YYRValueiPPS1_$/

  @type item :: %{
          required(:key) => String.t(),
          required(:date) => String.t(),
          required(:title) => String.t(),
          required(:body) => String.t(),
          optional(:body2) => String.t(),
          optional(:url) => String.t(),
          optional(:button) => String.t(),
          optional(:video) => String.t()
        }

  @doc "The articles in the executable at `path`, in the game's order, or `{:error, reason}`."
  @spec read(Path.t()) :: {:ok, [item()]} | {:error, term()}
  def read(path) do
    with {:ok, bytes} <- File.read(path),
         {:ok, image} <- image(bytes),
         {:ok, texts} <- function_strings(image, "gml_Script_newsItems"),
         [_ | _] = constructors <- constructors(image) do
      {:ok, items(texts, constructors)}
    else
      [] -> {:error, :no_news}
      :error -> {:error, :no_news}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Whether the article `key` is not in `seen`."
  @spec unread([String.t()], String.t()) :: boolean()
  def unread(seen, key), do: key not in seen

  @doc "`seen` with the article `key` in it."
  @spec seen([String.t()], String.t()) :: [String.t()]
  def seen(seen, key), do: if(key in seen, do: seen, else: seen ++ [key])

  @doc "How many of `items` are not in `seen`."
  @spec unread_count([item()], [String.t()]) :: non_neg_integer()
  def unread_count(items, seen), do: Enum.count(items, &unread(seen, &1.key))

  defp image(<<"MZ", _::binary>> = bytes), do: Pe.read(bytes)
  defp image(bytes), do: MachO.read(bytes)

  defp items(texts, constructors) do
    localised = localised(texts, %{})

    for constants <- constructors, key = item_key(constants), key != nil do
      fields = Map.get(localised, key, %{})

      %{key: key, date: Enum.find(constants, "", &(&1 =~ @date))}
      |> Map.merge(fields)
      |> put_found(:url, Enum.find(constants, &String.starts_with?(&1, "http")))
      |> put_found(:video, Enum.find(constants, &String.ends_with?(&1, ".mp4")))
    end
  end

  defp item_key(constants) do
    Enum.find(constants, fn text ->
      not (text =~ @date) and not String.starts_with?(text, "http") and
        not String.ends_with?(text, ".mp4") and text =~ ~r/^[a-z0-9_]+$/
    end)
  end

  defp put_found(item, _key, nil), do: item
  defp put_found(item, key, value), do: Map.put(item, key, value)

  defp localised([key, english | rest], acc) do
    case Regex.run(~r/^([a-z0-9_]+)_(#{Enum.join(@fields, "|")})$/, key) do
      [_, item, field] ->
        fields = Map.put(Map.get(acc, item, %{}), field(field), english)
        localised(rest, Map.put(acc, item, fields))

      nil ->
        localised([english | rest], acc)
    end
  end

  defp localised(_rest, acc), do: acc

  defp field("title"), do: :title
  defp field("body"), do: :body
  defp field("body2"), do: :body2
  defp field("button"), do: :button

  defp constructors(%Image{machine: :arm64, symbols: symbols} = image) do
    symbols
    |> Map.keys()
    |> Enum.flat_map(fn name ->
      with [_, script] <- Regex.run(@script_symbol, name),
           [_, number] <- Regex.run(@constructor, script) do
        [{String.to_integer(number), name}]
      else
        nil -> []
      end
    end)
    |> Enum.uniq_by(&elem(&1, 0))
    |> Enum.sort()
    |> Enum.flat_map(fn {_number, name} ->
      case symbol_strings(image, name) do
        {:ok, strings} -> [strings]
        :error -> []
      end
    end)
  end

  defp constructors(%Image{machine: :x64, bytes: bytes} = image) do
    Regex.scan(~r/gml_Script____struct___(\d+)@newsItems@newsFeed(?=\x00)/, bytes)
    |> Enum.map(fn [name, number] -> {String.to_integer(number), name} end)
    |> Enum.uniq_by(&elem(&1, 0))
    |> Enum.sort()
    |> Enum.flat_map(fn {_number, name} ->
      case function_strings(image, name) do
        {:ok, strings} -> [strings]
        :error -> []
      end
    end)
  end

  defp constructors(_image), do: []

  defp function_strings(%Image{machine: :arm64, symbols: symbols} = image, name) do
    case Enum.find(Map.keys(symbols), &match?([_, ^name], Regex.run(@script_symbol, &1))) do
      nil -> :error
      symbol -> symbol_strings(image, symbol)
    end
  end

  defp function_strings(%Image{machine: :x64} = image, name) do
    with {:ok, {start, stop}} <- X64.named_function(image, name) do
      {:ok, x64_strings(image, start, stop, name)}
    end
  end

  defp function_strings(_image, _name), do: :error

  defp symbol_strings(image, symbol) do
    case Image.named_function(image, symbol) do
      {start, stop} -> {:ok, arm64_strings(image, start, stop)}
      nil -> :error
    end
  end

  defp arm64_strings(image, start, stop) do
    constants = arm64_constants(image)

    image
    |> Image.slice(start, stop)
    |> arm64_addresses(start, %{}, [])
    |> Enum.flat_map(&text_at(image, constants, &1))
  end

  defp arm64_addresses(<<word::little-32, rest::binary>>, pc, pages, acc) do
    cond do
      (word &&& 0x9F000000) == 0x90000000 ->
        low = word >>> 29 &&& 0x3
        high = word >>> 5 &&& 0x7FFFF
        offset = signed((high <<< 2 ||| low) <<< 12, 33)

        arm64_addresses(
          rest,
          pc + 4,
          Map.put(pages, word &&& 0x1F, (pc &&& bnot(0xFFF)) + offset),
          acc
        )

      (word &&& 0xFF800000) == 0x91000000 and Map.has_key?(pages, word >>> 5 &&& 0x1F) ->
        shift = if (word &&& 0x400000) != 0, do: 12, else: 0
        address = pages[word >>> 5 &&& 0x1F] + ((word >>> 10 &&& 0xFFF) <<< shift)
        arm64_addresses(rest, pc + 4, Map.delete(pages, word >>> 5 &&& 0x1F), [address | acc])

      true ->
        arm64_addresses(rest, pc + 4, pages, acc)
    end
  end

  defp arm64_addresses(_rest, _pc, _pages, acc), do: Enum.reverse(acc)

  defp arm64_constants(%Image{symbols: symbols} = image) do
    texts =
      for {symbol, address} <- symbols,
          [_, name] <- [Regex.run(~r/^__ZL\d+(g_pString\d+_[0-9A-F]+)_s$/, symbol)],
          into: %{},
          do: {name, Image.text(image, address)}

    for {symbol, address} <- symbols,
        [_, name] <- [Regex.run(~r/^__ZL\d+(g_pString\d+_[0-9A-F]+)$/, symbol)],
        text = texts[name],
        is_binary(text),
        into: %{},
        do: {address, text}
  end

  defp x64_strings(image, start, stop, name) do
    constants = X64.constant_strings(image)
    body = Image.slice(image, start, stop)

    body
    |> rip_targets(start)
    |> Enum.flat_map(&text_at(image, constants, &1))
    |> Enum.reject(&(&1 == name))
  end

  defp rip_targets(body, start) do
    (:binary.matches(body, <<0x8D>>) ++ :binary.matches(body, <<0x0F, 0x10>>))
    |> Enum.sort()
    |> Enum.flat_map(fn {at, _length} -> rip_target(body, start, at) end)
  end

  defp rip_target(body, start, at) when at >= 1 and at + 7 <= byte_size(body) do
    case binary_part(body, at - 1, 8) do
      <<rex, 0x8D, modrm, displacement::little-signed-32, _::binary>>
      when rex in [0x48, 0x4C] and band(modrm, 0xC7) == 0x05 ->
        [start + at + 6 + displacement]

      <<_byte, 0x0F, 0x10, modrm, displacement::little-signed-32>>
      when band(modrm, 0xC7) == 0x05 ->
        [start + at + 7 + displacement]

      _other ->
        []
    end
  end

  defp rip_target(_body, _start, _at), do: []

  defp text_at(image, constants, address) do
    case Map.fetch(constants, address) do
      {:ok, text} -> [text]
      :error -> c_string(image, address)
    end
  end

  defp c_string(%Image{bytes: bytes} = image, address) do
    with at when is_integer(at) and at > 0 <- Image.offset(image, address),
         0 <- :binary.at(bytes, at - 1),
         text when is_binary(text) and text != "" <- Image.text(image, address),
         true <- String.valid?(text) and String.printable?(text),
         false <- String.starts_with?(text, "gml_") do
      [text]
    else
      _not_text -> []
    end
  end

  defp signed(value, bits) do
    if value >= 1 <<< (bits - 1), do: value - (1 <<< bits), else: value
  end
end
