defmodule CsrfPlus.ErrorMapper do
  @moduledoc """
  Defines the behaviour for an ErrorModule while also defining a default map function.
  """

  @callback map(exception :: Exception.t()) :: {status_code :: atom() | integer(), error :: map()}

  @behaviour __MODULE__

  @doc "Maps a CsrfPlus exception into a tuple with the status code and the error map."
  @impl __MODULE__
  def map(exception) do
    if CsrfPlus.Exception.csrf_plus_exception?(exception) do
      error =
        %{
          is_csrf_error: true,
          reason: module_to_string(exception.__struct__),
          message: exception.message
        }

      {:unauthorized, error}
    else
      raise exception
    end
  end

  @doc "Converts a module to string, but without the Elixir prefix."
  def module_to_string(module) when is_atom(module) do
    module
    |> to_string()
    |> String.replace_prefix("Elixir.", "")
  end

  def module_from_string(nil) do
    nil
  end

  @doc "Converts back a string representation of a module to an actual module name"
  def module_from_string(string) when is_binary(string) do
    "Elixir."
    |> Kernel.<>(string)
    |> String.to_atom()
  end
end
