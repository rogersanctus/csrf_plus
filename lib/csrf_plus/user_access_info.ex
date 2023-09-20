defmodule CsrfPlus.UserAccessInfo do
  @moduledoc false

  defstruct ip: "", user_agent: ""

  @type t :: %__MODULE__{
          ip: String.t(),
          user_agent: String.t()
        }

  def user_info_from_string(user_info) when is_binary(user_info) do
    user_info
    |> Jason.decode!()
    |> user_info_from_map()
  end

  def user_info_to_string(%__MODULE__{ip: ip} = user_info) do
    ip = CsrfPlus.IpHelper.normalize_ip!(ip)

    user_info
    |> Map.put(:ip, ip)
    |> Map.delete(:__struct__)
    |> Jason.encode!()
  end

  def user_info_from_map(%{} = map) do
    map
    |> Enum.reduce(%__MODULE__{}, fn {k, v}, acc -> Map.put(acc, String.to_atom(k), v) end)
  end
end
