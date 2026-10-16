"""Post the CI result to a Discord channel through a webhook.

Inputs come from environment variables (set by the workflow), never from the command line, so commit
messages and log lines are only ever data in a JSON body. Skips quietly when DISCORD_WEBHOOK_URL is unset
(forks, or before the secret is configured). DRY_RUN=1 prints the message instead of sending it.
"""
import json, os, re, sys, time, urllib.request

def first_failure(log_path):
    try:
        with open(log_path, encoding='utf-8', errors='replace') as f:
            for line in f:
                if re.search(r'\bFAIL\b|ERROR:', line):
                    return re.sub(r'^psql:\S+\s*', '', line.strip())[:300]
    except FileNotFoundError:
        return 'no log produced'
    return None

def verified(log_path):
    try:
        with open(log_path, encoding='utf-8', errors='replace') as f:
            hits = [l.strip() for l in f if l.startswith('VERIFIED:')]
        return hits[-1] if hits else None
    except FileNotFoundError:
        return None

def main():
    url = os.environ.get('DISCORD_WEBHOOK_URL', '')
    log = sys.argv[1] if len(sys.argv) > 1 else 'verify.log'
    ok = os.environ.get('JOB_STATUS', '') == 'success'
    sha = os.environ.get('SHA', '')[:7]
    started = os.environ.get('STARTED', '')
    took = f'{(int(time.time()) - int(started)) // 60} min' if started.isdigit() else 'n/a'
    commit = (os.environ.get('COMMIT_MESSAGE') or '').splitlines()[0][:120] if os.environ.get('COMMIT_MESSAGE') else ''
    fields = [
        {'name': 'Branch', 'value': os.environ.get('REF_NAME', '?'), 'inline': True},
        {'name': 'Commit', 'value': sha or '?', 'inline': True},
        {'name': 'Duration', 'value': took, 'inline': True},
    ]
    if ok:
        description = (verified(log) or 'all milestones verified') + '\nSeed at 1% scale.'
    else:
        description = 'First failure: ' + (first_failure(log) or 'see the log')
    if commit:
        fields.append({'name': 'Message', 'value': commit, 'inline': False})
    payload = {
        'username': 'Talentra CI',
        'allowed_mentions': {'parse': []},
        'embeds': [{
            'title': ('✅ verify passed' if ok else '❌ verify failed') + f" · {os.environ.get('REPO', '')}",
            'url': os.environ.get('RUN_URL', ''),
            'description': description[:1500],
            'color': 3066993 if ok else 15158332,
            'fields': fields,
            'footer': {'text': f"{os.environ.get('EVENT', 'push')} by {os.environ.get('ACTOR', '?')}"},
        }],
    }
    if os.environ.get('DRY_RUN') == '1':
        print(json.dumps(payload, indent=2))   # ASCII-escaped so it prints on any console
        return
    if not url:
        print('DISCORD_WEBHOOK_URL not set; skipping the notification')
        return
    req = urllib.request.Request(url, data=json.dumps(payload).encode(), headers={'Content-Type': 'application/json', 'User-Agent': 'talentra-ci'})
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            print('Discord notified:', resp.status)
    except Exception as e:   # a failed notification must never fail the build result
        print('Discord notification failed:', type(e).__name__)

if __name__ == '__main__':
    main()
