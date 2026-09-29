defmodule JidoCodemode.LocaleTest do
  use ExUnit.Case, async: true

  alias JidoCodemode.Locale

  describe "normalize/1" do
    test "maps Spanish and English variants to supported locales" do
      assert Locale.normalize("es") == "es_MX"
      assert Locale.normalize("es-MX") == "es_MX"
      assert Locale.normalize("ES_es") == "es_MX"
      assert Locale.normalize("en") == "en"
      assert Locale.normalize("en-GB") == "en"
    end

    test "returns nil for unsupported or missing values" do
      assert Locale.normalize("fr") == nil
      assert Locale.normalize("") == nil
      assert Locale.normalize(nil) == nil
    end
  end

  describe "from_accept_language/1" do
    test "takes the highest-weighted supported language" do
      assert Locale.from_accept_language("es-MX,es;q=0.9,en;q=0.8") == "es_MX"
      assert Locale.from_accept_language("fr-FR,fr;q=0.9,es;q=0.8,en;q=0.7") == "es_MX"
      assert Locale.from_accept_language("en-US,en;q=0.9,es;q=0.8") == "en"
      assert Locale.from_accept_language("es;q=0.4,en;q=0.9") == "en"
    end

    test "returns nil when nothing is supported" do
      assert Locale.from_accept_language("fr-FR,de;q=0.8") == nil
      assert Locale.from_accept_language("") == nil
      assert Locale.from_accept_language(nil) == nil
    end
  end

  describe "resolve/3" do
    test "prefers the parameter, then the cookie, then the header" do
      assert Locale.resolve("en", "es_MX", "es-MX") == "en"
      assert Locale.resolve(nil, "es_MX", "en-US") == "es_MX"
      assert Locale.resolve("xx", nil, "es-ES") == "es_MX"
      assert Locale.resolve(nil, nil, nil) == "en"
    end
  end

  test "html_lang/1" do
    assert Locale.html_lang("es_MX") == "es-MX"
    assert Locale.html_lang("en") == "en"
  end
end
