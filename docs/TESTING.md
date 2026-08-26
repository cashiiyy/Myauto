# Testing Guide

## Backend Tests

The backend uses `pytest` with `httpx` (for async HTTP requests) and `fakeredis` (for in-memory Redis mocking). Firebase authentication is mocked out.

### Setup

1. Navigate to the backend directory:
   ```bash
   cd backend
   ```

2. Install test dependencies:
   ```bash
   pip install pytest pytest-asyncio httpx fakeredis
   ```

3. Run the tests:
   ```bash
   pytest tests/ -v --asyncio-mode=auto
   ```

### Test Coverage

- **Authentication**: Validates that endpoints requiring auth return `401 Unauthorized` without a token.
- **Location Updates**: Tests driver and passenger location submissions, coordinate validation (e.g., rejecting latitude > 90), and timestamp freshness.
- **Driver Discovery**: Verifies that `GET /api/drivers/nearby` returns registered drivers and ignores offline ones.
- **Ride Lifecycle**: Tests creating a request, matching, accepting/rejecting (simulated via API), cancelling, completing, and SOS events.
- **Authorization**: Ensures users cannot cancel rides they are not part of.

## Flutter Testing

Currently, the app relies heavily on `AppConfig.mockMode` for UI testing without a real backend.

To run the app with mock data:
```bash
flutter run --dart-define=MOCK_MODE=true
```
