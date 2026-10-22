import json
import collections
import re
import sys
import unicodedata

if sys.stdout and hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

with open('data/packets_all.json', encoding='utf-8') as f:
    data = json.load(f)

packages = data['packages']

WORD = re.compile(r'[^\wႠ-ჿᲐ-Ჿ]+')
STOP = set('''ეს ამ იგი მან მას რომ და თუ არის იყო არა მაგრამ როცა სადაც რომელიც
რომელსაც რომელმაც მისი მათი ერთ ერთი ორი სამი ამის იმ იმის მისმა დაასახელეთ
წელს წლის საუკუნეში ასევე უფრო ყველაზე შემდეგ დროს გამო შესახებ თავისი'''.split())
STEM = 6

def stems(text: str) -> set[str]:
    text = unicodedata.normalize('NFKC', text).lower()
    return {w[:STEM] for w in WORD.sub(' ', text).split() if len(w) > 3 and w not in STOP}

def norm_ans(ans: str) -> str:
    ans = unicodedata.normalize('NFKC', ans).lower()
    ans = re.sub(r'\(.*?\)', '', ans)
    return ' '.join(WORD.sub(' ', ans).split())

topic_counts = collections.defaultdict(list)
clues = []
ans_map = collections.defaultdict(list)
exact_q_map = collections.defaultdict(list)

for p in packages:
    p_num = p['number']
    for r in p['rounds']:
        r_idx = r['index']
        for t_idx, t in enumerate(r['topics']):
            t_name = t['name'].strip()
            topic_counts[t_name].append({
                'pkg': p_num,
                'round': r_idx,
                't_idx': t_idx
            })
            for c_idx, c in enumerate(t['clues']):
                q_text = c['question'].strip()
                a_text = c['answer'].strip()
                na = norm_ans(a_text)
                st = stems(q_text)
                clue_rec = {
                    'pkg': p_num,
                    'round': r_idx,
                    't_idx': t_idx,
                    'topic': t_name,
                    'c_idx': c_idx,
                    'val': c.get('value'),
                    'q': q_text,
                    'a': a_text,
                    'na': na,
                    'stems': list(st)
                }
                clues.append(clue_rec)
                if na:
                    ans_map[na].append(clue_rec)
                norm_q = ' '.join(WORD.sub(' ', q_text.lower()).split())
                exact_q_map[norm_q].append(clue_rec)

# 1. Topic duplicates
multi_topics = {k: v for k, v in topic_counts.items() if len(v) > 1}

# 2. Exact duplicate questions
exact_dupes = {k: v for k, v in exact_q_map.items() if len(v) > 1}

# 3. Same answer within same package
same_pkg_ans = collections.defaultdict(lambda: collections.defaultdict(list))
for na, occ in ans_map.items():
    if len(occ) > 1:
        by_p = collections.defaultdict(list)
        for c in occ:
            by_p[c['pkg']].append(c)
        for p_num, p_clues in by_p.items():
            if len(p_clues) > 1:
                same_pkg_ans[p_num][na].extend(p_clues)

# 4. Re-asks (overlap >= 0.40)
# Build stem inverted index
stem_index = collections.defaultdict(list)
for idx, c in enumerate(clues):
    for s in c['stems']:
        stem_index[s].append(idx)

checked_pairs = set()
reasks = []

for s, idxs in stem_index.items():
    if len(idxs) > 100:
        continue
    for i in range(len(idxs)):
        for j in range(i + 1, len(idxs)):
            a, b = idxs[i], idxs[j]
            pair_key = (min(a, b), max(a, b))
            if pair_key in checked_pairs:
                continue
            checked_pairs.add(pair_key)
            ca, cb = clues[a], clues[b]
            sa, sb = set(ca['stems']), set(cb['stems'])
            if not sa or not sb:
                continue
            inter = len(sa & sb)
            union = len(sa | sb)
            score = inter / union
            if score >= 0.40:
                reasks.append({
                    'score': round(score, 3),
                    'clue_a': ca,
                    'clue_b': cb,
                    'same_answer': ca['na'] == cb['na']
                })

report_data = {
    'total_packages': len(packages),
    'total_topics': sum(len(v) for v in topic_counts.values()),
    'unique_topics': len(topic_counts),
    'multi_topics_count': len(multi_topics),
    'multi_topics': {k: v for k, v in sorted(multi_topics.items(), key=lambda x: len(x[1]), reverse=True)},
    'exact_dupes_count': len(exact_dupes),
    'exact_dupes': [
        {'question': v[0]['q'], 'occurrences': [{'pkg': x['pkg'], 'round': x['round'], 'topic': x['topic'], 'answer': x['a']} for x in v]}
        for v in exact_dupes.values()
    ],
    'same_pkg_ans_pkgs_count': len(same_pkg_ans),
    'same_pkg_ans_groups_count': sum(len(v) for v in same_pkg_ans.values()),
    'same_pkg_ans': {
        p: {
            na: [{'round': x['round'], 'topic': x['topic'], 'val': x['val'], 'q': x['q'], 'a': x['a']} for x in clues_list]
            for na, clues_list in ans_groups.items()
        }
        for p, ans_groups in sorted(same_pkg_ans.items())
    },
    'reask_count': len(reasks),
    'reasks': sorted(reasks, key=lambda x: x['score'], reverse=True)
}

with open('duplicate_audit_report.json', 'w', encoding='utf-8') as f:
    json.dump(report_data, f, ensure_ascii=False, indent=2)

print(f"Audit completed:")
print(f"- Total packages: {len(packages)}")
print(f"- Total topics: {report_data['total_topics']}, Unique: {report_data['unique_topics']}")
print(f"- Duplicate topic names: {len(multi_topics)}")
print(f"- Exact duplicate questions: {len(exact_dupes)}")
print(f"- Packages with duplicate answers within same package: {len(same_pkg_ans)} (groups: {report_data['same_pkg_ans_groups_count']})")
print(f"- Re-ask pairs (stem overlap >= 0.40): {len(reasks)}")
