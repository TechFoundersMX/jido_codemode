defmodule JidoCodemodeWeb.PageControllerTest do
  use JidoCodemodeWeb.ConnCase

  test "GET /health", %{conn: conn} do
    conn = get(conn, ~p"/health")
    assert response(conn, 200) == "ok"
  end
end
