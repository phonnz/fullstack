defmodule FullstackWeb.AboutHTML do
  use FullstackWeb, :html

  embed_templates "about_html/*"

  def index(assigns) do
    ~H"""
    <div class="container px-4 py-8 mx-auto">
      <h1 class="mb-8 text-3xl font-bold text-center text-gray-800">Happy Demos!</h1>
      <div class="grid grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-3">
        <a href="/" class="block group">
          <div class="overflow-hidden relative bg-white rounded-lg shadow-md transition-all duration-300 hover:shadow-xl">
            <div class="relative">
              <img src="https://placehold.co/600x400/png" alt="Phoenix Project" class="object-cover w-full h-48"/>
              <div class="absolute inset-0 bg-gradient-to-t opacity-0 transition-opacity duration-300 from-black/80 to-black/0 group-hover:opacity-100"></div>
            </div>
            <h2 class="p-4 text-xl font-semibold text-gray-800">FullStack Phoenix Project</h2>
            <div class="flex absolute inset-0 items-end opacity-0 transition-opacity duration-300 group-hover:opacity-100">
              <div class="p-8 text-white">
                <p class="mb-10 text-sm leading-relaxed">
                  A comprehensive Phoenix application showcasing full-stack development capabilities with modern web technologies.
                </p>
              </div>
            </div>
          </div>
        </a>

        <a href={~p"/chat"} class="block group">
          <div class="overflow-hidden relative bg-white rounded-lg shadow-md transition-all duration-300 hover:shadow-xl">
            <div class="relative">
              <img src="https://placehold.co/600x400/png" alt="Chat Application" class="object-cover w-full h-48"/>
              <div class="absolute inset-0 bg-gradient-to-t opacity-0 transition-opacity duration-300 from-black/80 to-black/0 group-hover:opacity-100"></div>
            </div>
            <h2 class="p-4 text-xl font-semibold text-gray-800">Chat Application</h2>
            <div class="flex absolute inset-0 items-end opacity-0 transition-opacity duration-300 group-hover:opacity-100">
              <div class="p-8 text-white">
                <p class="mb-10 text-sm leading-relaxed">
                  Real-time chat application built with Phoenix LiveView, enabling instant communication and updates.
                </p>
              </div>
            </div>
          </div>
        </a>
        <a href={~p"/fibonacci"} class="block group">
          <div class="overflow-hidden relative bg-white rounded-lg shadow-md transition-all duration-300 hover:shadow-xl">
            <div class="relative">
              <img src="https://placehold.co/600x400/png" alt="Dashboard Sample" class="object-cover w-full h-48"/>
              <div class="absolute inset-0 bg-gradient-to-t opacity-0 transition-opacity duration-300 from-black/80 to-black/0 group-hover:opacity-100"></div>
            </div>
            <h2 class="p-4 text-xl font-semibold text-gray-800">Fibonacci</h2>
            <div class="flex absolute inset-0 items-end opacity-0 transition-opacity duration-300 group-hover:opacity-100">
              <div class="p-8 text-white">
                <p class="mb-10 text-sm leading-relaxed">
                  Fibonacci examples.
                </p>
              </div>
            </div>
          </div>
        </a>
        <a href={~p"/transactions"} class="block group">
          <div class="overflow-hidden relative bg-white rounded-lg shadow-md transition-all duration-300 hover:shadow-xl">
            <div class="relative">
              <img src="https://placehold.co/600x400/png" alt="Dashboard Sample" class="object-cover w-full h-48"/>
              <div class="absolute inset-0 bg-gradient-to-t opacity-0 transition-opacity duration-300 from-black/80 to-black/0 group-hover:opacity-100"></div>
            </div>
            <h2 class="p-4 text-xl font-semibold text-gray-800">Basic Dashboard Sample</h2>
            <div class="flex absolute inset-0 items-end opacity-0 transition-opacity duration-300 group-hover:opacity-100">
              <div class="p-8 text-white">
                <p class="mb-10 text-sm leading-relaxed">
                  Interactive dashboard displaying transaction data with filtering and sorting capabilities.
                </p>
                <h2 class="mb-2 text-xl font-semibold">Basic Dashboard Sample</h2>
              </div>
            </div>
          </div>
        </a>
      </div>
    </div>
    """
  end
end
