defmodule JidoCodemode.StaffAccess do
  @moduledoc """
  Verifies the Cloudflare Access token that lets co-founders use `/live`.

  Cloudflare Access protects `agentic-bi.superdev.mx/live` with the co-founders'
  policy and forwards a signed JWT (`Cf-Access-Jwt-Assertion`, also the
  `CF_Authorization` cookie). This module checks it: RS256 signature against the
  team's published keys, `aud` equal to the application's AUD tag, `iss` equal
  to the team domain, and `exp`. Anything else fails closed.

  Configured with `config :jido_codemode, JidoCodemode.StaffAccess,
  team_domain: "<team>.cloudflareaccess.com", aud: "<AUD tag>"`
  (`CF_ACCESS_TEAM_DOMAIN`, `CF_ACCESS_LIVE_AUD`). Unconfigured, nobody passes.
  """

  @keys_key {__MODULE__, :keys}
  @keys_ttl_seconds 10 * 60
  @leeway_seconds 60

  @type claims :: %{email: String.t(), expires_at: integer()}

  @spec configured?() :: boolean()
  def configured?, do: not is_nil(team_domain()) and not is_nil(aud())

  @doc "Verifies an Access JWT. Returns the co-founder's email and the token's expiry."
  @spec verify(String.t() | nil, integer()) :: {:ok, claims()} | :error
  def verify(jwt, now \\ System.system_time(:second))

  def verify(jwt, now) when is_binary(jwt) do
    with true <- configured?(),
         [header64, payload64, signature64] <- String.split(jwt, "."),
         {:ok, header} <- decode_json(header64),
         %{"alg" => "RS256", "kid" => kid} <- header,
         {:ok, key} <- key(kid),
         {:ok, signature} <- Base.url_decode64(signature64, padding: false),
         true <- :public_key.verify(header64 <> "." <> payload64, :sha256, signature, key),
         {:ok, claims} <- decode_json(payload64),
         true <- valid_claims?(claims, now) do
      {:ok, %{email: claims["email"], expires_at: claims["exp"]}}
    else
      _invalid -> :error
    end
  end

  def verify(_jwt, _now), do: :error

  @doc false
  # Tests install keys directly instead of fetching them.
  def put_keys(keys) when is_map(keys),
    do: :persistent_term.put(@keys_key, {keys, System.system_time(:second)})

  defp valid_claims?(claims, now) do
    audience = List.wrap(claims["aud"])

    aud() in audience and claims["iss"] == "https://" <> team_domain() and
      is_integer(claims["exp"]) and claims["exp"] + @leeway_seconds > now and
      (not is_integer(claims["nbf"]) or claims["nbf"] - @leeway_seconds <= now) and
      is_binary(claims["email"]) and claims["email"] != ""
  end

  defp key(kid) do
    case cached_keys() do
      %{^kid => key} ->
        {:ok, key}

      _missing ->
        # Keys rotate: refetch once when a token names an unknown kid.
        with {:ok, keys} <- fetch_keys(), %{^kid => key} <- keys, do: {:ok, key}
    end
  end

  defp cached_keys do
    case :persistent_term.get(@keys_key, nil) do
      {keys, fetched_at} ->
        if System.system_time(:second) - fetched_at < @keys_ttl_seconds,
          do: keys,
          else: refresh_or(keys)

      nil ->
        refresh_or(%{})
    end
  end

  defp refresh_or(fallback) do
    case fetch_keys() do
      {:ok, keys} -> keys
      :error -> fallback
    end
  end

  defp fetch_keys do
    url = "https://" <> team_domain() <> "/cdn-cgi/access/certs"

    with {:ok, %Req.Response{status: 200, body: %{"keys" => jwks}}} <-
           Req.get(url, receive_timeout: 5_000, retry: false) do
      keys =
        for %{"kty" => "RSA", "kid" => kid, "n" => n, "e" => e} <- jwks, into: %{} do
          {kid, {:RSAPublicKey, decode_int(n), decode_int(e)}}
        end

      put_keys(keys)
      {:ok, keys}
    else
      _error -> :error
    end
  end

  defp decode_int(value),
    do: value |> Base.url_decode64!(padding: false) |> :binary.decode_unsigned()

  defp decode_json(segment) do
    with {:ok, json} <- Base.url_decode64(segment, padding: false),
         {:ok, map} when is_map(map) <- Jason.decode(json) do
      {:ok, map}
    else
      _error -> :error
    end
  end

  defp config, do: Application.get_env(:jido_codemode, __MODULE__, [])
  defp team_domain, do: present(config()[:team_domain])
  defp aud, do: present(config()[:aud])

  defp present(value) when is_binary(value) and value != "", do: value
  defp present(_value), do: nil
end
