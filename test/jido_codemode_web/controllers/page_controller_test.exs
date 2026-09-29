defmodule JidoCodemodeWeb.PageControllerTest do
  use JidoCodemodeWeb.ConnCase

  test "GET /health", %{conn: conn} do
    conn = get(conn, ~p"/health")
    assert response(conn, 200) == "ok"
  end

  test "Phoenix leaves /admin and /api/admin to the invitation service's Worker", %{conn: conn} do
    for path <- [
          "/admin/invitations",
          "/api/admin/invitations",
          "/invite/solicitar",
          "/api/invite/partner/status"
        ] do
      assert build_conn() |> get(path) |> Map.fetch!(:status) == 404
    end

    _ = conn
  end
end
