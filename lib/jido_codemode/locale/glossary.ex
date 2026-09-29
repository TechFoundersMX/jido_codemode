defmodule JidoCodemode.Locale.Glossary do
  @moduledoc """
  Reviewed English to Spanish (Mexico) names for Northwind's categories and
  countries. Product, customer, and shipper names are proper nouns and are not
  translated.
  """

  @categories %{
    "Beverages" => "Bebidas",
    "Condiments" => "Condimentos",
    "Confections" => "Dulces y postres",
    "Dairy Products" => "Lácteos",
    "Grains/Cereals" => "Granos y cereales",
    "Meat/Poultry" => "Carnes y aves",
    "Produce" => "Frutas y verduras",
    "Seafood" => "Pescados y mariscos"
  }

  @countries %{
    "Argentina" => "Argentina",
    "Australia" => "Australia",
    "Austria" => "Austria",
    "Belgium" => "Bélgica",
    "Brazil" => "Brasil",
    "Canada" => "Canadá",
    "Denmark" => "Dinamarca",
    "Finland" => "Finlandia",
    "France" => "Francia",
    "Germany" => "Alemania",
    "Ireland" => "Irlanda",
    "Italy" => "Italia",
    "Japan" => "Japón",
    "Mexico" => "México",
    "Netherlands" => "Países Bajos",
    "Norway" => "Noruega",
    "Poland" => "Polonia",
    "Portugal" => "Portugal",
    "Singapore" => "Singapur",
    "Spain" => "España",
    "Sweden" => "Suecia",
    "Switzerland" => "Suiza",
    "UK" => "Reino Unido",
    "USA" => "Estados Unidos",
    "Venezuela" => "Venezuela"
  }

  @spec categories() :: %{String.t() => String.t()}
  def categories, do: @categories

  @spec countries() :: %{String.t() => String.t()}
  def countries, do: @countries

  @doc "One line for the agent instructions: Spanish names with the English original."
  @spec prompt_summary() :: String.t()
  def prompt_summary do
    "categories: " <> pairs(@categories) <> "; countries: " <> pairs(@countries)
  end

  defp pairs(map) do
    map
    |> Enum.sort_by(fn {english, _spanish} -> english end)
    |> Enum.map_join(", ", fn {english, spanish} -> "#{spanish} (#{english})" end)
  end
end
