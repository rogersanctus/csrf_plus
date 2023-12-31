defmodule CsrfPlus.Store.MemoryDbTest do
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

    test "if an access is correctly stored" do
      MemoryDb.start_link([])

      created_at = System.os_time(:millisecond)
      access = %UserAccess{token: "a_token", access_id: "an_id", created_at: created_at}

      MemoryDb.put_access(access)

      all_accesses = MemoryDb.all_accesses()

      assert Enum.count(all_accesses) == 1
      store_access = hd(all_accesses)
      assert match?(^access, store_access)

      # New tokens are not expired by default
      refute store_access.expired?
    end

    test "if accesses are stored correctly" do
      access_id = "an_id"

      tokens = [
        "token_one",
        "token_two",
        "token_three"
      ]

      created_at = System.os_time(:millisecond)

      MemoryDb.start_link([])

      MemoryDb.put_access(%UserAccess{
        token: Enum.at(tokens, 0),
        access_id: access_id,
        created_at: created_at
      })

      MemoryDb.put_access(%UserAccess{
        token: Enum.at(tokens, 1),
        access_id: access_id,
        created_at: created_at
      })

      MemoryDb.put_access(%UserAccess{
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

    test "if put a wrong access returns an error" do
      MemoryDb.start_link([])

      put_result = MemoryDb.put_access(:wrong)

      assert match?({:error, :invalid_param}, put_result)
    end

    test "if an access can be retrieved by access_id" do
      MemoryDb.start_link([])
      token = "a_token"
      access_id = "the_id"

      MemoryDb.put_access(%UserAccess{
        token: token,
        access_id: access_id
      })

      retrieved_access = MemoryDb.get_access(access_id)

      assert retrieved_access.token == token
    end

    test "if trying to retrieve a non stored access returns nil" do
      MemoryDb.start_link([])
      retrieved_access = MemoryDb.get_access("non_stored_access_id")

      assert retrieved_access == nil
    end

    test "if trying to retrieve an access with invalid param fails with error" do
      MemoryDb.start_link([])

      retrieve_result = MemoryDb.get_access(:wrong)

      assert match?({:error, :invalid_param}, retrieve_result)
    end

    test "if an access can be deleted" do
      MemoryDb.start_link([])

      token = "a_token"
      access_id = "the_id"

      MemoryDb.put_access(%UserAccess{
        token: token,
        access_id: access_id
      })

      deleted_result = MemoryDb.delete_access(access_id)

      assert match?({:ok, _}, deleted_result)
      {:ok, deleted_access} = deleted_result
      assert deleted_access.token == token
    end

    test "if a non existing acess cannot be deleted and returns an error" do
      MemoryDb.start_link([])

      deleted_result = MemoryDb.delete_access("non_existing_access_id")

      assert match?({:error, _}, deleted_result)
      {:error, error} = deleted_result
      assert error == :not_found
    end

    test "if trying to delete an access fails with error when the param is invalid" do
      MemoryDb.start_link([])

      delete_result = MemoryDb.delete_access(:wrong)

      assert match?({:error, :invalid_param}, delete_result)
    end

    test "if all dead accesses are flagged as expired after :delete_dead_accesses/1 is called" do
      MemoryDb.start_link([])

      # 100 milliseconds
      max_age = 100

      good_time = System.os_time(:millisecond)

      all_raw = [
        %{
          token: "health token 1",
          access_id: "access_id_1",
          created_at: good_time
        },
        %{
          token: "dead token 1",
          access_id: "access_id_2",
          created_at: good_time - max_age - 1
        },
        %{
          token: "health token 2",
          access_id: "access_id_3",
          created_at: good_time
        },
        %{
          token: "dead token 2",
          access_id: "access_id_4",
          created_at: good_time - max_age - 1
        }
      ]

      Enum.each(all_raw, fn raw ->
        MemoryDb.put_access(%UserAccess{
          token: raw.token,
          access_id: raw.access_id,
          created_at: raw.created_at
        })
      end)

      all_accesses = MemoryDb.all_accesses()

      assert Enum.count(all_accesses) == Enum.count(all_raw)

      almost_checking_time = System.os_time(:millisecond)
      result = MemoryDb.delete_dead_accesses(max_age)

      assert result == :ok

      all_accesses_after_delete = MemoryDb.all_accesses()

      # Even after deleting all dead accesses, the number of accesses should be the same
      # as the dead accesses are only flagged as expired
      assert Enum.count(all_accesses_after_delete) == 4

      # There must be two expired accesses
      assert Enum.count(all_accesses_after_delete, fn access ->
               access.expired?
             end) == 2

      non_expired_accesses =
        Enum.reject(all_accesses_after_delete, fn entry -> entry.expired? end)

      assert Enum.all?(non_expired_accesses, fn access ->
               almost_checking_time <= access.created_at + max_age
             end)
    end

    test "if no access is flagged as expired after :delete_dead_accesses/1 is called and all accesses are healthy" do
      MemoryDb.start_link([])

      # 100 milliseconds
      max_age = 100

      good_time = System.os_time(:millisecond)

      all_raw = [
        %{
          token: "health token 1",
          access_id: "access_id_1",
          created_at: good_time
        },
        %{
          token: "health token 2",
          access_id: "access_id_2",
          created_at: good_time
        }
      ]

      Enum.each(all_raw, fn raw ->
        MemoryDb.put_access(%UserAccess{
          token: raw.token,
          access_id: raw.access_id,
          created_at: raw.created_at
        })
      end)

      all_accesses = MemoryDb.all_accesses()

      assert Enum.count(all_accesses) == Enum.count(all_raw)

      result = MemoryDb.delete_dead_accesses(max_age)

      assert result == :ok

      all_accesses_after_delete = MemoryDb.all_accesses()

      assert Enum.count(all_accesses_after_delete) == Enum.count(all_raw)
      assert Enum.count(all_accesses_after_delete, fn access -> access.expired? == false end)
    end
  end
end
