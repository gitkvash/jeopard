"""One-off: list every topic name already used across pilot.json + agy_packets/*.json.

Fed into new-packet prompts so packets 31-50 do not repeat a topic already played.
Writes data/used_topics.txt, one "PxxRy: name" per line.

    python src/collect_used_topics.py
"""
import glob
import json
import os

OUT = os.path.join('data', 'used_topics.txt')


def packages_in(data):
    if isinstance(data, dict) and 'packages' in data:
        return data['packages']
    if isinstance(data, list):
        return data
    return [data]


def main():
    lines = []
    files = ['data/pilot.json'] + sorted(glob.glob('data/agy_packets/packet_*.json'))
    for path in files:
        with open(path, encoding='utf-8') as fh:
            data = json.load(fh)
        for pkg in packages_in(data):
            num = pkg.get('number')
            for rnd in pkg.get('rounds', []):
                ridx = rnd.get('index')
                for topic in rnd.get('topics', []):
                    name = (topic.get('name') or '').strip()
                    if name:
                        lines.append(f'P{num}R{ridx}: {name}')

    with open(OUT, 'w', encoding='utf-8') as fh:
        fh.write('\n'.join(lines) + '\n')
    print(f'{len(lines)} topic names from {len(files)} files -> {OUT}')


if __name__ == '__main__':
    main()
