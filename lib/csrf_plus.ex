defmodule CsrfPlus do
  @moduledoc """
  A CSRF (Cross-Site Request Forgery) protection Plug with accesses storing support.
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

  @doc false
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

  @doc false
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
          put_session_token: fn conn, access_id, token ->
            csrf_token = opts.csrf_key

            conn =
              if access_id == nil do
                conn
              else
                put_session(conn, :access_id, access_id)
              end

            put_session(conn, csrf_token, token)
          end,
          put_header_token: fn conn, _access_id, signed_token ->
            Plug.Conn.put_resp_header(conn, "x-csrf-token", signed_token)
          end,
          put_store_token: fn conn, access_id, token ->
            store = Map.get(opts, :store)

            if store != nil do
              access =
                if Kernel.function_exported?(store, :conn_to_access, 2) do
                  store.conn_to_access(conn, %{token: token, access_id: access_id})
                else
                  %UserAccess{}
                  |> Map.put(:access_id, access_id)
                  |> Map.put(:token, token)
                end

              store.put_access(access)
            end

            conn
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

            reraise exception, __STACKTRACE__
          end
        else
          reraise exception, __STACKTRACE__
        end
    end
  end

  @doc "Digs into the connection data to make an user access information struct."
  def get_user_info(conn) do
    %UserAccessInfo{
      ip: get_conn_ip(conn),
      user_agent: get_conn_user_agent(conn)
    }
  end

  @doc "The default max age for a token"
  def default_token_max_age do
    @default_token_max_age
  end

  @doc """
  Uses the plug configuration to put the token and its signed version
  into the store, session and `x-csrf-token` header.

  This function uses the functions: `put_session_token/3`, `put_header_token/2` and `put_store_token/3`
  base functions under the hood. So, you can have a look at them for more information about how this function works.

  ## Params
    * `conn` - The connection struct.
    * `opts` - The options.

  ### Options
    The options is a Keyword with the follwing keys:

    * `:access_id` - the id of the access. If none is given CsrfPlus will generate one.
    * `:token_tuple` - a tuple with the token and its signed version in the format `{token, signed_token}`. This option is required.
    * `:excludes` - a list of tokens to exclude. A excluded token will not
    be put into its corresponding store, session or header.

  ### Excludes list
    * `:session` - do not put the session token.
    * `:header` - do not put the header token.
    * `:store` - do not put the store token.

  """
  def put_token(%Plug.Conn{} = conn, opts \\ []) do
    access_id = Keyword.get(opts, :access_id, UUID.uuid4())

    token_tuple =
      Keyword.get(opts, :token_tuple) ||
        raise CsrfPlus.Exception,
              "CsrfPlus.put_token/2 options requires a :token_tuple to be given"

    {token, signed_token} = token_tuple

    excludes = Keyword.get(opts, :excludes, [])
    excludes_session_token? = Keyword.get(excludes, :session, false)
    excludes_header_token? = Keyword.get(excludes, :header, false)
    excludes_store_token? = Keyword.get(excludes, :store, false)

    conn
    |> put_a_token_optional(access_id, token, :session, excludes_session_token?)
    |> put_a_token_optional(access_id, signed_token, :header, excludes_header_token?)
    |> put_a_token_optional(access_id, token, :store, excludes_store_token?)
  end

  @doc """
  Put the token and the given `access_id` in the session. Uses the conn struct to
  determine the needed keys.

  ## Params
  * `conn` - the connection struct.
  * `token` - the CSRF unsigned token.
  * `access_id` - the access id. If none is given no access id is put in the session. Defaults to nil.

  """
  def put_session_token(conn, token, access_id \\ nil) do
    put_a_token(conn, access_id, token, :session)
  end

  @doc """
  Put the token in the header. It uses the conn struct to determine the header name.

  ## Params
  * `conn` - the connection struct.
  * `signed_token` - the signed version of the CSRF token.

  """
  def put_header_token(conn, signed_token) do
    put_a_token(conn, nil, signed_token, :header)
  end

  @doc """
  Put the token in the store. If a `conn_to_access` function is implemented in the
  configured store, that function will be called with the given params to generate
  the `CsrfPlus.UserAccess` to be put into the store. Also, have a look at `CsrfPlus.Store.Behaviour`
  to see more about `conn_to_access` callback.

  ## Params
  * `conn` - the connection struct.
  * `token` - the CSRF unsigned token.
  * `access_id` - the access id. It's required here because a token must be associeted with an identifier.

  """
  def put_store_token(_conn, _token, nil),
    do:
      raise(
        CsrfPlus.Exception,
        "CsrfPlus.put_store_token/3 requires the access_id parameter to be given"
      )

  def put_store_token(conn, token, access_id) do
    put_a_token(conn, access_id, token, :store)
  end

  defp put_a_token_optional(conn, access_id, token, what, false) do
    put_a_token(conn, access_id, token, what)
  end

  defp put_a_token_optional(conn, _access_id, _token, _what, true) do
    conn
  end

  defp put_a_token(%Plug.Conn{private: private} = conn, access_id, token, what) do
    state = Map.get(private, :plug_csrf_plus, %{})
    put_session_token = Map.get(state, :put_session_token, nil)
    put_header_token = Map.get(state, :put_header_token, nil)
    put_store_token = Map.get(state, :put_store_token, nil)

    fun =
      case what do
        :session ->
          put_session_token

        :header ->
          put_header_token

        :store ->
          put_store_token
      end

    if fun == nil do
      raise CsrfPlus.Exception,
            "CsrfPlus.put_token/3 must be called after CsrfPlus is plugged"
    else
      fun.(conn, access_id, token)
    end
  end

  defp allowed_method?(
         %Plug.Conn{method: method},
         %{allowed_methods: allowed_methods} = _opts
       ) do
    method in allowed_methods
  end

  defp check_token(%Plug.Conn{} = conn, true = _allowed_method?, _opts) do
    conn
  end

  defp check_token(%Plug.Conn{body_params: body_params} = conn, false = _allowed_method?, opts) do
    access_id = get_session(conn, :access_id)

    header_token =
      conn
      |> get_req_header("x-csrf-token")
      |> Enum.at(0)

    body_token = Map.get(body_params, "_csrf_token", nil)

    cond do
      is_nil(access_id) ->
        raise CsrfPlus.Exception, {CsrfPlus.Exception.SessionException, :missing_id}

      header_token == nil && body_token == nil ->
        raise CsrfPlus.Exception, CsrfPlus.Exception.SignedException

      true ->
        store = Map.get(opts, :store)
        signed_token = header_token || body_token

        check_token_store(conn, store, {opts, access_id, signed_token})
    end
  end

  defp check_token_store(_conn, nil, _to_check) do
    Logger.debug("CsrfPlus: No token store configured")

    raise CsrfPlus.Exception, CsrfPlus.Exception.StoreException
  end

  defp check_token_store(conn, store, {opts, access_id, signed_token}) do
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
        result = Token.verify(signed_token)
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
