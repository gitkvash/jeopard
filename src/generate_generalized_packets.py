import pandas as pd
import json
import random
import os

df = pd.read_csv('data/JEOPARDY_CSV.csv')
df.columns = df.columns.str.strip()
category_counts = df['Category'].value_counts()
valid_cats = category_counts[category_counts >= 5].index.tolist()

good_keywords = ['WORLD', 'SCIENCE', 'GEOGRAPHY', 'MYTHOLOGY', 'LITERATURE', 'ANATOMY', 
                 'ASTRONOMY', 'PHYSICS', 'BIOLOGY', 'CHEMISTRY', 'EUROPE', 'MAMMALS', 
                 'ANIMALS', 'COUNTRIES', 'ART', 'MUSIC', 'HISTORY', 'INVENTIONS', 
                 'CAPITALS', 'BODIES OF WATER', 'ISLANDS', 'MOUNTAINS', 'FOOD', 
                 'LANGUAGES', 'RELIGION', 'SPORTS', 'CLASSICAL']

bad_keywords = ['U.S.', 'AMERICAN', 'U. S.', 'US ', 'PRESIDENTS', 'STATE', 'CONGRESS', 
                'SENATE', 'BASEBALL', 'NFL', 'NBA', 'HOLLYWOOD', 'TV', 'EMMY', 'OSCAR', 
                'GRAMMY', 'NEW YORK', 'CALIFORNIA', 'POP MUSIC', 'BRITISH']

def is_generalized(cat):
    cat_upper = cat.upper()
    if any(b in cat_upper for b in bad_keywords):
        return False
    # To be really strict about general knowledge:
    return any(g in cat_upper for g in good_keywords)

generalized_cats = [c for c in valid_cats if is_generalized(c)]
print(f'Found {len(generalized_cats)} generalized categories.')

random.seed(43) # ensure reproducibility
# We need enough categories for 10 packets (180 for standard + 20 for final)
# Total 200 categories.
if len(generalized_cats) < 200:
    print(f"Only found {len(generalized_cats)} categories. Need 200. I will select {len(generalized_cats)}.")
    selected_cats = generalized_cats
else:
    selected_cats = random.sample(generalized_cats, 200)

normal_categories = selected_cats[:180]
final_categories = selected_cats[180:] if len(selected_cats) >= 200 else selected_cats[-20:]

new_packages = []
normal_idx = 0
final_idx = 0
num_packets = 10

for p in range(num_packets):
    if normal_idx + 18 > len(normal_categories):
        break # not enough categories left
        
    rounds = []
    for r in range(3):
        topics = []
        for t in range(6):
            cat_name = normal_categories[normal_idx]
            normal_idx += 1
            
            cat_df = df[df['Category'] == cat_name].head(5)
            clues = []
            
            val_multiplier = (r + 1) * 10
            if r == 1: val_multiplier = 20
            elif r == 2: val_multiplier = 30
                
            for i, row in enumerate(cat_df.itertuples()):
                clues.append({
                    "value": (i + 1) * val_multiplier,
                    "question": row.Question,
                    "answer": row.Answer
                })
            topics.append({
                "name": cat_name,
                "clues": clues
            })
        rounds.append({
            "index": r + 1,
            "is_final": False,
            "playable": True,
            "topics": topics
        })
        
    # Final
    final_topics = []
    for t in range(2):
        if final_idx >= len(final_categories):
            final_idx = 0
        cat_name = final_categories[final_idx]
        final_idx += 1
        cat_df = df[df['Category'] == cat_name].head(1)
        row = cat_df.iloc[0]
        final_topics.append({
            "name": cat_name,
            "clues": [{
                "value": None,
                "question": row['Question'],
                "answer": row['Answer']
            }]
        })
    rounds.append({
        "index": 4,
        "is_final": True,
        "playable": False,
        "topics": final_topics
    })
    
    new_packages.append({
        "number": p + 1 + 20, # start from 21
        "title": f"Generalized Packet {p+1}",
        "subtitle": "Global Knowledge",
        "rounds": rounds
    })

# Read existing pilot
existing_file = os.path.join('data', 'pilot.json')
with open(existing_file, 'r', encoding='utf-8') as f:
    data = json.load(f)
    
data["packages"].extend(new_packages)

out_file = os.path.join('data', 'generalized_english_pilot.json')
with open(out_file, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=1)

print(f"Generated 10 generalized English packets at {out_file}!")
