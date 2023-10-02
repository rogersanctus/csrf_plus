defmodule CsrfPlus.Store.ManagerTest do
  alias CsrfPlus.Store.Manager
  use ExUnit.Case

  test "if the Store Manager is started" do
    Manager.start_link(token_max_age: 1000)

    pid = Process.whereis(Manager)

    assert is_pid(pid)
    assert Process.alive?(pid)
  end

  test "if the store is not started when missing params" do
    assert_raise FunctionClauseError, fn ->
      Manager.start_link([])
    end
  end
end
