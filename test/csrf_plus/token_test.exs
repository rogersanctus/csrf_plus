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

    test "if it raises an error when no secret key is given" do
      assert_raise RuntimeError, fn ->
        CsrfPlus.Token.DefaultToken.generate()
      end
    end
  end
end
