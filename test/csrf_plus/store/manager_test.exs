defmodule CsrfPlus.Store.ManagerTest do
  alias CsrfPlus.Store.Manager
  use ExUnit.Case

  setup _ do
    on_exit(fn ->
      Application.delete_env(:csrf_plus, CsrfPlus)
    end)
  end

  test "if the Store Manager is started" do
    Manager.start_link(token_max_age: 1000)

    pid = Process.whereis(Manager)

    assert is_pid(pid)
    assert Process.alive?(pid)
  end

  test "if the store is not started when missing params" do
    assert_raise RuntimeError, fn ->
      Manager.start_link([])
    end
  end

  test "if the Store is called after the Manager checking time" do
    Application.put_env(:csrf_plus, CsrfPlus, store: CsrfPlus.StoreMock)

    Manager.start_link(token_max_age: 1000, check_age_time: 20)

    manager_pid = Process.whereis(Manager)
    test_pid = self()

    Mox.stub(CsrfPlus.StoreMock, :delete_dead_accesses, fn _ -> send(test_pid, :store_called) end)
    Mox.allow(CsrfPlus.StoreMock, test_pid, manager_pid)

    assert_receive :store_called
  end
end
