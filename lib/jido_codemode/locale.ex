defmodule JidoCodemode.Locale do
  @moduledoc """
  Supported page languages and how the language of a request is chosen.

  Order: an explicit `?lang=` value, then the saved cookie, then the browser's
  `Accept-Language` header, then English.
  """

  @supported ["en", "es_MX"]
  @default "en"
  @cookie "agentic_bi_locale"

  @spec supported() :: [String.t()]
  def supported, do: @supported

  @spec default() :: String.t()
  def default, do: @default

  @spec cookie_name() :: String.t()
  def cookie_name, do: @cookie

  @doc "Maps a user-supplied value to a supported locale, or nil."
  @spec normalize(term()) :: String.t() | nil
  def normalize(value) when is_binary(value) do
    case value |> String.trim() |> String.downcase() |> String.replace("-", "_") do
      "es" <> _ -> "es_MX"
      "en" <> _ -> "en"
      _ -> nil
    end
  end

  def normalize(_value), do: nil

  @doc "The highest-weighted supported language in an Accept-Language header, or nil."
  @spec from_accept_language(String.t() | nil) :: String.t() | nil
  def from_accept_language(header) when is_binary(header) do
    header
    |> String.split(",")
    |> Enum.map(&parse_entry/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(fn {_tag, weight} -> -weight end)
    |> Enum.find_value(fn {tag, _weight} -> normalize(tag) end)
  end

  def from_accept_language(_header), do: nil

  @spec resolve(term(), term(), String.t() | nil) :: String.t()
  def resolve(param, cookie, accept_language) do
    normalize(param) || normalize(cookie) || from_accept_language(accept_language) || @default
  end

  @spec html_lang(String.t()) :: String.t()
  def html_lang("es_MX"), do: "es-MX"
  def html_lang(_locale), do: "en"

  defp parse_entry(entry) do
    case entry |> String.trim() |> String.split(";") do
      [""] -> nil
      [tag | params] -> {String.trim(tag), weight(params)}
    end
  end

  defp weight(params) do
    Enum.find_value(params, 1.0, fn param ->
      case param |> String.trim() |> String.split("=") do
        ["q", value] ->
          case Float.parse(value) do
            {weight, _rest} -> weight
            :error -> 0.0
          end

        _other ->
          nil
      end
    end)
  end
end
