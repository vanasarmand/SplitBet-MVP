# SplitBet MVP

Social pooled betting platform built around the core loop:
**CREATE -> DISCOVER -> JOIN -> FILL -> FAIR RANDOM WINNER -> PAYOUT -> REPEAT**

## Workspace Structure

- `flutter_app/`: Cross-platform Flutter frontend (Web, Android, iOS, Windows).
  - Expandable in-place pool cards (WhatsApp style)
  - New user first-pool onboarding flow
  - Double-entry financial wallet UI (Available, In Active Pools, Total)
  - Admin inspection dialog and profile overview
- `server/`: Node.js + Express + WebSocket backend with SQLite database.
  - Server-side cryptographic RNG for fair winner selection
  - Double-entry financial ledger (`ledger.js`)
  - Atomic concurrency protection against simultaneous final-slot joins

## Quick Start

### 1. Start the Backend Server
```bash
cd server
node server.js
```
Runs on `http://localhost:4000` with WebSocket support at `ws://localhost:4000/ws`.

### 2. Start the Flutter Web App
```bash
cd flutter_app
flutter run -d chrome
```
Runs on `http://localhost:8080`.
