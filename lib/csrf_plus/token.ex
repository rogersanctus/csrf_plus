defmodule CsrfPlus.Token do
  @moduledoc false

  @callback generate() :: {String.t(), String.t()}
  @callback verify(signed_token :: String.t()) :: :ok | {:error, term()}

  @default_token_mod __MODULE__.DefaultToken

  defmodule DefaultToken do
    @moduledoc false

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

  def generate() do
    token_mod = token_mod()
    apply(token_mod, :generate, [])
  end

  def verify(signed_token) do
    token_mod = token_mod()
    apply(token_mod, :verify, [signed_token])
  end

  defp config() do
    Application.get_env(:csrf_plus, CsrfPlus, [])
  end

  def token_mod() do
    config()
    |> Keyword.get(:token_mod, @default_token_mod)
  end
end
