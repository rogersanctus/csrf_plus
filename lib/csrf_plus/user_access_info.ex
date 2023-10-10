defmodule CsrfPlus.UserAccessInfo do
  @moduledoc """
  Defines a basic user access information containing the ip and the user agent.
  """

  defstruct ip: "", user_agent: ""

  @typedoc """
  The User access information.

    * `:ip` - The most trustable IP address you can get.
    * `:user_agent` - The user agent string of the requests.
  """
  @type t :: %__MODULE__{
          ip: String.t(),
          user_agent: String.t()
        }

  @doc "Converts a JSON object string with `:ip` and `:user_agent` fields into a `CsrfPlus.UserAccessInfo` struct."
  def user_info_from_string(user_info) when is_binary(user_info) do
    user_info
    |> Jason.decode!()
    |> user_info_from_map()
  end

  @doc "Converts a `CsrfPlus.UserAccessInfo` struct into a JSON object string."
  def user_info_to_string(%__MODULE__{ip: ip} = user_info) do
    ip = CsrfPlus.IpHelper.normalize_ip!(ip)

    user_info
    |> Map.put(:ip, ip)
    |> Map.delete(:__struct__)
    |> Jason.encode!()
  end

  @doc "Will convert a raw map with `:ip` and `:user_agent` into a `CsrfPlus.UserAccessInfo` struct."
  def user_info_from_map(%{} = map) do
    map
    |> Enum.reduce(%__MODULE__{}, fn {k, v}, acc -> Map.put(acc, String.to_atom(k), v) end)
  end
end
