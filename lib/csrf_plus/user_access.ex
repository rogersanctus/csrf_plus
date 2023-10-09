defmodule CsrfPlus.UserAccess do
  defstruct token: nil, access_id: nil, expired?: false, user_info: nil, created_at: nil

  @type t :: %__MODULE__{
          token: String.t(),
          access_id: String.t(),
          expired?: boolean(),
          user_info: UserAccessInfo.t(),
          created_at: non_neg_integer() | nil
        }
end
