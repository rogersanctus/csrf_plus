defmodule CsrfPlus do
  @moduledoc false
  @behaviour Plug

  alias CsrfPlus.Token
  alias CsrfPlus.UserAccessInfo
  require Logger

  @default_csrf_key "_csrf_token_"
  @non_csrf_request_methods ["GET", "HEAD", "OPTIONS"]

  # Max token age in milliseconds
  @default_token_max_age 24 * 60 * 60 * 1000

  import Plug.Conn

  def init(opts \\ []) do
    csrf_key = Keyword.get(opts, :csrf_key, @default_csrf_key)

    allowed_methods = Keyword.get(opts, :allowed_methods, @non_csrf_request_methods)

    store = Keyword.get(opts, :store)

    %{
      csrf_key: csrf_key,
      allowed_methods: allowed_methods,
      store: store
    }
  end

  def call(%Plug.Conn{halted: true} = conn, _opts) do
    conn
  end

  def call(%Plug.Conn{} = conn, opts) do
    allowed_method? = allowed_method?(conn, opts)

    conn
    |> put_private(
      :plug_csrf_plus,
      %{
        put_session_token: fn conn, token ->
          csrf_token = opts.csrf_key
          Plug.Conn.put_session(conn, csrf_token, token)
        end
      }
    )
    |> check_token(allowed_method?, opts)
  end

  def get_user_info(conn) do
    %UserAccessInfo{
      ip: get_conn_ip(conn),
      user_agent: get_conn_user_agent(conn)
    }
  end

  def default_token_max_age do
    @default_token_max_age
  end

  def put_session_token(%Plug.Conn{private: private} = conn, token) do
    state = Map.get(private, :plug_csrf_plus, %{})
    fun = Map.get(state, :put_session_token, nil)

    if fun == nil do
      raise "CsrfPlus.put_session_token/2 must be called after CsrfPlus is plugged"
    else
      fun.(conn, token)
    end
  end

  defp allowed_method?(
         %Plug.Conn{method: method},
         %{allowed_methods: allowed_methods} = _opts
       ) do
    method in allowed_methods
  end

  def check_token(%Plug.Conn{} = conn, true = _allowed_method?, _opts) do
    conn
  end

  def check_token(%Plug.Conn{} = conn, false = _allowed_method?, opts) do
    access_id = get_session(conn, :access_id)

    header_token =
      conn
      |> get_req_header("x-csrf-token")
      |> Enum.at(0)

    cond do
      is_nil(access_id) ->
        conn
        |> send_resp(:unauthorized, Jason.encode!(%{error: "Missing access_id in the session"}))
        |> halt()

      header_token == nil ->
        conn
        |> send_resp(
          :unauthorized,
          Jason.encode!(%{error: "Missing token in the request header"})
        )
        |> halt()

      true ->
        store = Map.get(opts, :store)

        check_token_store(conn, store, {opts, access_id, header_token})
    end
  end

  defp check_token_store(conn, nil, _to_check) do
    Logger.debug("CsrfPlus: No token store configured")

    conn
    |> send_resp(:unauthorized, Jason.encode!(%{error: "No token store configured"}))
    |> halt()
  end

  defp check_token_store(conn, store, {opts, access_id, header_token}) do
    csrf_key = Map.get(opts, :csrf_key, nil)
    store_access = store.get_access(access_id)
    store_token = Map.get(store_access || %{}, :token, nil)
    session_token = get_session(conn, csrf_key)

    cond do
      session_token == nil ->
        Logger.debug("Missing token in the request session")

        send_resp(conn, :unauthorized, Jason.encode!(%{error: "Missing token in the session"}))
        |> halt()

      session_token != store_token ->
        Logger.debug(
          "Token mismatch session:#{inspect(session_token)} != store:#{inspect(store_token)}"
        )

        send_resp(conn, :unauthorized, Jason.encode!(%{error: "Invalid token"}))
        |> halt()

      true ->
        result = Token.verify(header_token)
        check_token_store_verified(conn, result, store_token)
    end
  end

  defp check_token_store_verified(conn, {:ok, verified_token}, store_token) do
    if verified_token != store_token do
      Logger.debug(
        "Token mismatch: verified_token:#{inspect(verified_token)} != store_token:#{inspect(store_token)}"
      )

      send_resp(conn, :unauthorized, Jason.encode!(%{error: "Invalid token"}))
      |> halt()
    else
      conn
    end
  end

  defp check_token_store_verified(conn, {:error, error}, _store_token) do
    Logger.debug("Token validation error: #{inspect(error)}")

    send_resp(conn, :unauthorized, Jason.encode!(%{error: error}))
    |> halt()
  end

  defp get_conn_ip(%Plug.Conn{remote_ip: remote_ip, req_headers: req_headers}) do
    [x_real_ip | _] = List.keyfind(req_headers, "x-real-ip", 0, [nil])
    [x_forwarded_for | _] = List.keyfind(req_headers, "x-forwarded-for", 0, [nil])

    case {remote_ip, x_real_ip, x_forwarded_for} do
      {nil, nil, nil} ->
        nil

      {nil, nil, x_forwarded_for} ->
        x_forwarded_for

      {nil, x_real_ip, nil} ->
        x_real_ip

      {remote_ip, nil, nil} ->
        remote_ip
    end
  end

  defp get_conn_user_agent(%Plug.Conn{} = conn) do
    user_agent = get_req_header(conn, "user-agent")

    if Enum.empty?(user_agent) do
      nil
    else
      hd(user_agent)
    end
  end
end
