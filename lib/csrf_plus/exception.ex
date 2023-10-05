defmodule CsrfPlus.Exception do
  @moduledoc false

  defexception [:message]

  defmodule HeaderException do
    defexception [:message]
  end

  defmodule MismatchException do
    defexception [:message]
  end

  defmodule SessionException do
    defexception [:message]
  end

  defmodule StoreException do
    defexception [:message]
  end

  @impl Exception
  def exception([]) do
    map_exception(__MODULE__)
  end

  @impl Exception
  def exception({which, type}) when is_atom(type) do
    map_exception(which, type)
  end

  @impl Exception
  def exception(which) when is_atom(which) do
    map_exception(which)
  end

  @impl Exception
  def exception(message) when is_binary(message) do
    map_exception_message(__MODULE__, message)
  end

  def csrf_plus_exception?(%{__exception__: true, __struct__: exception}) do
    csrf_plus_exception?(exception)
  end

  def csrf_plus_exception?(exception) when is_atom(exception) do
    Map.has_key?(exceptions(), exception)
  end

  defp map_exception(which, type \\ nil) when is_atom(type) do
    {exception, message} = get_exception(which, type)

    map_exception_message(exception, message)
  end

  defp map_exception_message(exception, message) do
    exception
    |> Map.from_struct()
    |> Map.put(:message, message)
    |> Map.put(:__struct__, exception)
  end

  def exceptions do
    %{
      "#{__MODULE__}.HeaderException":
        {HeaderException, [default: "missing token in the requrest header"]},
      "#{__MODULE__}.MismatchException": {MismatchException, [default: "tokens mismatch"]},
      "#{__MODULE__}.SessionException":
        {SessionException,
         [default: "missing token in the session", missing_id: "missing id in the session"]},
      "#{__MODULE__}.StoreException": {StoreException, [default: "no store is set"]},
      "#{__MODULE__}": {__MODULE__, [default: "invalid token"]}
    }
  end

  defp get_exception(which, type) do
    {exception, messages} = Map.get(exceptions(), which)

    message =
      if type != nil && Keyword.has_key?(messages, type) do
        Keyword.get(messages, type)
      else
        Keyword.get(messages, :default, "unknown exception")
      end

    {exception, message}
  end
end
