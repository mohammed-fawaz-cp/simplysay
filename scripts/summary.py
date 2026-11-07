import json

with open(r'C:\Users\cpmoh\.gemini\antigravity\brain\772a4763-59ab-4b3f-a2e3-d10b43580164\qa_104_test_results.json') as f:
    results = json.load(f)

counts = {}
ratings = {}
for tc_id, d in results.items():
    s = d['status']
    r = d['rating']
    counts[s] = counts.get(s, 0) + 1
    ratings[r] = ratings.get(r, 0) + 1

print('Status Breakdown:', counts)
print('Rating Breakdown:', ratings)

fails = [f"{k}: {v['title']} [{v['status']}]" for k, v in results.items() if v['status'] in ('FAIL', 'BLOCKED')]
print(f'\nRemaining Fails & Blocked ({len(fails)}):')
for item in fails:
    print('  -', item)

partials = [f"{k}: {v['title']} [{v['status']}]" for k, v in results.items() if v['status'] == 'PARTIAL']
print(f'\nPartials ({len(partials)}):')
for item in partials:
    print('  -', item)

