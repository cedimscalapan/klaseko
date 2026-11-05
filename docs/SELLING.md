# Selling KlaseKo Plus

| | Free | Plus |
| --- | --- | --- |
| Classes | 2 (the sample class does not count) | Unlimited |
| Scanned papers | 40 a month | Unlimited |
| Everything else | Yes | Yes |
| Price | | ₱49 a month, or ₱399 a year |

A plan ending never locks anyone out. Teachers can still open, edit and print all their records, check papers by tapping, and use the forms.

## Making a sale

1. The teacher pays your GCash and sends you the receipt, using **Write the message** in **More → Your plan**.
2. Check that the payment arrived.
3. Send the teacher the next unused code of that plan from `batch-codes.csv`, in the `.klaseko` folder of your home folder. Write their name in the `sold_to` column, or a code may get sold twice.
4. They paste it in **Your plan** and tap **Turn on Plus**. It works offline, and no phone ID is needed.

When you run low, make more on your computer, in the project folder:

```bash
node tool/make_batch.js year 50
```

```bash
node tool/make_batch.js month 50
```

- A plan's days start when the teacher enters the code. Entering a code early adds to the days left.
- A code must be entered within one year of being made.
- **A code can be shared.** Nothing stops one code from working on many phones, and a code cannot be cancelled once it is out. One code also works again on the same phone after the app is reinstalled. For anyone you do not know, use a one-phone code. The online system would close this gap by allowing each code to be used once.

## One-phone codes

These work only on one phone, so sharing them does nothing. Ask the teacher for the phone ID shown in small print at the bottom of **Your plan**, then run:

```bash
node tool/make_code.js AB23-CD45 year "Maria Santos"
```

Use `month` for a one-month plan. For an early renewal, add the date the current plan ends, so the teacher keeps those days:

```bash
node tool/make_code.js AB23-CD45 month "Maria Santos" 2027-01-15
```

These codes are recorded in `sales.csv` in the `.klaseko` folder. A teacher who changes phones, or reinstalls the app, gets a new phone ID and needs a new code from you. Check `sales.csv` for when their plan ends, and give them a code that covers the time they have left.

## Your keys

The `.klaseko` folder in your home folder holds what the business depends on. **Copy it somewhere safe, such as a private USB drive, and never send it to anyone or put it in the project.**

| File | What it does | If you lose it |
| --- | --- | --- |
| `activation-key.pem` | Makes activation codes | You cannot make codes until a new app version ships with a new key |
| `klaseko-release.jks`, `keystore-password.txt` | Signs the app, so updates install over the old version | Teachers must uninstall and reinstall to update, which erases their data unless they restored a backup |
| `batch-codes.csv` | Lists your ready-to-sell codes | Unsold codes still work, but you cannot see them |
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
