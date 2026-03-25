# Secret Rotation

A full-stack application for managing dynamic secret rotation with a PostgreSQL backend and real-time monitoring dashboard.

## Project Structure

```
secret_rotation/
├── app/
│   ├── api/          # Express.js backend server
│   └── web/          # React frontend dashboard
├── postgres/         # PostgreSQL initialization scripts
├── compose.yml       # Docker Compose configuration
└── README.md         # This file
```

## Backend: `./app/api`

Node.js/Express API server that manages secret rotation and credential lifecycle.

### Overview

- **Runtime**: Node.js (ES6 modules)
- **Framework**: Express.js 5.x
- **Database**: PostgreSQL 16
- **Port**: 3000 (configurable via `.env`)

### Key Features

- **Patient Lane**: Issues dynamic PostgreSQL credentials with automatic expiration
- **Surgeon Lane**: Manages static role password rotation with TTL tracking
- **Doctor Lane**: Rotates database root credentials and monitors system health

### API Endpoints

**Patient Management** (`/api/patient/`)
- `POST /issue` - Issue temporary database credentials
- `POST /test` - Validate current credentials
- `POST /revoke` - Revoke an active lease

**Surgeon Management** (`/api/surgeon/`)
- `POST /issue` - Load static role credentials
- `POST /test` - Verify static credentials
- `POST /rotate` - Rotate role password

**Doctor Management** (`/api/doctor/`)
- `POST /rotate-root` - Rotate database root credential

### Configuration

```bash
# Required environment variables (.env)
DB_HOST=postgres          # PostgreSQL host
DB_PORT=5432              # PostgreSQL port
DB_USER=vaultadmin        # Database user
DB_PASSWORD=vaultadminpass # Database password
DB_NAME=librarydemo       # Database name
PORT=3000                 # API server port
```

### Running the API

```bash
# Navigate to the API directory
cd app/api

# Install dependencies
npm install

# Development with auto-reload
npm run dev

# Production mode
npm run start
```

## Frontend: `./app/web`

React dashboard for real-time credential and secret rotation monitoring.

### Overview

- **Framework**: React 19.x
- **Build Tool**: Vite 8.x
- **Port**: 5173 (default Vite dev server)
- **Type**: ES6 modules

### Key Features

**Dashboard Lanes**
- **Patient Monitor**: Real-time lease countdown, credential display, pulse checks
- **Surgeon Card**: Static role password tracking, TTL countdown, rotation controls
- **Doctor Card**: Root credential rotation status, last rotation timestamp

**Real-Time Updates**
- Auto-refresh intervals for lease expiration tracking
- Event timeline with color-coded status (success, warning, critical)
- Waveform visualization showing credential health status

### Components

```
src/components/
├── PatientMonitor.jsx   # Patient credential lifecycle management
├── SurgeonCard.jsx      # Static password rotation tracking
└── DoctorCard.jsx       # Root credential rotation monitoring
```

### Configuration

```javascript
// Environment variables (vite.config.js)
VITE_API_BASE=http://localhost:3000  // Backend API URL (default shown)
```

### Running the Frontend

```bash
# Navigate to the web directory
cd app/web

# Install dependencies
npm install

# Development with hot reload
npm run dev

# Production build
npm run build

# Preview production build
npm run preview

# Lint code
npm run lint
```

## Docker Compose

Full stack orchestration with PostgreSQL database.

### Services

- **postgres**: PostgreSQL 16 database container
  - Auto-initializes from `postgres/init/` scripts
  - Health checks enabled
  - Data persistence via Docker volume

### Running with Docker

```bash
# Start all services
docker-compose up -d

# View logs
docker-compose logs -f

# Stop services
docker-compose down

# Stop and remove volumes
docker-compose down -v
```

## Quick Start

### Prerequisites

- Node.js v18+
- Docker & Docker Compose (optional, for PostgreSQL)
- npm or yarn

### Development Setup

```bash
# 1. Start the database
docker-compose up -d postgres

# 2. Start the API
cd app/api
npm install
npm run dev

# 3. In another terminal, start the frontend
cd app/web
npm install
npm run dev

# 4. Open browser
# Frontend: http://localhost:5173
# API: http://localhost:3000
```

### Production Deployment

```bash
# 1. Build frontend
cd app/web
npm run build

# 2. Start backend with environment variables
cd ../api
npm install
npm run start

# 3. Configure API_BASE in frontend (Vite config or deploy)
# Point to production API URL
```

## Architecture

```
┌─────────────────────────────────────┐
│         React Dashboard             │
│  (Patient, Surgeon, Doctor Lanes)   │
│       Port: 5173 (dev)              │
└──────────────┬──────────────────────┘
               │ HTTP
               ▼
┌─────────────────────────────────────┐
│      Express.js API Server          │
│  (Routes: patient, surgeon, doctor) │
│       Port: 3000                    │
└──────────────┬──────────────────────┘
               │ SQL
               ▼
┌─────────────────────────────────────┐
│      PostgreSQL Database            │
│  (Credential storage & tracking)    │
│       Port: 5432                    │
└─────────────────────────────────────┘
```

## Monitoring & Debugging

### Backend Logs
```bash
cd app/api
npm run dev  # Logs to console
```

### Frontend Logs
```bash
cd app/web
npm run dev  # Browser DevTools for React/Vite logs
```

### Database Access
```bash
# Connect to PostgreSQL
docker-compose exec postgres psql -U vaultadmin -d librarydemo
```

## License

[GPLv3](LICENSE)
