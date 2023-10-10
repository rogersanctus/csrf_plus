defmodule CsrfPlus.Fixtures do
  @moduledoc false

  def token_config_fixture(other_options \\ []) do
    options = [
      secret_key:
        "XeMI8JB7othiZ3YOD4aCfSs_L4LZ1FmOaFtE3lFgjQN9cNxWBMsdJcxzp83TIuMcXbKAh1h0jb5zlybAPheTlA=="
    ]

    Application.put_env(:csrf_plus, CsrfPlus.Token, Keyword.merge(options, other_options))
  end
end
