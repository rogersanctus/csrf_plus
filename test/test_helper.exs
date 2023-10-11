ExUnit.start()

Mox.defmock(CsrfPlus.StoreMock, for: CsrfPlus.Store.Behaviour)

Mox.defmock(CsrfPlus.OptionalStoreMock,
  for: CsrfPlus.Store.Behaviour,
  skip_optional_callbacks: true
)
