defmodule CsrfPlus.Fixtures do
  def token_config_fixture() do
    Application.put_env(:csrf_plus, CsrfPlus.Token,
      secret_key:
        "XeMI8JB7othiZ3YOD4aCfSs_L4LZ1FmOaFtE3lFgjQN9cNxWBMsdJcxzp83TIuMcXbKAh1h0jb5zlybAPheTlA=="
    )
  end
end
