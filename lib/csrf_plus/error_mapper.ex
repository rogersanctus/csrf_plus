defmodule CsrfPlus.ErrorMapper do
  @callback map(exception :: Exception.t()) :: {status_code :: atom() | integer(), error :: map()}

  @behaviour __MODULE__

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

  def module_to_string(module) when is_atom(module) do
    module
    |> to_string()
    |> String.replace_prefix("Elixir.", "")
  end

  def module_from_string(nil) do
    nil
  end

  def module_from_string(string) when is_binary(string) do
    "Elixir."
    |> Kernel.<>(string)
    |> String.to_atom()
  end
end
