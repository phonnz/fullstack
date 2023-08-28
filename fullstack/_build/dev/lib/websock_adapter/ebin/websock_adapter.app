{application,websock_adapter,
             [{optional_applications,[bandit,plug_cowboy]},
              {applications,[kernel,stdlib,elixir,websock,plug,bandit,
                             plug_cowboy]},
              {description,"A set of WebSock adapters for common web servers"},
              {modules,['Elixir.WebSockAdapter',
                        'Elixir.WebSockAdapter.CowboyAdapter']},
              {registered,[]},
              {vsn,"0.5.4"}]}.
