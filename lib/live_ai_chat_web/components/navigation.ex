defmodule LiveAiChatWeb.Components.Navigation do
  @moduledoc """
  Navigation component for switching between Chat and Knowledge pages.
  Provides a clean, modern navigation bar with visual indicators.
  """
  use Phoenix.Component
  use LiveAiChatWeb, :verified_routes

  attr :current_page, :atom, required: true, doc: "The current page (:chat or :knowledge)"
  attr :current_user, :map, default: nil, doc: "The currently logged in user"

  def navigation_bar(assigns) do
    ~H"""
    <nav class="bg-white border-b border-gray-200 shadow-sm">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="flex justify-between h-16">
          <div class="flex items-center">
            <!-- Logo/Brand -->
            <div class="flex-shrink-0 flex items-center">
              <div class="flex items-center justify-center rounded-lg text-indigo-700 bg-indigo-100 h-8 w-8">
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M7 8h10M7 12h4m1 8l-4-4H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-3l-4 4z"
                  >
                  </path>
                </svg>
              </div>
              <span class="ml-2 text-xl font-bold text-gray-900">LiveAiChat</span>
            </div>

    <!-- Navigation Items -->
            <div class="ml-8 flex space-x-1">
              <!-- Chat Tab -->
              <.link
                navigate={~p"/"}
                class={[
                  "inline-flex items-center px-4 py-2 text-sm font-medium rounded-lg transition-all duration-200",
                  @current_page == :chat && "bg-indigo-100 text-indigo-700 shadow-sm",
                  @current_page != :chat && "text-gray-600 hover:text-gray-900 hover:bg-gray-50"
                ]}
              >
                <svg class="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-3.582 8-8 8a8.013 8.013 0 01-7-4L3 20l4-4a8.003 8.003 0 01-1-4c0-4.418 3.582-8 8-8s8 3.582 8 8z"
                  >
                  </path>
                </svg>
                Chat
                <%= if @current_page == :chat do %>
                  <div class="ml-2 w-2 h-2 bg-indigo-500 rounded-full"></div>
                <% end %>
              </.link>

    <!-- Knowledge Tab -->
              <.link
                navigate={~p"/knowledge"}
                class={[
                  "inline-flex items-center px-4 py-2 text-sm font-medium rounded-lg transition-all duration-200",
                  @current_page == :knowledge && "bg-indigo-100 text-indigo-700 shadow-sm",
                  @current_page != :knowledge && "text-gray-600 hover:text-gray-900 hover:bg-gray-50"
                ]}
              >
                <svg class="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"
                  >
                  </path>
                </svg>
                Knowledge
                <%= if @current_page == :knowledge do %>
                  <div class="ml-2 w-2 h-2 bg-indigo-500 rounded-full"></div>
                <% end %>
              </.link>
            </div>
          </div>

              <!-- Quick Actions & User Menu -->
          <div class="flex items-center space-x-3">
            <%= if @current_page == :chat do %>
              <!-- Quick link to upload files -->
              <.link
                navigate={~p"/knowledge"}
                class="inline-flex items-center px-3 py-1.5 text-sm text-indigo-600 hover:text-indigo-700 hover:bg-indigo-50 rounded-md transition-colors duration-200"
                title="Upload new files"
              >
                <svg class="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M12 6v6m0 0v6m0-6h6m-6 0H6"
                  >
                  </path>
                </svg>
                Upload Files
              </.link>
            <% else %>
              <!-- Quick link back to chat -->
              <.link
                navigate={~p"/"}
                class="inline-flex items-center px-3 py-1.5 text-sm text-indigo-600 hover:text-indigo-700 hover:bg-indigo-50 rounded-md transition-colors duration-200"
                title="Back to chat"
              >
                <svg class="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-3.582 8-8 8a8.013 8.013 0 01-7-4L3 20l4-4a8.003 8.003 0 01-1-4c0-4.418 3.582-8 8-8s8 3.582 8 8z"
                  >
                  </path>
                </svg>
                Back to Chat
              </.link>
            <% end %>

            <!-- User Menu -->
            <%= if @current_user do %>
              <div class="flex items-center space-x-2">
                <!-- User Info -->
                <div class="flex items-center space-x-2">
                  <%= if @current_user.picture do %>
                    <img src={@current_user.picture} alt="User avatar" class="h-8 w-8 rounded-full" />
                  <% else %>
                    <div class="h-8 w-8 rounded-full bg-indigo-100 flex items-center justify-center">
                      <span class="text-sm font-medium text-indigo-700">
                        <%= String.first(@current_user.name || @current_user.email || "?") %>
                      </span>
                    </div>
                  <% end %>
                  <span class="text-sm text-gray-700 hidden sm:block">
                    <%= @current_user.name || @current_user.email %>
                  </span>
                </div>
                <!-- Logout Form -->
                <form action="/auth/logout" method="post" class="inline">
                  <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
                  <button
                    type="submit"
                    class="inline-flex items-center px-3 py-1.5 text-sm text-gray-600 hover:text-gray-700 hover:bg-gray-50 rounded-md transition-colors duration-200"
                    title="Sign out"
                  >
                    <svg class="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1"
                      />
                    </svg>
                    Sign out
                  </button>
                </form>
              </div>
            <% else %>
              <!-- Login Link -->
              <.link
                href="/login"
                class="inline-flex items-center px-4 py-2 text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 rounded-md transition-colors duration-200"
              >
                Login
              </.link>
            <% end %>
          </div>
        </div>
      </div>
    </nav>
    """
  end
end
