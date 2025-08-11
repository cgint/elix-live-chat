# LiveAiChat

A **stream-first, modern AI chat workspace** built with Phoenix LiveView and pure Elixir.
Users can open multiple chat conversations, watch real-time token-by-token AI replies, and have all history persisted in lightweight CSV files—no database required.

---
## 📑 Project Roadmap

| Stage | Document | Status |
|-------|----------|--------|
| Vision & Feature Scope | [`PLAN_0_description.md`](PLAN_0_description.md) | ✅ finalised |
| High-Level Best Practices | [`PLAN_1_High_Level.md`](PLAN_1_High_Level.md) | ✅ finalised |
| Detailed Implementation How-To | [`PLAN_2_implementation_howto.md`](PLAN_2_implementation_howto.md) | 🚧 in progress |

Keep these in sync with the codebase as we implement.

---
## 🛠  Tech Stack

* **Elixir 1.16  / OTP 26**  – BEAM concurrency powers the real-time UX
* **Phoenix 1.7 + LiveView 0.20+**  – WebSocket transport & `live_stream/4` rendering
* **Ash 3.5** (future) – Domain layer when we add auth or resources
* **TailwindCSS 3 + DaisyUI** – Modern styling, already vendored
* **CSV-based persistence** – Flat files under `priv/data/chat_logs/`, no extra deps

See [`KNOWHOW_tech_stack.md`](KNOWHOW_tech_stack.md) for generator tips and workflow shortcuts.

---
## 🚀 Getting Started

1. **Install deps & assets**
   ```bash
   mix setup
   ```
2. **Run the dev server**
   ```bash
   mix phx.server   # or: iex -S mix phx.server
   ```
3. Visit [`http://localhost:4000`](http://localhost:4000) and start chatting.

> The first run creates `priv/data/chat_logs/` automatically.

---
## 🗺  Implementation Milestones (excerpt)

- [ ] Scaffold modules & supervision tree
- [ ] CSV storage layer + unit tests
- [ ] Sidebar & Chat LiveView (no AI yet)
- [ ] AI streaming integration (dummy client)
- [ ] Visual polish & responsiveness
- [ ] Telemetry hooks & CI tests

Full checklist lives at the bottom of **PLAN 2**.

---
## 🤝 Contributing

Pull requests are welcome! Please align with the active milestone and avoid introducing new Hex/NPM dependencies unless discussed.

---
## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
