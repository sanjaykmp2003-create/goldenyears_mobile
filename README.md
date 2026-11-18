# Golden Years – Care Operations Console (Flutter mobile app)

Mobile twin of the React web console. Same look (colours, Newsreader + Inter fonts, cards, tags, drawer
navigation) and **the same Express API** – no server fork.

## Run
```bash
./setup.sh                      # once: creates android/ios folders, adds INTERNET permission, pub get
flutter run --dart-define=API_URL=http://192.168.1.10:8080/api
```
* Android emulator → host machine is `http://10.0.2.2:8080/api` (the default).
* Real phone → use your computer's LAN IP, same Wi‑Fi. You can also change it on the login screen ("Server: …").
* iOS with plain `http://` needs an ATS exception in `ios/Runner/Info.plist` (dev only). Use https in production.
* Release APK: `flutter build apk --dart-define=API_URL=https://api.yourdomain.com/api`

## How it talks to the server
| Web app                              | Mobile app                                  |
|--------------------------------------|---------------------------------------------|
| `POST /api/auth/login`, `/refresh`   | same (tokens in secure storage, auto-refresh on 401) |
| write path `POST/PUT/DELETE /api/:table` | same                                    |
| read path `GET /sync/:table` (public) | `GET /api/:table` (authenticated, paged, RBAC-scoped) |
| `/api/admin/roles`, `/api/admin/users` | same                                      |
| `/api/payroll/run`, `/api/billing/invoices` | same                                 |

Screens shown depend on the role's screen list returned by login (`role_screen`), exactly like the web sidebar.

## Screens
Dashboard · Enquiries · Clients & Patients · Patient Assessment · Duty Roster · Attendance (nurse check-in/out with
rules R3.2/R3.3/R3.5) · Leave (overlap rule R4.2, approve/reject) · Nurse App (summary, vitals, medication, intake/output,
procedure, general care, shift report) · Billing (manual or server-generated invoices, record payment) · Payroll (run + status) ·
Masters (7 tables) · Role Management · User Management.

## Differences from the web app (deliberate)
* **Online-first**, not offline-first: no PGlite / ElectricSQL / outbox. Last-loaded lists are cached on the device and shown
  with an "Offline" banner, but **writes need a connection**.
* Assessment form covers the main sections (A–G) but not the full clinical systems review / medication table.
* Payroll uses the server's `/payroll/run` calculation rather than the web page's in-browser sample numbers.

## Server change (optional, recommended)
See `server/CHANGES.md`: `AUTH_ENFORCED=true` turns on real JWT verification. Currently the server bypasses auth for every request.
