defmodule JidoCodemodeWeb.StaffLiveTest do
  use JidoCodemodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCodemode.{DemoAccessFake, StaffAccess}

  @team "team-test.cloudflareaccess.com"
  @aud "aud-live-test"

  setup do
    private = :public_key.generate_key({:rsa, 2048, 65_537})
    {:RSAPrivateKey, _, n, e, _, _, _, _, _, _, _} = private
    StaffAccess.put_keys(%{"kid-1" => {:RSAPublicKey, n, e}})

    previous = Application.get_env(:jido_codemode, StaffAccess)
    Application.put_env(:jido_codemode, StaffAccess, team_domain: @team, aud: @aud)

    on_exit(fn ->
      :persistent_term.erase({StaffAccess, :keys})

      if previous,
        do: Application.put_env(:jido_codemode, StaffAccess, previous),
        else: Application.delete_env(:jido_codemode, StaffAccess)
    end)

    %{private: private}
  end

  defp jwt(private, overrides \\ %{}, kid \\ "kid-1") do
    now = System.system_time(:second)

    claims =
      Map.merge(
        %{
          "aud" => [@aud],
          "iss" => "https://" <> @team,
          "email" => "alex@superdev.mx",
          "iat" => now,
          "nbf" => now,
          "exp" => now + 3600
        },
        overrides
      )

    encode = &(&1 |> Jason.encode!() |> Base.url_encode64(padding: false))
    input = encode.(%{"alg" => "RS256", "kid" => kid, "typ" => "JWT"}) <> "." <> encode.(claims)
    input <> "." <> Base.url_encode64(:public_key.sign(input, :sha256, private), padding: false)
  end

  defp staff(conn, token), do: put_req_header(conn, "cf-access-jwt-assertion", token)

  test "a co-founder with a valid Access token gets the agent, free and unlocked",
       %{conn: conn, private: private} do
    # Even with invitations on, /live doesn't redirect and spends nothing.
    DemoAccessFake.install(self(), [])

    {:ok, view, _html} = conn |> staff(jwt(private)) |> live(~p"/live")

    assert has_element?(view, "#staff-badge", "alex@superdev.mx")
    assert has_element?(view, "#chat-form")
    refute has_element?(view, "#unlock-form")
    refute has_element?(view, "#invite-status")
  end

  test "the Access cookie works when the header is missing", %{conn: conn, private: private} do
    {:ok, view, _html} =
      conn |> put_req_cookie("CF_Authorization", jwt(private)) |> live(~p"/live")

    assert has_element?(view, "#staff-badge")
  end

  test "anything but a valid token is a plain 404", %{conn: conn, private: private} do
    other = :public_key.generate_key({:rsa, 2048, 65_537})

    for token <- [
          nil,
          "not-a-jwt",
          jwt(private, %{"aud" => ["another-app"]}),
          jwt(private, %{"iss" => "https://evil.cloudflareaccess.com"}),
          jwt(private, %{"exp" => System.system_time(:second) - 120}),
          jwt(private, %{"email" => ""}),
          jwt(private, %{}, "unknown-kid"),
          jwt(other)
        ] do
      conn = if token, do: staff(build_conn(), token), else: build_conn()
      assert conn |> get(~p"/live") |> Map.fetch!(:status) == 404
    end

    _ = conn
  end

  test "unconfigured, /live is closed", %{conn: conn, private: private} do
    Application.put_env(:jido_codemode, StaffAccess, team_domain: nil, aud: nil)
    assert conn |> staff(jwt(private)) |> get(~p"/live") |> Map.fetch!(:status) == 404
  end

  test "the public pages' LiveView socket is not under /live" do
    sockets = JidoCodemodeWeb.Endpoint.__sockets__() |> Enum.map(&elem(&1, 0))
    assert "/lv" in sockets
    refute "/live" in sockets
  end
end
