defmodule CsrfPlus.TokenTest do
  use ExUnit.Case

  def config_fixture() do
    Application.put_env(:csrf_plus, CsrfPlus.Token,
      secret_key:
        "XeMI8JB7othiZ3YOD4aCfSs_L4LZ1FmOaFtE3lFgjQN9cNxWBMsdJcxzp83TIuMcXbKAh1h0jb5zlybAPheTlA=="
    )
  end

  setup do
    on_exit(fn -> Application.delete_env(:csrf_plus, CsrfPlus.Token) end)
  end

  describe "CsrfPlus.Token default" do
    test "if it defaults to CsrfPlus.Token.DefaultToken when no Token module is set in the config" do
      config = Application.get_env(:csrf_plus, CsrfPlus)
      config_fixture()

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

    test "if it raises an error when no secret key is given when generate is called" do
      assert_raise RuntimeError, fn ->
        CsrfPlus.Token.DefaultToken.generate()
      end
    end

    test "if it raises an error when no secret key is given when verify is called" do
      assert_raise RuntimeError, fn ->
        CsrfPlus.Token.DefaultToken.verify("signed")
      end
    end

    test "if it can generate a token" do
      config_fixture()
      result = CsrfPlus.Token.DefaultToken.generate()

      assert match?({_token, _signed}, result)
      {token, signed} = result

      assert is_binary(token)
      assert is_binary(signed)
    end

    test "if it can verify a generated token" do
      config_fixture()

      {token, signed} = CsrfPlus.Token.DefaultToken.generate()
      result = CsrfPlus.Token.DefaultToken.verify(signed)

      assert match?({:ok, ^token}, result)
    end

    test "if verify returns :error with reason in a tuple when the token is invalid" do
      config_fixture()

      result = CsrfPlus.Token.DefaultToken.verify("invalid signed token")

      assert match?({:error, "invalid token"}, result)
    end
  end
end
