defmodule JidoCodemode.SidebarAgentTest do
  use ExUnit.Case, async: false

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
