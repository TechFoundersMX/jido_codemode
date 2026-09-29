defmodule JidoCodemode.DemoAccessFake do
  @moduledoc """
  Stand-in for the invitation service in tests. `install/2` makes it the client
  for the current test and restores the previous one on exit. Every call is sent
  to the test process as `{:demo_access, action, args}`.

  Options: `:status` (a map of token => status result, default unavailable),
  `:consume` and `:refund` (results, or 2-arity functions of token and
  conversation id).
  """

  @behaviour JidoCodemode.DemoAccess

  import ExUnit.Callbacks, only: [on_exit: 1]

  def install(test_pid, opts) do
    previous = Application.get_env(:jido_codemode, :demo_access_client)
    Application.put_env(:jido_codemode, :demo_access_client, __MODULE__)
    Application.put_env(:jido_codemode, __MODULE__, Keyword.put(opts, :pid, test_pid))

    on_exit(fn ->
      Application.delete_env(:jido_codemode, __MODULE__)

      if previous,
        do: Application.put_env(:jido_codemode, :demo_access_client, previous),
        else: Application.delete_env(:jido_codemode, :demo_access_client)
    end)
  end

  @impl true
  def status(token) do
    notify(:status, [token])
    opts() |> Keyword.get(:status, %{}) |> Map.get(token, {:error, :unavailable})
  end

  @impl true
  def consume(token, conversation_id) do
    notify(:consume, [token, conversation_id])
    result(:consume, token, conversation_id, {:ok, 2})
  end

  @impl true
  def refund(token, conversation_id) do
    notify(:refund, [token, conversation_id])
    result(:refund, token, conversation_id, :ok)
  end

  defp result(key, token, conversation_id, default) do
    case Keyword.get(opts(), key, default) do
      fun when is_function(fun, 2) -> fun.(token, conversation_id)
      value -> value
    end
  end

  defp notify(action, args), do: send(Keyword.fetch!(opts(), :pid), {:demo_access, action, args})
  defp opts, do: Application.get_env(:jido_codemode, __MODULE__, [])
end
