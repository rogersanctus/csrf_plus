defmodule CsrfPlus.Token do
  @moduledoc """
  Defines the Token behaviour and a DefaultToken module implementation.
  """

  @doc """
  The function to generate a token. It must returns a tuple with the token itself and the signed version of it.
  In the format `{token, signed_token}`.

  The `signed_token` is the token signed with some secret key or crypto algorithm that allows further verification.
  """
  @callback generate() :: {String.t(), String.t()}

  @doc """
  Simply put, must verifies a `signed_token`.

  Returns `{:ok, verified_token}` in case of success. Or `{:error, the_error_itself}`.

  The `verified_token` is the original token before being signed.
  """
  @callback verify(signed_token :: String.t()) :: {:ok, String.t()} | {:error, term()}

  @default_token_mod __MODULE__.DefaultToken

  defmodule DefaultToken do
    @moduledoc """
    The default module implementation for the Token behaviour.

    It uses the `Plug.Crypto.MessageVerifier` module to sign and verify tokens under the hood.
    """

    @behaviour CsrfPlus.Token
    @no_secret_key_message "CsrfPlus.Token requires secret_key to be given when no Token module is set"

    def generate() do
      secret_key = Keyword.get(config(), :secret_key) || raise @no_secret_key_message
      generation_fn = Keyword.get(config(), :token_generation_fn, &UUID.uuid4/0)

      if !is_function(generation_fn) do
        raise "CsrfPlus.Token requires token_generation_fn to be a function"
      end

      token = generation_fn.()

      signed = Plug.Crypto.MessageVerifier.sign(token, secret_key)

      {token, signed}
    end

    def verify(signed) do
      secret_key =
        Keyword.get(config(), :secret_key) || raise @no_secret_key_message

      case Plug.Crypto.MessageVerifier.verify(signed, secret_key) do
        :error ->
          {:error, "invalid token"}

        ok ->
          ok
      end
    end

    defp config() do
      Application.get_env(:csrf_plus, CsrfPlus.Token, [])
    end
  end

  @doc "Calls the configured Token module to generate a token"
  def generate() do
    token_mod = token_mod()
    apply(token_mod, :generate, [])
  end

  @doc "Calls the configured Token module to verify a `signed_token`"
  def verify(signed_token) do
    token_mod = token_mod()
    apply(token_mod, :verify, [signed_token])
  end

  defp config() do
    Application.get_env(:csrf_plus, CsrfPlus, [])
  end

  defp token_mod() do
    config()
    |> Keyword.get(:token_mod, @default_token_mod)
  end
end
