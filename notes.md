# Fullstack Project Exploration Notes

## Project Structure
This is a multi-project repository with:

1. **fullstack/** - Main Phoenix LiveView application
   - Has standard Phoenix structure (assets/, config/, lib/, priv/, test/)
   - Uses PostgreSQL (based on System Index showing postgrex dep)
   - Has authentication system (User model, auth routes in router)
   - Multiple LiveViews for different features

2. **firmware/** - Nerves IoT firmware project
   - Targets various embedded devices (rpi, bbb, etc.)
   - Has server link functionality to communicate with main app

3. **fibonaccier/** - Rust project (Cargo.toml present)
   - Likely a performance-optimized Fibonacci calculator

## Main App Features (from System Index)
- User authentication with registration/login
- Blog posts with author relationships
- Devices management
- Customers and POS (Point of Sale) system
- Transactions with status tracking
- URL shortener functionality
- Chat system with presence
- Public analytics and dashboards
- Real-time features using PubSub

## Current App Status
✅ **Server Running** - Phoenix app is running on port 4000
✅ **Database Setup** - PostgreSQL configured and migrations run
✅ **Real-time Features** - Counters work, showing Phoenix LiveView functionality

### Homepage Features Observed:
- Interactive counters (Browser, User, Centralized) 
- Statistics display (Devices: 0, Customers: 0, Transactions: 0)
- Fibonacci calculator (computing...)
- "Crash the Browser" and "Destroy Centralized" action buttons
- User authentication links (Register/Log in)
- Navigation to "/about" showing "All projects"
- Technology logos (Phoenix, Nx, Nerves, Livebook)

## Next Steps
Need to explore what specific functionality to add or modify.
