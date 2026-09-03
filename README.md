# Datem

Multi-tenant visitor access management and event ticketing, built on GS1
identification standards. See [project.md](project.md) for the overview and
[tasks.md](tasks.md) for the build breakdown.

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Demo data

```bash
mix ecto.reset    # create the database and seed the demo organisation
mix demo          # scripted end-to-end run: register → QR → scan in → lunch → scan out
```

Log in as `owner@datem.test` / `datem-demo-password` (also `admin@`, `operator@`
and `viewer@` for the other roles).

## Documentation

* [Admin guide](docs/admin-guide.md)
* [Operator scanning guide](docs/operator-scanning-guide.md)
* [GS1 prefix setup guide](docs/gs1-prefix-setup.md)

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
