"""Generate local admin credentials; never print secrets or add them to Git."""
from pathlib import Path
import hashlib, json, secrets, argparse

parser = argparse.ArgumentParser()
parser.add_argument('--reset', action='store_true', help='Rotate password and invalidate existing sessions')
args = parser.parse_args()
root = Path(__file__).resolve().parent
config = root / '.dev.vars'
password_file = root / '.admin-password.production'
if not config.exists() or args.reset:
    password = secrets.token_urlsafe(24)
    salt = secrets.token_hex(24)
    digest = hashlib.pbkdf2_hmac('sha256', password.encode(), salt.encode(), 100000).hex()
    values = {'ADMIN_PASSWORD_HASH': f'pbkdf2-sha256${salt}${digest}', 'SESSION_SECRET': secrets.token_hex(32)}
    config.write_text('\n'.join(f'{k}={v}' for k, v in values.items())+'\n', encoding='utf-8')
    password_file.write_text(password+'\n', encoding='utf-8')
    config.chmod(0o600)
    password_file.chmod(0o600)
else:
    values = dict(line.split('=', 1) for line in config.read_text(encoding='utf-8').splitlines() if '=' in line)
target = root.parent / 'build/checks/analytics-secrets.json'
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(json.dumps(values), encoding='utf-8')
target.chmod(0o600)
print(f'Credentials saved locally: {password_file}')
print(f'Secret upload file: {target}')
