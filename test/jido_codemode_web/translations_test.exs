defmodule JidoCodemodeWeb.TranslationsTest do
  use JidoCodemodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    previous = Application.get_env(:jido_codemode, :demo_password)
    Application.put_env(:jido_codemode, :demo_password, "test-password")

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:jido_codemode, :demo_password)
      else
        Application.put_env(:jido_codemode, :demo_password, previous)
      end
    end)

    :ok
  end

  test "every es_MX message is translated" do
    {:ok, po} = Expo.PO.parse_file("priv/gettext/es_MX/LC_MESSAGES/default.po")

    untranslated =
      for %Expo.Message.Singular{msgid: id, msgstr: str} <- po.messages,
          IO.iodata_to_binary(str) == "",
          do: IO.iodata_to_binary(id)

    assert untranslated == []
  end

  test "the Spanish page shows Spanish copy and no English interface copy", %{conn: conn} do
    {:ok, _view, html} = conn |> put_req_header("accept-language", "es-MX") |> live(~p"/demo")

    for spanish <- [
          "Convierte preguntas de negocio en análisis claros",
          "Aquí aparecerá tu análisis",
          "Agente de análisis",
          "Tendencia mensual de ingresos",
          "Contraseña de la demo"
        ] do
      assert html =~ spanish
    end

    for english <- [
          "Turn business questions into clear analysis",
          "Your analysis will appear here",
          "Monthly revenue trend",
          "Demo password",
          "How it works"
        ] do
      refute html =~ english
    end
  end
end
