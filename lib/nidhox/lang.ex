defmodule Nidhox.Lang do
  @moduledoc """
  The game's languages (`locInit`, `locApplyLanguage`, `cmn_loc_get_func`): every text
  is looked up by a section and a key in the copy's `lang/<code>.json`, beside its data
  file, and is the English the game's code gives when the language has none.

      Nidhox.Lang.text("fr", "main menu", "options", "OPTIONS")
      Nidhox.Lang.text("en", "attract mode", "press_start", "press {0}", ["start"])

  `{n}` in a text is replaced by the `n`th argument, as a string; a `{n}` with no
  argument stays as written. English (`"en"`) has no file. `font/1` is the font the menus
  use in a language: `fMenu`, or for Chinese, Japanese, Korean, Russian, Polish and
  Ukrainian their own (`LocFont`). `initial/1` is the language a system locale names
  (`locInitialLanguageCode`), English for any it does not know.
  """

  alias Nidhox.Assets

  @languages [
    {"en", "English", "fMenu"},
    {"fr", "Français", "fMenu"},
    {"it", "Italiano", "fMenu"},
    {"de", "Deutsch", "fMenu"},
    {"es-es", "Español (ES)", "fMenu"},
    {"zh-cn", "简体中文", "f_zh"},
    {"ru", "Русский", "f_ru"},
    {"es-419", "Español (LA)", "fMenu"},
    {"pt", "Português", "fMenu"},
    {"ja", "日本語", "f_ja"},
    {"ko", "한국어", "f_ko"},
    {"pl", "Polski", "f_ru"},
    {"zh-tw", "繁體中文", "f_zh"},
    {"uk", "Українська", "f_ru"}
  ]

  @locales [
    {~w(de de-de german), "de"},
    {~w(es es-es spanish), "es-es"},
    {~w(es-419 es-mx latam), "es-419"},
    {~w(fr fr-fr fr-ca french), "fr"},
    {~w(it it-it italian), "it"},
    {~w(ja ja-jp japanese), "ja"},
    {~w(ko ko-kr korean koreana), "ko"},
    {~w(pl pl-pl polish), "pl"},
    {~w(pt pt-pt pt-br portuguese brazilian), "pt"},
    {~w(ru ru-ru russian), "ru"},
    {~w(uk uk-ua ukrainian), "uk"},
    {~w(zh zh-cn zh-hans schinese), "zh-cn"},
    {~w(zh-tw zh-hk zh-hant tchinese), "zh-tw"}
  ]

  @doc "The languages in the game's order, each `{code, name, font}`."
  @spec languages() :: [{String.t(), String.t(), String.t()}]
  def languages, do: @languages

  @doc "The language codes in the game's order."
  @spec codes() :: [String.t()]
  def codes, do: Enum.map(@languages, &elem(&1, 0))

  @doc "The name language `code` calls itself by, `code` itself for one the game does not have."
  @spec name(String.t()) :: String.t()
  def name(code) do
    case List.keyfind(@languages, code, 0) do
      {^code, name, _font} -> name
      nil -> code
    end
  end

  @doc "The font the menus are drawn in for language `code`."
  @spec font(String.t()) :: String.t()
  def font(code) do
    case List.keyfind(@languages, code, 0) do
      {^code, _name, font} -> font
      nil -> "fMenu"
    end
  end

  @doc "The language after `code` (`step` 1) or before it (`step` −1), round the list."
  @spec step(String.t(), integer()) :: String.t()
  def step(code, step) do
    codes = codes()
    index = Enum.find_index(codes, &(&1 == code)) || 0
    Enum.at(codes, Integer.mod(index + step, length(codes)))
  end

  @doc """
  The language a system locale names, such as `"de_DE.UTF-8"` or `"pt-BR"`: its
  language and region, then its language alone, matched as the game matches them;
  English otherwise.
  """
  @spec initial(String.t() | nil) :: String.t()
  def initial(nil), do: "en"

  def initial(locale) do
    tag =
      locale
      |> String.split(".", parts: 2)
      |> hd()
      |> String.replace("_", "-")
      |> String.downcase()

    language = tag |> String.split("-", parts: 2) |> hd()
    matched(tag) || matched(language) || "en"
  end

  defp matched(tag),
    do: Enum.find_value(@locales, fn {names, code} -> if tag in names, do: code end)

  @doc "The text of `key` in `section` in language `code`, else `english`, with `{n}` filled from `args`."
  @spec text(String.t(), String.t(), String.t(), String.t(), [term()]) :: String.t()
  def text(code, section, key, english, args \\ []) do
    code
    |> table()
    |> get_in([section, key])
    |> case do
      text when is_binary(text) -> text
      _missing -> english
    end
    |> filled(args)
  end

  defp filled(text, []), do: text

  defp filled(text, args) do
    Regex.replace(~r/\{(\d+)\}/, text, fn whole, number ->
      case Enum.at(args, String.to_integer(number)) do
        nil -> whole
        arg -> to_string(arg)
      end
    end)
  end

  defp table("en"), do: %{}

  defp table(code) do
    key = {__MODULE__, code}

    case :persistent_term.get(key, nil) do
      nil ->
        table = read(code)
        :persistent_term.put(key, table)
        table

      table ->
        table
    end
  end

  defp read(code) do
    path = Path.join([Path.dirname(Assets.get().path), "lang", code <> ".json"])

    with {:ok, json} <- File.read(path),
         {:ok, table} when is_map(table) <- JSON.decode(json) do
      table
    else
      _missing -> %{}
    end
  end
end
