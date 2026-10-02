# ggpi-uptime

Outside-in availability check for **Go Green Verify** and **DocGen AI**,
run every 10 minutes on GitHub's runners (`.github/workflows/uptime.yml`).

- **What:** the public endpoints in `targets.txt`, each with an expected
  status and, for the health routes, text the body must contain.
- **When it alerts:** a target has to fail **two consecutive runs**, and each
  run retries a failure once after 15 s. The alert goes to the ops Telegram
  chat. A recovery message follows the first passing run.
- **Why here:** this repo is public, so Actions minutes are free. The same
  schedule in the products' private repos would bill about 4,000 minutes a
  month.
- **Limits:** GitHub may delay scheduled runs, so treat this as a 10-minute
  check, not a pager. Schedules in a public repo are disabled after 60 days
  of inactivity; the `keepalive` job re-enables the workflow weekly.

Secrets (repository settings): `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`.

To prove the alert path: **Actions → Uptime probe → Run workflow**, with
`test_url` set to a URL that fails. That run uses a throwaway state file and
alerts on the first failure, labelled `ALERT TEST`.

To add a target, append a line to `targets.txt`.
