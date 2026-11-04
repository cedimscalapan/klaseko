// Makes a KlaseKo Plus activation code for one phone, and notes the sale in sales.csv.
//   node tool/make_code.js AB23-CD45 year "Maria Santos"
//   node tool/make_code.js AB23-CD45 month "Maria Santos" 2027-01-15     (starts from that date, for a renewal)
// The private key stays outside this project: in the .klaseko folder of your home folder.
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');

const dir = process.env.KLASEKO_DIR || path.join(os.homedir(), '.klaseko');
const [phoneArg, termArg, note = '', fromArg] = process.argv.slice(2);
const phone = (phoneArg || '').toUpperCase().replace(/[^0-9A-Z]/g, '');
if (!/^[2-9A-HJKMNP-TV-Z]{8}$/.test(phone) || !['month', 'year'].includes(termArg)) {
  console.error('Usage: node tool/make_code.js PHONE-ID month|year "Teacher name" [start date YYYY-MM-DD]');
  process.exit(1);
}
const start = fromArg ? new Date(`${fromArg}T00:00:00`) : new Date();
if (isNaN(start)) {
  console.error('The start date should look like 2027-01-15.');
  process.exit(1);
}
const expires = new Date(start);
expires.setDate(expires.getDate() + (termArg === 'year' ? 365 : 31));
const pad = (n) => String(n).padStart(2, '0');
const day = `${expires.getFullYear()}${pad(expires.getMonth() + 1)}${pad(expires.getDate())}`;

const key = crypto.createPrivateKey(fs.readFileSync(path.join(dir, 'activation-key.pem')));
const message = Buffer.from(`K1|${phone}|${termArg[0]}|${day}`);
const code = 'KK-' + Buffer.concat([message, crypto.sign(null, message, key)]).toString('base64url');

const log = path.join(dir, 'sales.csv');
if (!fs.existsSync(log)) fs.writeFileSync(log, 'date,phone,plan,ends,teacher,code\n');
fs.appendFileSync(log, `${new Date().toISOString().slice(0, 10)},${phone},${termArg},${day},"${note.replace(/"/g, '""')}",${code}\n`);

console.log(`Plan: ${termArg}, ends ${day.slice(0, 4)}-${day.slice(4, 6)}-${day.slice(6)}`);
console.log(code);
