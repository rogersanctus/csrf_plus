defmodule CsrfPlus do
  @moduledoc """
  A CSRF (Cross-Site Request Forgery) protection Plug with accesses storing support.

  Sometimes you need more than a per-request CSRF tokens. This is why this Plug was created.
  This plug supports storing tokens in any kind of storage system. And all you have to do is to
    implement its 'CsrfPlus.Store.Behaviour'. By doing so you will provide ways to put, get,
    delete and other operations of accesses on that 'Store'.

  # How it works?
    When a request is made, this plug will check the request method type. Request methods intended
    for reading data (GET, HEAD, OPTIONS) will be ignored, by default. The other requests will be
    checked against the CSRF token stored in the connection session, in the 'x-csrf-token' header
    and the one stored in the configured Store. All those tokens must match to a token be
    considered valid. The first checkings are to ensure the tokens are given. Then, the token in
    the session and the one in the Store are verified against each other. Later, the token on the
    'x-csrf-token' header that is a signed version of the generated token with the configured secret
    key will be verified against that secret key. If this verification succeeds, the returned verified
    token will be checked against the token in the store. If this verification also succeeds, the
    connection continues normally. Otherwise, an exception will be raised and be used to make the
    error message and response status code.

  # Usage
    You can use CsrfPlus as a plug in your endpoint, router or in some plug pipeline. As this plug
    uses connection session, it must be plugged after `Plug.Session` and `Plug.Conn.fetch_session`.
    Also, this plug won't check requests origin. So, to have safer connections, use some CORS lib of
    your choice before CsrfPlus. A good choice is the [Corsica](https://github.com/whatyouhide/corsica) project.
    
  # How to install?
    Simple, add :csrf_plus to you mix dependencies:

    `mix.exs:`
    ```elixir
    def deps do
      [
        {:plug, "~> 1.0"},
        {:csrf_plus, "~> 0.1"}
      ]
    ```

    And then run `$ mix deps.get`.
  """

  @behaviour Plug

  alias CsrfPlus.UserAccess
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

    error_mapper = Keyword.get(opts, :error_mapper, CsrfPlus.ErrorMapper)

    store =
      :csrf_plus
      |> Application.get_env(CsrfPlus, [])
      |> Keyword.get(:store)

    %{
      csrf_key: csrf_key,
      allowed_methods: allowed_methods,
      error_mapper: error_mapper,
      store: store
    }
  end

  def call(%Plug.Conn{halted: true} = conn, _opts) do
    conn
  end

  def call(%Plug.Conn{} = conn, opts) do
    allowed_method? = allowed_method?(conn, opts)

    try do
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
    rescue
      exception ->
        if CsrfPlus.Exception.csrf_plus_exception?(exception) do
          error_mapper = opts.error_mapper

          # Ensure the configured error mapper module is compiled
          # BEWARE as this function call may lead to deadlocks.
          module_compiled = Code.ensure_compiled(error_mapper)

          if match?({:module, _}, module_compiled) &&
               Kernel.function_exported?(error_mapper, :map, 1) do
            {status_code, error} = error_mapper.map(exception)

            # After any CSRF exception, must clear session and return the mapped error and status code
            conn
            |> delete_session(:access_id)
            |> delete_session(opts.csrf_key)
            |> send_resp(status_code, Jason.encode!(error))
            |> halt()
          else
            Logger.debug(
              "The given error_mapper #{inspect(error_mapper)} does not exist or doesn't implements the map/1 function"
            )

            raise exception
          end
        else
          raise exception
        end
    end
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
      raise CsrfPlus.Exception,
            "CsrfPlus.put_session_token/2 must be called after CsrfPlus is plugged"
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
        raise CsrfPlus.Exception, {CsrfPlus.Exception.SessionException, :missing_id}

      header_token == nil ->
        raise CsrfPlus.Exception, CsrfPlus.Exception.HeaderException

      true ->
        store = Map.get(opts, :store)

        check_token_store(conn, store, {opts, access_id, header_token})
    end
  end

  defp check_token_store(_conn, nil, _to_check) do
    Logger.debug("CsrfPlus: No token store configured")

    raise CsrfPlus.Exception, CsrfPlus.Exception.StoreException
  end

  defp check_token_store(conn, store, {opts, access_id, header_token}) do
    csrf_key = Map.get(opts, :csrf_key, nil)
    store_access = store.get_access(access_id)
    store_token = Map.get(store_access || %{}, :token, nil)
    session_token = get_session(conn, csrf_key)

    cond do
      session_token == nil ->
        Logger.debug("Missing token in the request session")

        raise CsrfPlus.Exception, CsrfPlus.Exception.SessionException

      store_access == nil ->
        Logger.debug("The access with id: #{access_id} was not found")

        raise CsrfPlus.Exception, {CsrfPlus.Exception.StoreException, :token_not_found}

      match?(%UserAccess{expired?: true}, store_access) ->
        Logger.debug("The access with id: #{access_id} has expired")

        raise CsrfPlus.Exception, {CsrfPlus.Exception.StoreException, :token_expired}

      session_token != store_token ->
        Logger.debug(
          "Token mismatch session:#{inspect(session_token)} != store:#{inspect(store_token)}"
        )

        raise CsrfPlus.Exception, CsrfPlus.Exception.MismatchException

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

      raise CsrfPlus.Exception, CsrfPlus.Exception.MismatchException
    else
      conn
    end
  end

  defp check_token_store_verified(_conn, {:error, error}, _store_token) do
    Logger.debug("Token validation error: #{inspect(error)}")

    raise CsrfPlus.Exception, error
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
