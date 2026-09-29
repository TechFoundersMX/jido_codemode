defmodule JidoCodemode.Locale.GlossaryTest do
  use ExUnit.Case, async: true

  alias JidoCodemode.Locale.Glossary

  test "covers the 8 Northwind categories with the approved translations" do
    assert Glossary.categories() == %{
             "Beverages" => "Bebidas",
             "Condiments" => "Condimentos",
             "Confections" => "Dulces y postres",
             "Dairy Products" => "Lácteos",
             "Grains/Cereals" => "Granos y cereales",
             "Meat/Poultry" => "Carnes y aves",
             "Produce" => "Frutas y verduras",
             "Seafood" => "Pescados y mariscos"
           }
  end

  test "covers all 25 countries in the data" do
    countries = Glossary.countries()
    assert map_size(countries) == 25
    assert countries["Germany"] == "Alemania"
    assert countries["UK"] == "Reino Unido"
    assert countries["USA"] == "Estados Unidos"
    assert countries["Mexico"] == "México"
    assert countries["Netherlands"] == "Países Bajos"
  end

  test "prompt_summary/0 pairs Spanish names with the English originals" do
    summary = Glossary.prompt_summary()
    assert summary =~ "Bebidas (Beverages)"
    assert summary =~ "Alemania (Germany)"
  end
end
