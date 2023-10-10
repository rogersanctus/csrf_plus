# CsrfPlus
A plug-based CSRF (Cross-Site Request Forgery) protection Plug with accesses storing support.

Sometimes you need more than a per-request CSRF tokens. This is why this Plug was created.
This plug supports storing tokens in any kind of storage system. And all you have to do is to
implement its `CsrfPlus.Store.Behaviour`. By doing so you will provide ways to put, get,
delete and other operations of accesses on that 'Store'.

# How it works?
When a request is made, this plug will check the request method type. Request methods intended
for reading data (GET, HEAD, OPTIONS) will be ignored, by default. The other requests will be
checked against the CSRF token stored in the connection session, in the `x-csrf-token` header
and the one stored in the configured Store. All those tokens must match to a token be
considered valid. The first checkings are to ensure the tokens are given. Then, the token in
the session and the one in the Store are verified against each other. Later, the token on the
`x-csrf-token` header that is a signed version of the generated token with the configured secret
key will be verified against that secret key. If this verification succeeds, the returned verified
token will be checked against the token in the store. If this verification also succeeds, the
connection continues normally. Otherwise, an exception will be raised and be used to make the
error message and response status code.

# Usage
You can use CsrfPlus as a plug in your endpoint, router or in some plug pipeline. As this plug
uses connection session, it must be plugged after `Plug.Session` and `Plug.Conn.fetch_session/2`.
Also, this plug won't check requests origin. So, to have safer connections, use some CORS lib of
your choice before CsrfPlus. A good choice is the [Corsica](https://github.com/whatyouhide/corsica) project.

# How to install?
Simple, add `:csrf_plus` to you mix dependencies:

```elixir
# mix.exs
def deps do
  [
    {:plug, "~> 1.0"},
    {:csrf_plus, "~> 0.1"}
  ]
```

And then run `$ mix deps.get`.

# Setting it up

## Configs
`CsrfPlus` uses some configurations to get ready to run.

### Token module
This module is responsible to generate and verify tokens.
You can create your own Token module, since you implements the `CsrfPlus.Token` behaviour.

This lib comes with a 'DefaultToken' module, that is used for that. But if you
want to set a custom Token module, use the config:

```elixir
# config/config.exs
config :csrf_plus, CsrfPlus.Token, token_mod: YourTokenModule
```

When using the 'DefaultToken', you can define the function to be used to generate tokens
or use the default one.
To config the token generator function add the following to your config:

```elixir
# config/config.exs
config :csrf_plus, CsrfPlus.Token, token_generation_fn: &your_function/0
```

Such a function must return a string (binary) that is the token itself. That
token must be unique.

Yet, if you want to use the 'DefaultToken' module, you should set the
`:secret_key` to be used to generate and verify tokens. That key must be at least 64
bytes long.

Config with:

```elixir
# config/config.exs
config :csrf_plus, CsrfPlus.Token, secret_key: "a_good_strong_random_secret"
```

Please note that this `:secret_key` is only needed if you are using the 'DefaultToken'
module.

### Store module
In short, the store module is the module that implements the Store behaviour
and will keep your generated tokens ready to be checked against. If any served
token is not on the store, it is considered as invalid. For more information about
Stores look at the `CsrfPlu.Store.Behaviour` module.
To config the used store module, add the following:

```elixir
# config/config.exs
config :csrf_plus, CsrfPlus, store: YourStoreModule
```

There is no store set by default. But if you don't care about that, you can use
the builtin `CsrfPlus.Store.MemoryDb` store. As it names suggests, it will store
tokens (accesses, actually) in memory, using a `GenServer`.

If so, do:

```elixir
# config/config.exs
config :csrf_plus, CsrfPlus, store: CsrfPlus.Store.MemoryDb 
```

## Options
The `CsrfPlus` plug accepts some options at its initialization.
The following options are available:

`:csrf_key` - The key under the token is stored in the connection session. Defaults to: `"_csrf_key_"`

`:allowed_methods` - The requests methods that are ignored by the CSRF token validations.
By defaut: `["GET", "HEAD", "OPTIONS"]`.

`:error_mapper` - The module to be used to map exceptions to response status codes and error messages.
There is a default module for that: `CsrfPlus.ErrorMapper`. But you can set your own module
since it implements the `CsrfPlus.ErrorMapper` behaviour.

## Supervisor
As the CSRF validation of this lib uses a store of tokens, it's a good practice to
let them have a life span. And to keep the Store of tokens updated by this rule, we
use a store manager `CsrfPlus.Store.Manager` that will check all the tokens in the store
and flag the expired tokens as so. That Manager can be started directly, but to make it
easier to use with the default `CsrfPlus.Store.MemoryDb` store, we provide a `CsrfPlus.Supervisor` that
will not only start them, but also keep them up.

To start the Supervisor include the following entry in your application start function:

```elixir
# application.ex
def start(_type, _args) do
  #...

  children = [
    #...
    {CsrfPlus.Supervisor, opts}
    #...
  ]

  #...
end
```

Replace opts by the options you want to set for the `CsrfPlus.Store.Manager`.
For more information about the options look at the module documentation.
