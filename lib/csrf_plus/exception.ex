defmodule CsrfPlus.Exception do
  @moduledoc false

  defexception [:message]

  defmodule Header do
    defexception [:message]
  end

  defmodule Mismatch do
    defexception [:message]
  end

  defmodule Session do
    defexception [:message]
  end

  defmodule Store do
    defexception [:message]
  end

  @impl Exception
  def exception(nil) do
    map_exception(__MODULE__)
  end

  @impl Exception
  def exception({which, message}) do
    map_exception(which, message)
  end

  @impl Exception
  def exception(which) when is_atom(which) do
    map_exception(which)
  end

  @impl Exception
  def exception(message) when is_binary(message) do
    map_exception(__MODULE__, message)
  end

  defp map_exception(which, message \\ nil) do
    {exception, default_message} =
      case Map.get(exceptions(), which) do
        nil ->
          Map.get(exceptions(), __MODULE__, {__MODULE__, "unknown exception"})

        the_exception ->
          the_exception
      end

    exception
    |> Map.from_struct()
    |> Map.put(:message, message || default_message)
    |> Map.put(:__struct__, exception)
  end

  def exceptions do
    %{
      "#{__MODULE__}.Header": {Header, "missing token in the requrest header"},
      "#{__MODULE__}.Mismatch": {Mismatch, "tokens mismatch"},
      "#{__MODULE__}.Session": {Session, "missing token in the session"},
      "#{__MODULE__}.Store": {Store, "missing token in the store"},
      "#{__MODULE__}": {__MODULE__, "invalid token"}
    }
  end
end
