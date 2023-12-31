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

  defp build_session_req_conn(method, put_signed_token \\ :none) do
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
      case put_signed_token do
        :none ->
          conn

        :header ->
          Plug.Conn.put_req_header(conn, "x-csrf-token", signed)

        :body ->
          Map.put(conn, :body_params, %{"_csrf_token" => signed})
      end
    end

    method
    |> build_session_conn()
    |> Plug.Conn.put_req_header("cookie", cookie)
    |> put_header_token.()
    |> Plug.Conn.fetch_session()
  end

  defp exception_from_conn(conn) do
    body = Jason.decode!(conn.resp_body)

    body
    |> Map.get("reason")
    |> CsrfPlus.ErrorMapper.module_from_string()
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
        build_session_req_conn(:post, :header)
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

    test "if an exception is thrown when :raise_exception? is set to true" do
      config = CsrfPlus.init(raise_exception?: true)

      conn =
        :post
        |> build_session_conn()
        |> Plug.Conn.fetch_session()

      assert_raise CsrfPlus.Exception.SessionException, fn ->
        CsrfPlus.call(conn, config)
      end
    end

    test "if an error is set in the response body when :raise_exception? is set to false" do
      config = CsrfPlus.init()

      conn =
        :post
        |> build_session_conn()
        |> Plug.Conn.fetch_session()

      conn = CsrfPlus.call(conn, config)

      assert exception_from_conn(conn) == CsrfPlus.Exception.SessionException
    end
  end

  describe "CsrfPlus public functions" do
    test "if it can put a token into the session when no access_id is given" do
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

    test "if it can put a token into the session when access_id is given" do
      plug_config = CsrfPlus.init(csrf_key: :csrf_token)
      Fixtures.token_config_fixture()

      conn =
        build_session_conn(:get)
        |> Plug.Conn.fetch_session()
        |> CsrfPlus.call(plug_config)

      access_id = UUID.uuid4()
      {token, signed} = CsrfPlus.Token.generate()
      new_conn = CsrfPlus.put_session_token(conn, token, access_id)

      conn_token = Plug.Conn.get_session(new_conn, :csrf_token)
      conn_access_id = Plug.Conn.get_session(new_conn, :access_id)
      result = CsrfPlus.Token.verify(signed)

      assert conn_token == token
      assert conn_access_id == access_id
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

    test "if it put a token into the header." do
      Fixtures.token_config_fixture()

      plug_config = CsrfPlus.init(csrf_key: :csrf_token)

      conn =
        build_session_conn(:get)
        |> Plug.Conn.fetch_session()
        |> CsrfPlus.call(plug_config)

      {token, signed_token} = CsrfPlus.Token.generate()

      new_conn = CsrfPlus.put_header_token(conn, signed_token)

      conn_tokens = Plug.Conn.get_resp_header(new_conn, "x-csrf-token")
      conn_token = Enum.at(conn_tokens, 0)

      assert conn_token == signed_token

      result = CsrfPlus.Token.verify(signed_token)

      assert match?({:ok, ^token}, result)
    end

    test "if it fails to put a token in the store when no access_id is given" do
      plug_config = CsrfPlus.init(csrf_key: :csrf_token)
      Fixtures.token_config_fixture()

      conn =
        build_session_conn(:get)
        |> Plug.Conn.fetch_session()
        |> CsrfPlus.call(plug_config)

      {token, _signed} = CsrfPlus.Token.generate()

      assert_raise CsrfPlus.Exception, fn ->
        CsrfPlus.put_store_token(conn, token, nil)
      end
    end

    test "if it put a token in the store" do
      Mox.stub(CsrfPlus.OptionalStoreMock, :put_access, fn access ->
        Process.put(:store_access, access)
      end)

      Mox.stub(CsrfPlus.OptionalStoreMock, :get_access, fn _ -> Process.get(:store_access) end)
      Application.put_env(:csrf_plus, CsrfPlus, store: CsrfPlus.OptionalStoreMock)

      plug_config = CsrfPlus.init(csrf_key: :csrf_token)
      Fixtures.token_config_fixture()

      conn =
        build_session_conn(:get)
        |> Plug.Conn.fetch_session()
        |> CsrfPlus.call(plug_config)

      {token, _signed} = CsrfPlus.Token.generate()

      access_id = UUID.uuid4()
      new_conn = CsrfPlus.put_store_token(conn, token, access_id)

      store_access = CsrfPlus.OptionalStoreMock.get_access(access_id)

      assert store_access.access_id == access_id
      assert store_access.token == token
      # The conn are not affected by put_store_token
      assert conn == new_conn
    end

    test "if it can put an access in the store with a implemente conn_to_access function in the store" do
      Mox.stub(CsrfPlus.StoreMock, :conn_to_access, fn conn, raw_access ->
        user_agent =
          conn
          |> Plug.Conn.get_req_header("user-agent")
          |> Enum.at(0)

        %UserAccess{}
        |> Map.put(:access_id, raw_access.access_id)
        |> Map.put(:token, raw_access.token)
        |> Map.put(:user_info, %CsrfPlus.UserAccessInfo{
          ip: "an_ip",
          user_agent: user_agent
        })
      end)

      Mox.stub(CsrfPlus.StoreMock, :put_access, fn access ->
        Process.put(:store_access, access)
      end)

      Mox.stub(CsrfPlus.StoreMock, :get_access, fn _ -> Process.get(:store_access) end)
      Application.put_env(:csrf_plus, CsrfPlus, store: CsrfPlus.StoreMock)

      plug_config = CsrfPlus.init(csrf_key: :csrf_token)
      Fixtures.token_config_fixture()

      user_agent = "the best browser on the world"

      conn =
        build_session_conn(:get)
        |> Plug.Conn.fetch_session()
        |> Plug.Conn.put_req_header("user-agent", user_agent)
        |> CsrfPlus.call(plug_config)

      {token, _signed} = CsrfPlus.Token.generate()

      access_id = UUID.uuid4()
      CsrfPlus.put_store_token(conn, token, access_id)

      store_access = CsrfPlus.StoreMock.get_access(access_id)

      assert store_access.access_id == access_id
      assert store_access.token == token
      assert store_access.user_info.user_agent == user_agent
    end

    test "if put_token/2 fails when the token_tuple is not not given" do
      plug_config = CsrfPlus.init(csrf_key: :csrf_token)

      conn =
        build_session_conn(:get)
        |> Plug.Conn.fetch_session()
        |> CsrfPlus.call(plug_config)

      assert_raise CsrfPlus.Exception, fn ->
        CsrfPlus.put_token(conn, access_id: "access id")
      end
    end

    test "if put_token/2 puts token in all necessary places" do
      Mox.stub(CsrfPlus.OptionalStoreMock, :put_access, fn access ->
        Process.put(:store_access, access)
      end)

      # Fakes a get_access that must match the access_id
      Mox.stub(CsrfPlus.OptionalStoreMock, :get_access, fn access_id ->
        stored = Process.get(:store_access)

        if stored != nil && stored.access_id == access_id do
          stored
        end
      end)

      Application.put_env(:csrf_plus, CsrfPlus, store: CsrfPlus.OptionalStoreMock)

      plug_config = CsrfPlus.init(csrf_key: :csrf_token)

      Fixtures.token_config_fixture()

      conn =
        build_session_conn(:get)
        |> Plug.Conn.fetch_session()
        |> CsrfPlus.call(plug_config)

      {token, signed_token} = CsrfPlus.Token.generate()

      new_conn = CsrfPlus.put_token(conn, token_tuple: {token, signed_token})

      conn_header_token = Plug.Conn.get_resp_header(new_conn, "x-csrf-token") |> Enum.at(0)
      conn_session_access_id = Plug.Conn.get_session(new_conn, :access_id)
      conn_session_token = Plug.Conn.get_session(new_conn, :csrf_token)
      store_access = CsrfPlus.OptionalStoreMock.get_access(conn_session_access_id)

      assert token == conn_session_token
      assert store_access != nil
      assert store_access.token == token

      verify_result = CsrfPlus.Token.verify(conn_header_token)

      assert match?({:ok, ^token}, verify_result)
    end

    test "if put_token/2 don't put the header token when :header is on the exclude list" do
      Mox.stub(CsrfPlus.OptionalStoreMock, :put_access, fn access ->
        Process.put(:store_access, access)
      end)

      Mox.stub(CsrfPlus.OptionalStoreMock, :get_access, fn _ -> Process.get(:store_access) end)
      Application.put_env(:csrf_plus, CsrfPlus, store: CsrfPlus.OptionalStoreMock)
      csrf_config = CsrfPlus.init(csrf_key: :csrf_token)
      Fixtures.token_config_fixture()

      conn =
        build_session_conn(:get)
        |> Plug.Conn.fetch_session()
        |> CsrfPlus.call(csrf_config)

      {token, signed_token} = CsrfPlus.Token.generate()

      new_conn = CsrfPlus.put_token(conn, token_tuple: {token, signed_token}, exclude: [:header])

      conn_header_token = Plug.Conn.get_resp_header(new_conn, "x-csrf-token") |> List.first()

      assert conn_header_token == nil

      conn_session_token = Plug.Conn.get_session(new_conn, :csrf_token)
      store_access = CsrfPlus.OptionalStoreMock.get_access(conn_session_token)

      assert conn_session_token == token
      assert store_access.token == token
    end

    test "if put_token/2 don't put the session id and token when :session is on the exclude list" do
      Mox.stub(CsrfPlus.OptionalStoreMock, :put_access, fn access ->
        Process.put(:store_access, access)
      end)

      Mox.stub(CsrfPlus.OptionalStoreMock, :get_access, fn _ -> Process.get(:store_access) end)
      Application.put_env(:csrf_plus, CsrfPlus, store: CsrfPlus.OptionalStoreMock)
      csrf_config = CsrfPlus.init(csrf_key: :csrf_token)
      Fixtures.token_config_fixture()

      conn =
        build_session_conn(:get)
        |> Plug.Conn.fetch_session()
        |> CsrfPlus.call(csrf_config)

      {token, signed_token} = CsrfPlus.Token.generate()

      new_conn = CsrfPlus.put_token(conn, token_tuple: {token, signed_token}, exclude: [:session])

      header_token = Plug.Conn.get_resp_header(new_conn, "x-csrf-token") |> List.first()
      session_token = Plug.Conn.get_session(new_conn, :csrf_token)
      session_access_id = Plug.Conn.get_session(new_conn, :access_id)
      store_access = CsrfPlus.OptionalStoreMock.get_access(session_token)

      assert header_token == signed_token
      assert session_token == nil
      assert session_access_id == nil
      assert store_access.token == token
    end

    test "if put_token/2 don't put the store token when :s is on the exclude list" do
      Mox.stub(CsrfPlus.OptionalStoreMock, :put_access, fn access ->
        Process.put(:store_access, access)
      end)

      Mox.stub(CsrfPlus.OptionalStoreMock, :get_access, fn _ -> Process.get(:store_access) end)
      Application.put_env(:csrf_plus, CsrfPlus, store: CsrfPlus.OptionalStoreMock)
      csrf_config = CsrfPlus.init(csrf_key: :csrf_token)
      Fixtures.token_config_fixture()

      conn =
        build_session_conn(:get)
        |> Plug.Conn.fetch_session()
        |> CsrfPlus.call(csrf_config)

      {token, signed_token} = CsrfPlus.Token.generate()

      new_conn = CsrfPlus.put_token(conn, token_tuple: {token, signed_token}, exclude: [:store])

      header_token = Plug.Conn.get_resp_header(new_conn, "x-csrf-token") |> List.first()
      session_token = Plug.Conn.get_session(new_conn, :csrf_token)
      session_access_id = Plug.Conn.get_session(new_conn, :access_id)
      store_access = CsrfPlus.OptionalStoreMock.get_access(session_token)

      assert header_token == signed_token
      assert session_token == token
      assert session_access_id != nil
      assert store_access == nil
    end

    test "if get_token_tuple/1 generate a new token tuple when the access_id is not on the session" do
      test_token = "was generated here"

      Fixtures.token_config_fixture(
        token_generation_fn: fn ->
          test_token
        end
      )

      Mox.stub_with(CsrfPlus.StoreMock, CsrfPlus.OkStoreMock)
      Application.put_env(:csrf_plus, CsrfPlus, store: CsrfPlus.StoreMock)

      conn =
        build_session_conn(:get)
        |> Plug.Conn.fetch_session()
        |> CsrfPlus.call(CsrfPlus.init(csrf_key: :csrf_token))

      {token, _signed_token} = CsrfPlus.get_token_tuple(conn)

      assert token == test_token
    end

    test "if get_token_tuple/1 generates a new token tuple when an access is not found for a given access_id" do
      test_token = "was generated here"

      Fixtures.token_config_fixture(
        token_generation_fn: fn ->
          test_token
        end
      )

      Mox.stub(CsrfPlus.StoreMock, :get_access, fn _ -> nil end)
      Application.put_env(:csrf_plus, CsrfPlus, store: CsrfPlus.StoreMock)

      conn =
        build_session_conn(:get)
        |> Plug.Conn.fetch_session()
        |> Plug.Conn.put_session(:access_id, "access_id")
        |> CsrfPlus.call(CsrfPlus.init(csrf_key: :csrf_token))

      {token, _signed_token} = CsrfPlus.get_token_tuple(conn)

      assert token == test_token
    end

    test "if get_token_tuple/1 get a token from the store for the access_id and uses the signed token in the header" do
      test_token = "store token"

      Fixtures.token_config_fixture(
        token_generation_fn: fn ->
          "was generated here"
        end
      )

      test_signed_token = CsrfPlus.Token.sign_token(test_token)

      Mox.stub(CsrfPlus.StoreMock, :get_access, fn _ -> %{token: test_token} end)
      Application.put_env(:csrf_plus, CsrfPlus, store: CsrfPlus.StoreMock)

      conn =
        build_session_conn(:get)
        |> Plug.Conn.fetch_session()
        |> Plug.Conn.put_session(:access_id, "access_id")
        |> Plug.Conn.put_req_header("x-csrf-token", test_signed_token)
        |> CsrfPlus.call(CsrfPlus.init(csrf_key: :csrf_token))

      {token, signed_token} = CsrfPlus.get_token_tuple(conn)

      assert token == test_token
      assert token != "was generated here"
      assert signed_token == test_signed_token
    end

    test "if get_token_tuple/1 get a token from the store for the access_id but dont uses the token in the header when it's invalid" do
      test_token = "store token"
      test_signed_token = "wrong signed token"

      Fixtures.token_config_fixture(
        token_generation_fn: fn ->
          "was generated here"
        end
      )

      Mox.stub(CsrfPlus.StoreMock, :get_access, fn _ -> %{token: test_token} end)
      Application.put_env(:csrf_plus, CsrfPlus, store: CsrfPlus.StoreMock)

      conn =
        build_session_conn(:get)
        |> Plug.Conn.fetch_session()
        |> Plug.Conn.put_session(:access_id, "access_id")
        |> Plug.Conn.put_req_header("x-csrf-token", test_signed_token)
        |> CsrfPlus.call(CsrfPlus.init(csrf_key: :csrf_token))

      {token, signed_token} = CsrfPlus.get_token_tuple(conn)

      assert token == test_token
      assert token != "was generated here"
      assert signed_token != test_signed_token
    end

    test "if get_token_tuple/1 get a token from the store for the access_id but sign that token when the header token is not set" do
      test_token = "store token"

      Fixtures.token_config_fixture(
        token_generation_fn: fn ->
          "was generated here"
        end
      )

      Mox.stub(CsrfPlus.StoreMock, :get_access, fn _ -> %{token: test_token} end)
      Application.put_env(:csrf_plus, CsrfPlus, store: CsrfPlus.StoreMock)

      conn =
        build_session_conn(:get)
        |> Plug.Conn.fetch_session()
        |> Plug.Conn.put_session(:access_id, "access_id")
        |> CsrfPlus.call(CsrfPlus.init(csrf_key: :csrf_token))

      {token, signed_token} = CsrfPlus.get_token_tuple(conn)

      assert token == test_token
      assert token != "was generated here"
      result = CsrfPlus.Token.verify(signed_token)
      assert match?({:ok, ^token}, result)
    end
  end

  describe "CsrfPlus validations" do
    test "if the token validation fails when there is no session_id set in the request session" do
      csrf_config = CsrfPlus.init(csrf_key: :csrf_token)
      conn = build_session_req_conn(:post)

      conn =
        CsrfPlus.call(conn, csrf_config)

      assert conn.halted
      assert exception_from_conn(conn) == CsrfPlus.Exception.SessionException
    end

    test "if the validation fails when there is no token in the request headers or body_params" do
      csrf_config = CsrfPlus.init(csrf_key: :csrf_token)
      conn = build_session_req_conn(:post)

      conn =
        conn
        |> Plug.Conn.put_session(:access_id, CsrfPlus.OkStoreMock.access_id())
        |> CsrfPlus.call(csrf_config)

      assert conn.halted
      assert exception_from_conn(conn) == CsrfPlus.Exception.SignedException
    end

    test "if no SignedException is raised when sending the signed token through request header" do
      csrf_config = CsrfPlus.init(csrf_key: :csrf_token)
      conn = build_session_req_conn(:post)

      conn =
        conn
        |> Plug.Conn.put_session(:access_id, CsrfPlus.OkStoreMock.access_id())
        |> Plug.Conn.put_req_header("x-csrf-token", CsrfPlus.OkStoreMock.the_token())
        |> CsrfPlus.call(csrf_config)

      # The validation must fail, but not because the signed token is absent
      assert conn.halted
      assert exception_from_conn(conn) != CsrfPlus.Exception.SignedException
    end

    test "if no SignedException is raised when sending the signed token through request body" do
      csrf_config = CsrfPlus.init(csrf_key: :csrf_token)
      conn = build_session_req_conn(:post)

      conn =
        conn
        |> Plug.Conn.put_session(:access_id, CsrfPlus.OkStoreMock.access_id())
        |> Map.put(:body_params, %{"_csrf_token" => CsrfPlus.OkStoreMock.the_token()})
        |> CsrfPlus.call(csrf_config)

      assert conn.halted
      assert exception_from_conn(conn) != CsrfPlus.Exception.SignedException
    end

    test "if the validation fails when no token store is set" do
      csrf_config = CsrfPlus.init(csrf_key: :csrf_token)
      conn = build_session_req_conn(:post, :header)

      conn =
        conn
        |> Plug.Conn.put_session(:access_id, CsrfPlus.OkStoreMock.access_id())
        |> CsrfPlus.call(csrf_config)

      assert conn.halted
      assert exception_from_conn(conn) == CsrfPlus.Exception.StoreException
    end

    test "if the validation fails when there is no token in the connection session" do
      Mox.stub_with(CsrfPlus.StoreMock, CsrfPlus.OkStoreMock)
      Application.put_env(:csrf_plus, CsrfPlus, store: CsrfPlus.StoreMock)
      csrf_config = CsrfPlus.init(csrf_key: :csrf_token)

      conn =
        :post
        |> build_session_conn()
        |> Plug.Conn.fetch_session()
        |> Plug.Conn.put_session(:access_id, CsrfPlus.OkStoreMock.access_id())
        |> Plug.Conn.put_req_header("x-csrf-token", CsrfPlus.OkStoreMock.the_token())
        |> CsrfPlus.call(csrf_config)

      assert conn.halted
      assert exception_from_conn(conn) == CsrfPlus.Exception.SessionException
    end

    test "if the validation fails when the token in the session is different from the token in the store" do
      Mox.stub(CsrfPlus.StoreMock, :get_access, fn _ -> %UserAccess{token: "different token"} end)
      Application.put_env(:csrf_plus, CsrfPlus, store: CsrfPlus.StoreMock)
      csrf_config = CsrfPlus.init(csrf_key: :csrf_token)

      conn =
        :post
        |> build_session_req_conn(:header)
        |> Plug.Conn.put_session(:access_id, CsrfPlus.OkStoreMock.access_id())
        |> CsrfPlus.call(csrf_config)

      assert conn.halted
      assert exception_from_conn(conn) == CsrfPlus.Exception.MismatchException
    end

    test "if the validation fails when everything is ok but the token in the header is invalid" do
      Mox.stub_with(CsrfPlus.StoreMock, CsrfPlus.OkStoreMock)
      Application.put_env(:csrf_plus, CsrfPlus, store: CsrfPlus.StoreMock)
      csrf_config = CsrfPlus.init(csrf_key: :csrf_token)

      conn =
        :post
        |> build_session_req_conn()
        |> Plug.Conn.put_session(:access_id, CsrfPlus.OkStoreMock.access_id())
        |> Plug.Conn.put_req_header("x-csrf-token", "wrong token")
        |> CsrfPlus.call(csrf_config)

      assert conn.halted
      assert exception_from_conn(conn) == CsrfPlus.Exception
    end

    test "if the validation fails when everything is ok but the token in the body_params is invalid" do
      Mox.stub_with(CsrfPlus.StoreMock, CsrfPlus.OkStoreMock)
      Application.put_env(:csrf_plus, CsrfPlus, store: CsrfPlus.StoreMock)
      csrf_config = CsrfPlus.init(csrf_key: :csrf_token)

      conn =
        :post
        |> build_session_req_conn()
        |> Plug.Conn.put_session(:access_id, CsrfPlus.OkStoreMock.access_id())
        |> Map.put(:body_params, %{"_csrf_token" => "wrong token"})
        |> CsrfPlus.call(csrf_config)

      assert conn.halted
      assert exception_from_conn(conn) == CsrfPlus.Exception
    end

    test "if the validation fails when the signed token in the header is valid but does not match the session token or the store token" do
      Mox.stub(CsrfPlus.StoreMock, :get_access, fn _ -> %UserAccess{token: "different token"} end)
      Application.put_env(:csrf_plus, CsrfPlus, store: CsrfPlus.StoreMock)
      csrf_config = CsrfPlus.init(csrf_key: :csrf_token)

      conn =
        :post
        |> build_session_req_conn(:header)
        |> Plug.Conn.put_session(:access_id, CsrfPlus.OkStoreMock.access_id())
        |> Plug.Conn.put_session(:csrf_token, "different token")
        |> CsrfPlus.call(csrf_config)

      assert conn.halted
      assert exception_from_conn(conn) == CsrfPlus.Exception.MismatchException
    end

    test "if the validation fails when the signed token in the body_params is valid but does not match the session token or the store token" do
      Mox.stub(CsrfPlus.StoreMock, :get_access, fn _ -> %UserAccess{token: "different token"} end)
      Application.put_env(:csrf_plus, CsrfPlus, store: CsrfPlus.StoreMock)
      csrf_config = CsrfPlus.init(csrf_key: :csrf_token)

      conn =
        :post
        |> build_session_req_conn(:body)
        |> Plug.Conn.put_session(:access_id, CsrfPlus.OkStoreMock.access_id())
        |> Plug.Conn.put_session(:csrf_token, "different token")
        |> CsrfPlus.call(csrf_config)

      assert conn.halted
      assert exception_from_conn(conn) == CsrfPlus.Exception.MismatchException
    end

    test "if the validation succeeds when all the tokens are valid and matches each other, being the signed token in the request header" do
      Mox.stub_with(CsrfPlus.StoreMock, CsrfPlus.OkStoreMock)
      Application.put_env(:csrf_plus, CsrfPlus, store: CsrfPlus.StoreMock)
      csrf_config = CsrfPlus.init(csrf_key: :csrf_token)

      conn =
        :post
        |> build_session_req_conn(:header)
        |> Plug.Conn.put_session(:access_id, CsrfPlus.OkStoreMock.access_id())
        |> CsrfPlus.call(csrf_config)

      refute conn.halted
    end

    test "if the validation succeeds when all the tokens are valid and matches each other, being the signed token in the request body" do
      Mox.stub_with(CsrfPlus.StoreMock, CsrfPlus.OkStoreMock)
      Application.put_env(:csrf_plus, CsrfPlus, store: CsrfPlus.StoreMock)
      csrf_config = CsrfPlus.init(csrf_key: :csrf_token)

      conn =
        :post
        |> build_session_req_conn(:body)
        |> Plug.Conn.put_session(:access_id, CsrfPlus.OkStoreMock.access_id())
        |> CsrfPlus.call(csrf_config)

      refute conn.halted
    end
  end
end
