defimpl Jason.Encoder, for: Jido.Action.Error.InvalidInputError do
  def encode(error, opts) do
    Jason.Encode.map(
      %{
        message: Map.get(error, :message, "Invalid input"),
        field: Map.get(error, :field),
        details: Map.get(error, :details, %{})
      },
      opts
    )
  end
end

defimpl Jason.Encoder, for: Jido.Action.Error.ExecutionFailureError do
  def encode(error, opts) do
    Jason.Encode.map(
      %{
        message: Map.get(error, :message, "Execution failed"),
        details: Map.get(error, :details, %{})
      },
      opts
    )
  end
end

defimpl Jason.Encoder, for: Jido.Action.Error.TimeoutError do
  def encode(error, opts) do
    Jason.Encode.map(
      %{
        message: Map.get(error, :message, "Action timed out"),
        timeout: Map.get(error, :timeout),
        details: Map.get(error, :details, %{})
      },
      opts
    )
  end
end

defimpl Jason.Encoder, for: Jido.Action.Error.ConfigurationError do
  def encode(error, opts) do
    Jason.Encode.map(
      %{
        message: Map.get(error, :message, "Configuration error"),
        details: Map.get(error, :details, %{})
      },
      opts
    )
  end
end

defimpl Jason.Encoder, for: Jido.Action.Error.InternalError do
  def encode(error, opts) do
    Jason.Encode.map(
      %{
        message: Map.get(error, :message, "Internal error"),
        details: Map.get(error, :details, %{})
      },
      opts
    )
  end
end
