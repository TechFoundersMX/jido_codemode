defmodule JidoCodemodeWeb.PageController do
  use JidoCodemodeWeb, :controller

  def health(conn, _params) do
    text(conn, "ok")
  end
end
