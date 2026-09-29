defmodule JidoCodemode.SidebarAgentTest do
  use ExUnit.Case, async: false

  alias JidoCodemode.Locale.Dataset
  alias JidoCodemode.SidebarAgent

  test "the Spanish prompt carries the mirror rule, voice, glossary, and MXN rule" do
    prompt = SidebarAgent.system_prompt_with_schema("es_MX")

    assert prompt =~ "The page language is Spanish (Mexico)."
    assert prompt =~ "Answer in the language of the user's question."
    assert prompt =~ ~s(use Mexican Spanish with "tú")
    assert prompt =~ "Bebidas (Beverages)"
    assert prompt =~ "already in Mexican pesos (MXN)"
    assert prompt =~ "17.8413"
    assert prompt =~ "Never convert them again."
    assert prompt =~ "Schema digest:"
  end

  test "both prompts require every BuildReport string, including SQL aliases, in the answer language" do
    for locale <- ["es_MX", "en"] do
      prompt = SidebarAgent.system_prompt_with_schema(locale)

      assert prompt =~ "Every string you pass to BuildReport"
      assert prompt =~ "SQL column aliases used as table headers or axis titles"
      assert prompt =~ "in the language of your answer"
    end

    assert SidebarAgent.system_prompt_with_schema("es_MX") =~ ~s|AS "Ingresos (MXN)"|
    assert SidebarAgent.system_prompt_with_schema("en") =~ ~s|AS "Revenue"|
  end

  test "the Spanish alias example follows the currency the data is in" do
    assert SidebarAgent.system_prompt_with_schema("es_MX") =~ ~s|AS "Ingresos (MXN)"|

    previous = Application.get_env(:jido_codemode, Dataset)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:jido_codemode, Dataset, previous),
        else: Application.delete_env(:jido_codemode, Dataset)

      Dataset.reset()
    end)

    Application.put_env(:jido_codemode, Dataset, fx_usd_mxn: "abc")
    Dataset.reset()

    prompt = SidebarAgent.system_prompt_with_schema("es_MX")

    assert prompt =~ ~s|AS "Ingresos (USD)"|
    assert prompt =~ "Write amounts as $1,234.56 USD."
    refute prompt =~ "(MXN)"
  end

  test "both prompts tell the agent to sort comparison bars largest first" do
    for locale <- ["es_MX", "en"] do
      prompt = SidebarAgent.system_prompt_with_schema(locale)

      assert prompt =~ "sort the bars by the measured value, largest first"
      assert prompt =~ "unless the question asks for another order"
    end
  end

  test "the Spanish glossary parentheses are only the English original" do
    prompt = SidebarAgent.system_prompt_with_schema("es_MX")

    assert prompt =~ "only the English original"
    assert prompt =~ "must not be used in SQL filters"
  end

  test "the English prompt keeps USD and has no Spanish glossary" do
    prompt = SidebarAgent.system_prompt_with_schema("en")

    assert prompt =~ "The page language is English."
    assert prompt =~ "US dollars (USD)"
    refute prompt =~ "Bebidas"
  end

  test "the default is English" do
    assert SidebarAgent.system_prompt_with_schema() ==
             SidebarAgent.system_prompt_with_schema("en")
  end
end
