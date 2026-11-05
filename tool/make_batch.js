// Makes ready-to-sell KlaseKo Plus codes that work on any phone, and lists them in batch-codes.csv.
//   node tool/make_batch.js year 50
//   node tool/make_batch.js month 50
// The plan's days start when the teacher enters the code. A code must be entered within one year of
// being made. The private key and the list stay outside this project, in the .klaseko folder of your
// home folder.
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');

const dir = process.env.KLASEKO_DIR || path.join(os.homedir(), '.klaseko');
const [termArg, countArg] = process.argv.slice(2);
const count = Number(countArg);
if (!['month', 'year'].includes(termArg) || !Number.isInteger(count) || count < 1 || count > 1000) {
  console.error('Usage: node tool/make_batch.js month|year COUNT (1 to 1000)');
  process.exit(1);
}

const redeem = new Date();
redeem.setFullYear(redeem.getFullYear() + 1);
const pad = (n) => String(n).padStart(2, '0');
const redeemBy = `${redeem.getFullYear()}${pad(redeem.getMonth() + 1)}${pad(redeem.getDate())}`;
const today = new Date().toISOString().slice(0, 10);

const letters = '23456789ABCDEFGHJKMNPQRSTVWXYZ'; // none that look alike
const key = crypto.createPrivateKey(fs.readFileSync(path.join(dir, 'activation-key.pem')));
const list = path.join(dir, 'batch-codes.csv');
if (!fs.existsSync(list)) fs.writeFileSync(list, 'plan,made,enter_by,serial,code,sold_to\n');

const lines = [];
for (let i = 0; i < count; i++) {
  const serial = Array.from(crypto.randomBytes(8), (b) => letters[b % letters.length]).join('');
  const message = Buffer.from(`K2|ANY|${termArg[0]}|${serial}|${redeemBy}`);
  const code = 'KK-' + Buffer.concat([message, crypto.sign(null, message, key)]).toString('base64url');
  lines.push(`${termArg},${today},${redeemBy},${serial},${code},`);
}
fs.appendFileSync(list, lines.join('\n') + '\n');
console.log(`Added ${count} ${termArg} codes to ${list}`);
