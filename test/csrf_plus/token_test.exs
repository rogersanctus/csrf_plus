defmodule CsrfPlus.TokenTest do
  use ExUnit.Case

  alias CsrfPlus.Fixtures

  setup do
    on_exit(fn -> Application.delete_env(:csrf_plus, CsrfPlus.Token) end)
  end

  describe "CsrfPlus.Token default" do
    test "if it defaults to CsrfPlus.Token.DefaultToken when no Token module is set in the config" do
      config = Application.get_env(:csrf_plus, CsrfPlus)
      Fixtures.token_config_fixture()

      raised =
        try do
          CsrfPlus.Token.generate()
          false
        rescue
          RuntimeError ->
            true
        end

      assert config == nil
      refute raised
    end

    test "if it raises an error when no secret key is given when sign_token is called" do
      assert_raise RuntimeError, fn ->
        CsrfPlus.Token.sign_token("token")
      end
    end

    test "if it raises an error when no secret key is given when verify is called" do
      assert_raise RuntimeError, fn ->
        CsrfPlus.Token.verify("signed")
      end
    end

    test "if it can generate a token" do
      Fixtures.token_config_fixture()
      result = CsrfPlus.Token.generate()

      assert match?({_token, _signed}, result)
      {token, signed} = result

      assert is_binary(token)
      assert is_binary(signed)
    end

    test "if it can verify a generated token" do
      Fixtures.token_config_fixture()

      {token, signed} = CsrfPlus.Token.generate()
      result = CsrfPlus.Token.verify(signed)

      assert match?({:ok, ^token}, result)
    end

    test "if verify returns :error with reason in a tuple when the token is invalid" do
      Fixtures.token_config_fixture()

      result = CsrfPlus.Token.verify("invalid signed token")

      assert match?({:error, "invalid token"}, result)
    end

    test "if the generate_token function uses the token_generation_fn when it's set" do
      generation_fn = fn -> "token generated" end
      Fixtures.token_config_fixture(token_generation_fn: generation_fn)

      token = CsrfPlus.Token.generate_token()
      assert token == "token generated"
    end
  end
end
