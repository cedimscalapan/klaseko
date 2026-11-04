# Selling KlaseKo Plus

| | Free | Plus |
| --- | --- | --- |
| Classes | 2 (the sample class does not count) | Unlimited |
| Scanned papers | 40 a month | Unlimited |
| Everything else | Yes | Yes |
| Price | | ₱49 a month, or ₱399 a year |

A plan ending never locks anyone out. Teachers can still open, edit and print all their records, check papers by tapping, and use the forms.

## Making a sale

1. The teacher pays your GCash and sends the receipt and their phone ID, from **More → Your plan**.
2. Check that the payment arrived.
3. On your computer, in the project folder, run:

   ```bash
   node tool/make_code.js AB23-CD45 year "Maria Santos"
   ```

   Use `month` for a one-month plan. For an early renewal, add the date the current plan ends, so the teacher keeps those days:

   ```bash
   node tool/make_code.js AB23-CD45 month "Maria Santos" 2027-01-15
   ```

4. Send the teacher the code starting with `KK-`. They paste it in **Your plan** and tap **Turn on Plus**. It works offline.

Every code is recorded in `sales.csv` in the `.klaseko` folder of your home folder.

A code works only on the phone it was made for. A teacher who changes phones, or reinstalls the app, gets a new phone ID and needs a new code from you. Use the plan's original end date as the start, minus the plan length, or give the days left as a courtesy.

## Your keys

The `.klaseko` folder in your home folder holds what the business depends on. **Copy it somewhere safe, such as a private USB drive, and never send it to anyone or put it in the project.**

| File | What it does | If you lose it |
| --- | --- | --- |
| `activation-key.pem` | Makes activation codes | You cannot make codes until a new app version ships with a new key |
| `klaseko-release.jks`, `keystore-password.txt` | Signs the app, so updates install over the old version | Teachers must uninstall and reinstall to update, which erases their data unless they restored a backup |
| `keystore-base64.txt` | The signing key in the form GitHub needs | Can be made again from the `.jks` file |

Anyone with `activation-key.pem` can make free codes. Anyone with the signing key could publish an update that looks like yours.

## Setting up app signing (once)

In the GitHub repository, go to **Settings → Secrets and variables → Actions → New repository secret** and add two secrets:

| Name | Value |
| --- | --- |
| `KLASEKO_KEYSTORE_BASE64` | The contents of `keystore-base64.txt` |
| `KLASEKO_KEY_PASSWORD` | The contents of `keystore-password.txt` |

Until these are set, every build is signed with a temporary key, and updates will not install over the old version.

## Before selling

Set your GCash number, GCash name and contact (for example your Messenger link) at the top of `lib/core/plan.dart`.

The repository is currently public, so anyone can read the code and build their own copy without the limits. Make it private before selling: **Settings → General → Change repository visibility**.
