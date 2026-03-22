# Blitz MCP Integration

This project is open in **Blitz**, a native macOS iOS development environment.
Two MCP servers are active in `.mcp.json`:

- **`blitz-macos`** — Controls Blitz: navigate tabs, read project/simulator state,
  manage builds, fill App Store Connect forms, manage settings.
- **`blitz-iphone`** — Controls the iOS simulator/device: tap, swipe, type text,
  take screenshots, inspect UI hierarchy. See blitz-iphone tool docs for full command list.

## Testing workflow

After making code changes:
1. Wait briefly for hot reload / rebuild
2. `blitz-iphone` `describe_screen` — verify the UI updated as expected
3. `blitz-iphone` `device_action` — interact (tap buttons, type text, swipe)
4. `blitz-iphone` `describe_screen` — confirm the result
