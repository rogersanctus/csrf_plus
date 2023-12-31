defmodule CsrfPlus.Exception do
  @moduledoc """
  CsrfPlus exceptions.
  """

  defexception [:message]

  defmodule SignedException do
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

  @doc """
  Creates a new CsrfPlus exception based on the given params during the `Kernel.raise/2` call.

  Passing no param will create a `CsrfPlus.Exception`.

  If a string is passed it will be used as the exception message.

  If it's an exception module name (an atom) an exception will be created from it with the default message set in the
  `exceptions/0` function.

  When a tuple is passed in the format `{which, type}` an exception with name `which` will be created having the message set in the
  `exception/1` function with the message in `type`.

  ## Examples

       iex> raise CsrfPlus.Exception
       ** (CsrfPlus.Exception) invalid token

       iex> raise CsrfPlus.Exception, "custom message"
       ** (CsrfPlus.Exception) custom message

       iex> raise CsrfPlus.Exception, CsrfPlus.Exception.StoreException
       ** (CsrfPlus.Exception.StoreException) no store is set

       iex> raise CsrfPlus.Exception, {CsrfPlus.Exception.StoreException, :token_not_found}
       ** (CsrfPlus.Exception.StoreException) token was not found

  """

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

  @doc """
  Checks if the given exception is a CsrfPlus exception.
  Returns a boolean true if the given exception is a CsrfPlus.
  """
  def csrf_plus_exception?(%{__exception__: true, __struct__: exception}) do
    csrf_plus_exception?(exception)
  end

  def csrf_plus_exception?(exception) when is_atom(exception) do
    Map.has_key?(exceptions(), exception)
  end

  @doc "Retrieve all the CsrfPlus exceptions with their corresponding names and messages"
  def exceptions do
    %{
      "#{__MODULE__}.SignedException":
        {SignedException,
         [
           default:
             "missing the signed token in the request. Either send it in the response header or response body."
         ]},
      "#{__MODULE__}.MismatchException": {MismatchException, [default: "tokens mismatch"]},
      "#{__MODULE__}.SessionException":
        {SessionException,
         [default: "missing token in the session", missing_id: "missing id in the session"]},
      "#{__MODULE__}.StoreException":
        {StoreException,
         [
           default: "no store is set",
           token_not_found: "token was not found",
           token_expired: "token has expired"
         ]},
      "#{__MODULE__}": {__MODULE__, [default: "invalid token"]}
    }
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
