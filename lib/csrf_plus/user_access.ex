defmodule CsrfPlus.UserAccess do
  @moduledoc """
  Represents an user access. This struct is where you can set a token and other user access related informations.
  """

  defstruct token: nil, access_id: nil, expired?: false, user_info: nil, created_at: nil

  @typedoc """
  The UserAccess type:

    * `:token` - The token of the access.
    * `:access_id` - A unique id to identify the access.
    * `:expired?` - A flag indicating if the access is expired or not.
    * `:user_info` - The user access information. See more at `CsrfPlus.UserAccessInfo`.
    * `:created_at` - The time stamp in milliseconds of the access creation.
  """
  @type t :: %__MODULE__{
          token: String.t(),
          access_id: String.t(),
          expired?: boolean(),
          user_info: UserAccessInfo.t(),
          created_at: non_neg_integer() | nil
        }
end
