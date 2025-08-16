# TASK_auth_1 – Plan to Add Google Authentication (Login Required)

## 1. Goal
Require every visitor to authenticate with Google before using any page of LiveAiChat.  
Unauthenticated users are redirected automatically to the Google sign-in flow.

## 2. Current Situation vs. Example Article
|                                    | Example Article (phx.gen.auth + DB) | Our Codebase |
|------------------------------------|-------------------------------------|--------------|
|Auth generator in place             | Yes (mix phx.gen.auth)              | **No** – project has no Accounts context or Ecto Repo (uses Ash) |
|Database persistence of users       | Postgres via Ecto                   | None yet (can be added later via Ash) |
|Authentication library              | Ueberauth + `ueberauth_google`      | Same – we will use Ueberauth |
|Where user data stored              | `users` table                       | **Session cookie** for now (light-weight). Persistence optional extension |
|UI                                  | Button to start `/auth/google`      | Navigation component will show “Sign in with Google” if not logged-in; otherwise avatar + “Logout” |

Key difference: we skip `mix phx.gen.auth` scaffolding and heavy DB work for now; instead we take a minimal session-only path that still gates all routes. We can layer persistence later via Ash resource if needed.

## 3. Architectural Decisions
1. **Ueberauth** for OAuth2 dance; `ueberauth_google` strategy.
2. **Session-only** storage of a small user map: `%{sub, email, name, picture}`.
3. **Authentication Plug** placed in the `:browser` pipeline to enforce login on every request (controllers & LiveView).
4. **LiveView session propagation** – pass current_user via `Router.session_values/1` so all LiveViews have it.
5. **No DB migration** now.  Extension path documented.

## 4. Step-by-Step Implementation
### 4.1 Dependencies
```elixir
# mix.exs
defp deps do
  [
    ...,
    {:ueberauth, "~> 0.10"},
    {:ueberauth_google, "~> 0.10"}
  ]
end
```
Run `mix deps.get`.

### 4.2 Configuration
```elixir
# config/config.exs
config :ueberauth, Ueberauth,
  providers: [
    google: {Ueberauth.Strategy.Google, [default_scope: "email profile"]}
  ]

config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: System.get_env("GOOGLE_CLIENT_ID"),
  client_secret: System.get_env("GOOGLE_CLIENT_SECRET")
```
Add the two env vars locally and in production.

### 4.3 Auth Controller & Routes
```
lib/live_ai_chat_web/controllers/auth_controller.ex
  plug Ueberauth
  def request(conn, _), do: redirect(conn, external: Ueberauth.Strategy.Helpers.callback_url(conn))
  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    user = %{sub: auth.uid, email: auth.info.email, name: auth.info.name, picture: auth.info.image}
    conn |> put_session(:user, user) |> redirect(to: "/")
  end
  def logout(conn, _), do: conn |> configure_session(drop: true) |> redirect(to: "/")
```
Router additions:
```elixir
scope "/auth", LiveAiChatWeb do
  pipe_through :browser
  get "/:provider", AuthController, :request
  get "/:provider/callback", AuthController, :callback
  post "/logout", AuthController, :logout
end
```

### 4.4 Authentication Plug
Create `lib/live_ai_chat_web/plugs/require_auth.ex` that checks `get_session(conn, :user)`; if absent, redirect to `/auth/google` (and halt).
Add it as the last plug in the existing `:browser` pipeline *after* `fetch_session`.

### 4.5 Pass user to LiveView
Modify `Router.session_values/1`:
```elixir
user = Map.get(plug_session, "user")
Map.take(%{"user" => user, "test_pid" => plug_session["test_pid"]}, ["user", "test_pid"])
```
In LiveViews, read `@session["user"]` in `mount/3` and assign `:current_user`.

### 4.6 UI Updates
* `Navigation.navigation_bar/1` – if `@current_user` == nil show Google sign-in link (`/auth/google`); else show avatar, name and Logout form.
* Optionally hide page content until mount confirms `@current_user` to stop flashes.

### 4.7 Tests
1. Add `AuthPlugTest` to assert redirection for unauthenticated requests.
2. Add LiveView test that mount fails w/ redirect when session missing.

### 4.8 Roll-out Checklist
- [ ] Add env vars (`GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`) to `dev.env`, prod secrets, CI.
- [ ] `mix deps.get`, `mix compile`.
- [ ] Manual test: start app, hit `/`, should redirect to Google & back.
- [ ] Push.

## 5. Extension Path (optional)
If user persistence needed:
1. Introduce `User` Ash resource with unique email.
2. On callback upsert user by `sub`/`email`.
3. Replace session user map with `%User{id: …}` reference.

---
**ETA:** ~1–2 h coding + Google console setup. Minimal, surgical changes; no database touch unless needed later.
