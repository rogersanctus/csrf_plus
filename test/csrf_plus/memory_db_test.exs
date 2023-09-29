defmodule CsrfPlus.MemoryDbTest do
  use ExUnit.Case

  alias CsrfPlus.UserAccess
  alias CsrfPlus.Store.MemoryDb

  setup do
    on_exit(fn ->
      memory_db_pid = Process.whereis(MemoryDb)

      if is_pid(memory_db_pid) do
        Process.exit(memory_db_pid, :normal)
      end
    end)
  end

  describe "MemoryDb" do
    test "if, at start, thereis no tokens in the store" do
      MemoryDb.start_link([])

      all_tokens = MemoryDb.all_accesses()

      assert Enum.empty?(all_tokens)
    end

    test "if a token is correctly stored" do
      MemoryDb.start_link([])

      created_at = System.os_time(:millisecond)
      access = %UserAccess{token: "a_token", access_id: "an_id", created_at: created_at}

      MemoryDb.put_token(access)

      all_accesses = MemoryDb.all_accesses()

      assert Enum.count(all_accesses) == 1
      store_access = hd(all_accesses)
      assert match?(^access, store_access)
    end

    test "if tokens are store correctly" do
      access_id = "an_id"

      tokens = [
        "token_one",
        "token_two",
        "token_three"
      ]

      created_at = System.os_time(:millisecond)

      MemoryDb.start_link([])

      MemoryDb.put_token(%UserAccess{
        token: Enum.at(tokens, 0),
        access_id: access_id,
        created_at: created_at
      })

      MemoryDb.put_token(%UserAccess{
        token: Enum.at(tokens, 1),
        access_id: access_id,
        created_at: created_at
      })

      MemoryDb.put_token(%UserAccess{
        token: Enum.at(tokens, 2),
        access_id: access_id,
        created_at: created_at
      })

      all_accesses = MemoryDb.all_accesses()

      assert Enum.count(all_accesses) == 3

      assert Enum.all?(tokens, fn token ->
               Enum.find(all_accesses, nil, fn entry -> entry.token == token end) != nil
             end)
    end
  end
end
