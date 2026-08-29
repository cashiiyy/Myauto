name: passenger-driver-registration-flow
description: How passengers and drivers register, get verified via OTP, and have their profiles displayed in mock mode

**What happened:** Documented the registration flow for both passenger and driver profiles: screens collect user data, Firebase Auth creates session, Firestore stores profile document with role-specific fields (passenger: isRequesting; driver: auto reg number, license, location), post-reg redirects to PermissionGateScreen for location permission.

**How to apply:** Use this reference when adding new registration fields or modifying existing ones. Key files: `screens/registration_passenger.dart`, `screens/registration_driver.dart`, `providers/auth_provider.dart`. In Mock Mode (web testing), profile data is saved locally via `localSessionProvider` before redirecting to PermissionGateScreen. For production, Firestore document creation persists the user's profile permanently with real-time sync for driver location tracking via `backendDriversProvider`.

**Related memories:** [[app-config]] (for polling intervals)