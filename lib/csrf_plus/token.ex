defmodule CsrfPlus.Token do
  @moduledoc """
  Defines the Token behaviour and a DefaultToken module implementation.
  """

  @doc """
  Responsible to generate a unique token.

  ## Returns
  The generated token.
  """
  @callback generate_token() :: String.t()

  @doc """
  Responsible to sign a token.
  The **signed token** is the token signed with some secret key or crypto algorithm that allows further verification.

  ## Params
    * `token` - The token to sign.

  ## Returns
    A signed token.

  """
  @callback sign_token(token :: String.t()) :: String.t()

  @doc """
  The function to generate the token tuple. It must be a tuple with the token itself and the signed version of it.
  In the format `{token, signed_token}`.

  This callback is optional as all it does is to call `generate_token/0` and `sign_token/1` to generate both token
  and its signed version.

  """
  @callback generate() :: {String.t(), String.t()}

  @doc """
  Simply put, must verifies a `signed_token`.
  It must use the same secret key or crypto algorithm as in the sign_token function.

  > #### Note {: .info}
  > The `verified_token` is the original token before being signed.

  ## Returns
  `{:ok, verified_token}` in case of success. Or `{:error, the_error_itself}`.

  """
  @callback verify(signed_token :: String.t()) :: {:ok, String.t()} | {:error, term()}

  @optional_callbacks [generate: 0]

  @default_token_mod __MODULE__.DefaultToken

  defmodule DefaultToken do
    @moduledoc """
    The default module implementation for the Token behaviour.

    It uses the `Plug.Crypto.MessageVerifier` module to sign and verify tokens under the hood.
    """

    @behaviour CsrfPlus.Token
    @no_secret_key_message "CsrfPlus.Token requires secret_key to be given when no Token module is set"

    def generate_token() do
      generation_fn = Keyword.get(config(), :token_generation_fn, &UUID.uuid4/0)

      if !is_function(generation_fn) do
        raise "CsrfPlus.Token requires token_generation_fn to be a function"
      end

      generation_fn.()
    end

    def sign_token(token) do
      secret_key = Keyword.get(config(), :secret_key) || raise @no_secret_key_message
      Plug.Crypto.MessageVerifier.sign(token, secret_key)
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

  @doc """
  Calls the configured Token module to generate a token
  """
  def generate_token() do
    token_mod = token_mod()
    apply(token_mod, :generate_token, [])
  end

  @doc """
  Calls the configured Token module to sign a given `token`
  """
  def sign_token(token) do
    token_mod = token_mod()
    apply(token_mod, :sign_token, [token])
  end

  @doc """
  Just wraps `generate_token/0` and `sign_token/1` functions in a convenient function
  """
  def generate() do
    token = generate_token()
    signed = sign_token(token)

    {token, signed}
  end

  @doc """
  Calls the configured Token module to verify a `signed_token`
  """
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
