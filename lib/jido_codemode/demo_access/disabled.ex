defmodule JidoCodemode.DemoAccess.Disabled do
  @moduledoc "Default client while the invitation service is not connected: nobody is invited."

  @behaviour JidoCodemode.DemoAccess

  @impl true
  def status(_token), do: {:error, :unavailable}

  @impl true
  def consume(_token, _conversation_id), do: {:error, :unavailable}

  @impl true
  def refund(_token, _conversation_id), do: :ok
end
