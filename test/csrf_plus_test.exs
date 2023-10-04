defmodule CsrfPlus.CsrfPlusTest do
  use ExUnit.Case

  import Plug.Test
  alias CsrfPlus.UserAccess
  alias CsrfPlus
  alias CsrfPlus.Fixtures

  defp build_conn(method) do
    conn = conn(method, "/")

    %{
      conn
      | # Generated with :crypto.strong_rand_bytes(64) |> Base.encode64()
        secret_key_base:
          "96uqV4XL/GpDMgDDc7/G2p6AO1PM6FqI5b4JnyUh95F2bUtGDA5Uee1eHd+vaxmB6ilrZfU6ZglBJI6Wo7tW9A=="
    }
  end

  defp build_session_conn(method) do
    config =
      Plug.Session.init(key: "_session_test", store: :cookie, signing_salt: "$salt4meSalTforU&")

    build_conn(method)
    |> Plug.Session.call(config)
  end

  defp build_session_req_conn(method, put_header_token? \\ false) do
    Fixtures.token_config_fixture()
    config = Application.get_env(:csrf_plus, CsrfPlus.Token)
    config = Keyword.merge(config, token_generation_fn: &CsrfPlus.OkStoreMock.the_token/0)
    Application.put_env(:csrf_plus, CsrfPlus.Token, config)

    csrf_config =
      CsrfPlus.init(csrf_key: :csrf_token)

    resp_conn =
      :get
      |> build_session_conn()
      |> Plug.Conn.fetch_session()
      |> CsrfPlus.call(csrf_config)

    {token, signed} = CsrfPlus.Token.generate()

    resp_conn =
      resp_conn
      |> CsrfPlus.put_session_token(token)
      |> Plug.Conn.send_resp(:no_content, "")

    {_, cookie} = List.keyfind(resp_conn.resp_headers, "set-cookie", 0, {"set-cookie", nil})

    put_header_token = fn conn ->
      if put_header_token? do
        Plug.Conn.put_req_header(conn, "x-csrf-token", signed)
      else
        conn
      end
    end

    method
    |> build_session_conn()
    |> Plug.Conn.put_req_header("cookie", cookie)
    |> put_header_token.()
    |> Plug.Conn.fetch_session()
  end

  # Clean up CsrfPlus configuration after each test
  setup do
    on_exit(fn ->
      Application.delete_env(:csrf_plus, CsrfPlus)
      Application.delete_env(:csrf_plus, CsrfPlus.Token)
    end)
  end

  describe "CSRF Plug configuration" do
    test "if the correct store is set and called when CsrfPlus is plugged" do
      Mox.stub(CsrfPlus.StoreMock, :get_access, fn _ ->
        send(self(), :store_called)
        %UserAccess{token: CsrfPlus.OkStoreMock.the_token()}
      end)

      Application.put_env(:csrf_plus, CsrfPlus, store: CsrfPlus.StoreMock)
      config = CsrfPlus.init(csrf_key: :csrf_token)

      conn =
        build_session_req_conn(:post, true)
        |> Plug.Conn.put_session(:access_id, CsrfPlus.OkStoreMock.access_id())

      CsrfPlus.call(conn, config)

      assert_receive :store_called
    end

    test "if when an allowed method is set the Conn is not halted" do
      config = CsrfPlus.init(allowed_methods: ["PATCH"])

      conn = build_conn(:patch)
      new_conn = CsrfPlus.call(conn, config)

      refute new_conn.halted
    end
  end

  describe "CsrfPlus validations" do
    test "if it can put a token into the session" do
      plug_config = CsrfPlus.init(csrf_key: :csrf_token)
      Fixtures.token_config_fixture()

      conn =
        build_session_conn(:get)
        |> Plug.Conn.fetch_session()
        |> CsrfPlus.call(plug_config)

      {token, signed} = CsrfPlus.Token.generate()
      new_conn = CsrfPlus.put_session_token(conn, token)

      conn_token = Plug.Conn.get_session(new_conn, :csrf_token)
      result = CsrfPlus.Token.verify(signed)

      assert conn_token == token
      assert match?({:ok, ^token}, result)
    end

    test "if it fails to put a token into the session when CsrfPlus is not plugged yet" do
      Fixtures.token_config_fixture()

      conn =
        build_session_conn(:get)
        |> Plug.Conn.fetch_session()

      {token, _} = CsrfPlus.Token.generate()
      assert_raise CsrfPlus.Exception, fn -> CsrfPlus.put_session_token(conn, token) end
    end

    test "if the token validation fails when there is no session_id set in the request session" do
      csrf_config = CsrfPlus.init(csrf_key: :csrf_token)
      conn = build_session_req_conn(:post)

      assert_raise CsrfPlus.Exception.Session, fn ->
        CsrfPlus.call(conn, csrf_config)
      end
    end

    test "if the validation fails when there is no token in the request headers" do
      csrf_config = CsrfPlus.init(csrf_key: :csrf_token)
      conn = build_session_req_conn(:post)

      assert_raise CsrfPlus.Exception.Header, fn ->
        conn
        |> Plug.Conn.put_session(:access_id, CsrfPlus.OkStoreMock.access_id())
        |> CsrfPlus.call(csrf_config)
      end
    end

    test "if the validation fails when no token store is set" do
      csrf_config = CsrfPlus.init(csrf_key: :csrf_token)
      conn = build_session_req_conn(:post, true)

      assert_raise CsrfPlus.Exception.Store, fn ->
        conn
        |> Plug.Conn.put_session(:access_id, CsrfPlus.OkStoreMock.access_id())
        |> CsrfPlus.call(csrf_config)
      end
    end

    test "if the validation fails when there is no token in the connection session" do
      Mox.stub_with(CsrfPlus.StoreMock, CsrfPlus.OkStoreMock)
      Application.put_env(:csrf_plus, CsrfPlus, store: CsrfPlus.StoreMock)
      csrf_config = CsrfPlus.init(csrf_key: :csrf_token)

      assert_raise CsrfPlus.Exception.Session, fn ->
        :post
        |> build_session_conn()
        |> Plug.Conn.fetch_session()
        |> Plug.Conn.put_session(:access_id, CsrfPlus.OkStoreMock.access_id())
        |> Plug.Conn.put_req_header("x-csrf-token", CsrfPlus.OkStoreMock.the_token())
        |> CsrfPlus.call(csrf_config)
      end
    end

    test "if the validation fails when the token in the session is different from the token in the store" do
      Mox.stub(CsrfPlus.StoreMock, :get_access, fn _ -> %UserAccess{token: "different token"} end)
      Application.put_env(:csrf_plus, CsrfPlus, store: CsrfPlus.StoreMock)
      csrf_config = CsrfPlus.init(csrf_key: :csrf_token)

      assert_raise CsrfPlus.Exception.Mismatch, fn ->
        :post
        |> build_session_req_conn(true)
        |> Plug.Conn.put_session(:access_id, CsrfPlus.OkStoreMock.access_id())
        |> CsrfPlus.call(csrf_config)
      end
    end

    test "if the validation fails when everything is ok but the token in the header is invalid" do
      Mox.stub_with(CsrfPlus.StoreMock, CsrfPlus.OkStoreMock)
      Application.put_env(:csrf_plus, CsrfPlus, store: CsrfPlus.StoreMock)
      csrf_config = CsrfPlus.init(csrf_key: :csrf_token)

      assert_raise CsrfPlus.Exception, fn ->
        :post
        |> build_session_req_conn()
        |> Plug.Conn.put_session(:access_id, CsrfPlus.OkStoreMock.access_id())
        |> Plug.Conn.put_req_header("x-csrf-token", "wrong token")
        |> CsrfPlus.call(csrf_config)
      end
    end

    test "if the validation fails when the header token is valid but does not match the session token or the store token" do
      Mox.stub(CsrfPlus.StoreMock, :get_access, fn _ -> %UserAccess{token: "different token"} end)
      Application.put_env(:csrf_plus, CsrfPlus, store: CsrfPlus.StoreMock)
      csrf_config = CsrfPlus.init(csrf_key: :csrf_token)

      assert_raise CsrfPlus.Exception.Mismatch, fn ->
        :post
        |> build_session_req_conn(true)
        |> Plug.Conn.put_session(:access_id, CsrfPlus.OkStoreMock.access_id())
        |> Plug.Conn.put_session(:csrf_token, "different token")
        |> CsrfPlus.call(csrf_config)
      end
    end

    test "if the validation succeeds when all the tokens are valid and matches each other" do
      Mox.stub_with(CsrfPlus.StoreMock, CsrfPlus.OkStoreMock)
      Application.put_env(:csrf_plus, CsrfPlus, store: CsrfPlus.StoreMock)
      csrf_config = CsrfPlus.init(csrf_key: :csrf_token)

      conn =
        :post
        |> build_session_req_conn(true)
        |> Plug.Conn.put_session(:access_id, CsrfPlus.OkStoreMock.access_id())
        |> CsrfPlus.call(csrf_config)

      refute conn.halted
    end
  end
end
