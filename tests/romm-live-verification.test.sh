#!/usr/bin/env bash
# End-of-chain checks inside an installed disposable RomM container.
set -euo pipefail
systemd-detect-virt -q
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

for service in romm-backend romm-worker romm-scan-worker romm-scheduler romm-watcher angie; do
  systemctl is-active --quiet "$service"
  systemctl is-enabled --quiet "$service"
done
curl -fsS http://127.0.0.1/api/heartbeat -o "$work/heartbeat.json"
printf 'PASS backend heartbeat and installed service state\n'

for route in /rom/1/ejs /rom/36/ejs '/rom/36/ejs?probe=1'; do
  curl -fsS -D "$work/headers" "http://127.0.0.1$route" -o "$work/page"
  cmp /opt/romm/frontend/dist/index.html "$work/page"
  grep -qi '^Cross-Origin-Embedder-Policy: require-corp' "$work/headers"
  grep -qi '^Cross-Origin-Opener-Policy: same-origin' "$work/headers"
done
curl -fsS -D "$work/headers" http://127.0.0.1/settings -o "$work/page"
cmp /opt/romm/frontend/dist/index.html "$work/page"
if grep -qi '^Cross-Origin-' "$work/headers"; then
  printf 'ordinary SPA route unexpectedly isolated\n' >&2
  exit 1
fi
printf 'PASS player isolation headers and ordinary SPA routes\n'

core=$(find /opt/romm/frontend/dist/assets/emulatorjs/data/cores -name '*dosbox_pure*.data' -print -quit)
test -n "$core"
for path in /opt/romm/frontend/dist/assets/emulatorjs/data/loader.js \
  "$core" /opt/romm/frontend/dist/assets/ruffle/ruffle.js; do
  test -s "$path"
  curl -fsS "http://127.0.0.1${path#/opt/romm/frontend/dist}" -o "$work/asset"
  cmp "$path" "$work/asset"
done
printf 'PASS actual built player payloads served byte-for-byte\n'

cd /opt/romm/backend
/opt/romm/.venv/bin/python - << 'PY'
import pathlib
import time
import uuid

from dotenv import load_dotenv
from redis import Redis
from rq import Queue
from rq.cron import CronScheduler
from rq.job import JobStatus

load_dotenv('/opt/romm/.env')
from tasks.registry import SCHEDULED_TASKS

connection = Redis(host='127.0.0.1', port=6379, db=0)
expected = {name for name, task in SCHEDULED_TASKS.items() if task.enabled and task.cron_string}
assert expected, 'probe expects enabled scheduled tasks'
registered = {
    job.name
    for scheduler in CronScheduler.all(connection=connection, cleanup=False)
    if scheduler.config_file == 'tasks.cron_config'
    for job in scheduler.get_jobs()
}
assert expected <= registered, (expected, registered)
print(f'PASS cron process registered configured tasks in Redis: {sorted(expected)}')

token = uuid.uuid4().hex
module = f'romm_rq_probe_{token}'
path = pathlib.Path(f'{module}.py')
assert not path.exists()
path.write_text('def echo(value):\n    return value\n')
jobs = []
for name in ('default', 'scans'):
    value = f'{token}:{name}'
    job = Queue(name, connection=connection).enqueue(f'{module}.echo', value, result_ttl=300)
    jobs.append((job, value))

for job, value in jobs:
    for attempt in range(120):
        status = job.get_status(refresh=True)
        if status == JobStatus.FINISHED:
            assert job.return_value(refresh=True) == value
            print(f'PASS {job.origin} worker consumed the job and returned its payload')
            break
        assert status != JobStatus.FAILED, (job.id, job.exc_info)
        time.sleep(0.5)
    else:
        raise AssertionError(f'job {job.id} was not consumed; probe module retained at {path}')

for job, value in jobs:
    job.delete()
path.unlink()
PY
df -h /
