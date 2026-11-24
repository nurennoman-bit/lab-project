FoodGo - Food Delivery App (Supabase + PWA)

CHALANO (ek button)
- Windows : start.bat e double click  (kisu install korte hobe na, browser nije khulbe)
- Mac     : start.command e double click (prothombar: right click > Open)
- Linux   : ./start.sh

ADMIN LOGIN
Email: nuren@gmail.com   Password: Nuren@123
(setup.sql run korle ei admin account nije toiri hoy. Password bodlate setup.sql er "pw" line bodlao RUN korar age,
ba account age theke thakle reset-admin-password.sql chalao.)

"EMAIL RATE LIMIT EXCEEDED" error: Supabase > Authentication > Sign In / Providers > Email > "Confirm email" OFF kore Save.

PROTHOMBAR DATABASE SETUP (ekbar-i)
Login page e jodi "Database setup lagbe" dekhay:
  1. "Setup SQL copy koro" button chapo
  2. "Supabase SQL Editor kholo" chapo > paste > RUN
  3. Page reload (F5)
setup.sql jotobar run koro kono khoti nei. Eta email-confirm-o auto off kore dey.

DEMO ACCOUNT (setup.sql run korle toiri hoy)
Customer: customer@foodgo.com  Password: Customer@123
Rider   : rider@foodgo.com     Password: Rider@123
Admin   : nuren@gmail.com      Password: Nuren@123

RIDER: rider ke sign up korte bolo > Admin > Users theke role "rider" koro.
ONNO ADMIN: config.js er ADMIN_EMAILS ar setup.sql er 'nuren@gmail.com' list e email add koro,
ba SQL Editor e: update public.profiles set role='admin' where email='tomar@email.com';

ONLINE DEPLOY (phone e PWA install er jonno HTTPS lagbe)
Puro folder ta Netlify / Vercel / Cloudflare Pages e upload koro.

SECURITY
- config.js e shudhu publishable key ache (RLS protect kore). SECRET KEY / database password kokhono file e dibe na.
