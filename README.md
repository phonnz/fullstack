# FullStack

After been building infrastructure for millions of IoT devices connected to a Phoenix Backend, sending data and enable people to track everything soft real-time with Liveview and provide services to third-parties from APIs, I decided to share the knowledge with the community.

I had the chance to work in several Elixir projects, but most of the experience and knowledge came from building a product and the journey was shared at ElixirConf US 2023
[![ElixirConf US 2023]](https://www.youtube.com/watch?v=YWDCXbjircQ)

[![Watch the demo](./static/thumbnail.jpg)](https://www.youtube.com/watch?v=ZMFXT9YDu-o)

I have seen lot of times this table from "Elixir in Action" book, and want to show how wasy is to enable this features in a real system. 

![plot](./static/erlang_features.png)

## The abstract idea 
![plot](./static/idea.png)
Elixir, Erlang, OTP,the BEAM,Phoenix & Liveview and Nerves, is an amazing stack to build a rea-time distributed IoT platform.

## Key components from the Web Framework
```mermaid
flowchart TD
    J["Endpoint"] <--> F["Router"]
    F <-- Handles Requests --> C("Cowboy - (HTTP & WebSocket)")
    A["LiveView (reactive controller)"] <-- Monitor current Connections --> B["Presence"]
    E("PubSub - (Message Queue)") --> A
    A <-- serves --> C
    A <--> D["Business Logic API Layer"]
    E <-- broadcast --> D
    D <-- Caches Data --> H("ETS - (In-Memory Key-Value Store)")
    D <-- Handles --> G("GenServers - (Background Job)") & I("Task - (Long Running Request)")

    style J fill:#e85102,stroke:#ccc,stroke-width:2px,color:#FFFFFF
    style F fill:#e85102,stroke:#ccc,stroke-width:2px,color:#FFFFFF
    style C fill:#e85102,stroke:#ccc,stroke-width:2px,color:#FFFFFF
    style A fill:#e85102,stroke:#ccc,stroke-width:2px,color:#FFFFFF
    style B fill:#e85102,stroke:#ccc,stroke-width:2px,color:#FFFFFF
    style E fill:#e85102,stroke:#ccc,stroke-width:2px,color:#FFFFFF
    style D fill:#8205a8,stroke:#ccc,stroke-width:2px,color:#FFFFFF
    style H fill:#a80513,stroke:#ccc,stroke-width:2px,color:#FFFFFF
    style G fill:#a80513,stroke:#ccc,stroke-width:2px,color:#FFFFFF
    style I fill:#a80513,stroke:#ccc,stroke-width:2px,color:#FFFFFF
    linkStyle 0 stroke:#757575
```





