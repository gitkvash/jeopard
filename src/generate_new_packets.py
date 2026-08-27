import pandas as pd
import json
import random
import os
from deep_translator import GoogleTranslator
import time

def translate_text(text, translator, max_retries=3):
    if not text:
        return text
    for i in range(max_retries):
        try:
            return translator.translate(text)
        except Exception as e:
            print(f"Translation failed: {e}. Retrying...")
            time.sleep(2)
    return text  # fallback to original

def generate_packets(csv_path, num_packets=10):
    df = pd.read_csv(csv_path)
    
    # Clean up column names
    df.columns = df.columns.str.strip()
    
    # Group by category and round
    # We want categories that have at least 5 questions for normal rounds
    category_counts = df['Category'].value_counts()
    valid_categories = category_counts[category_counts >= 5].index.tolist()
    
    # We need 180 categories for normal rounds, 20 for final rounds
    if len(valid_categories) < (num_packets * 18 + num_packets * 2):
        print("Not enough categories with 5+ questions.")
        return
        
    random.seed(42)
    selected_categories = random.sample(valid_categories, num_packets * 20)
    
    normal_categories = selected_categories[:num_packets * 18]
    final_categories = selected_categories[num_packets * 18:]
    
    translator = GoogleTranslator(source='auto', target='ka')
    
    new_packages = []
    
    normal_idx = 0
    final_idx = 0
    
    print(f"Generating {num_packets} packets...")
    
    for p in range(num_packets):
        print(f"Generating packet {p+1}/{num_packets}...")
        
        # We need to only translate SOME questions to avoid hitting rate limits.
        # Let's say we translate the first packet fully, and the rest we leave as English to avoid 429 errors.
        translate_this_packet = (p < 2) # Translate first 2 packets
        
        rounds = []
        for r in range(3): # 3 normal rounds
            topics = []
            for t in range(6):
                cat_name = normal_categories[normal_idx]
                normal_idx += 1
                
                cat_df = df[df['Category'] == cat_name].head(5)
                
                t_name = translate_text(cat_name, translator) if translate_this_packet else cat_name
                
                clues = []
                val_multiplier = (r + 1) * 10 # R1: 10..50, R2: 20..100, R3: 30..150
                if r == 1:
                    val_multiplier = 20
                elif r == 2:
                    val_multiplier = 30
                    
                for i, row in enumerate(cat_df.itertuples()):
                    q = row.Question
                    a = row.Answer
                    
                    if translate_this_packet:
                        q_t = translate_text(q, translator)
                        a_t = translate_text(a, translator)
                    else:
                        q_t, a_t = q, a
                        
                    clues.append({
                        "value": (i + 1) * val_multiplier,
                        "question": q_t,
                        "answer": a_t
                    })
                    time.sleep(0.1) # Small delay to avoid rate limiting
                
                topics.append({
                    "name": t_name,
                    "clues": clues
                })
            rounds.append({
                "index": r + 1,
                "is_final": False,
                "playable": True,
                "topics": topics
            })
            
        # Final round
        final_topics = []
        for t in range(2):
            cat_name = final_categories[final_idx]
            final_idx += 1
            cat_df = df[df['Category'] == cat_name].head(1)
            t_name = translate_text(cat_name, translator) if translate_this_packet else cat_name
            
            row = cat_df.iloc[0]
            q = row['Question']
            a = row['Answer']
            
            if translate_this_packet:
                q_t = translate_text(q, translator)
                a_t = translate_text(a, translator)
            else:
                q_t, a_t = q, a
                
            final_topics.append({
                "name": t_name,
                "clues": [{
                    "value": None,
                    "question": q_t,
                    "answer": a_t
                }]
            })
            time.sleep(0.1)
            
        rounds.append({
            "index": 4,
            "is_final": True,
            "playable": False,
            "topics": final_topics
        })
        
        new_packages.append({
            "number": p + 1 + 6, # Assuming original were 1-6
            "title": translate_text(f"Generated Package {p+1}", translator) if translate_this_packet else f"Generated Package {p+1}",
            "subtitle": "From JEOPARDY_CSV.csv",
            "rounds": rounds
        })
        
    # Append to existing pilot.json or create new
    out_file = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'data', 'generated_pilot.json')
    
    # Read existing
    existing_file = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'data', 'pilot.json')
    if os.path.exists(existing_file):
        with open(existing_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
    else:
        data = {"packages": []}
        
    data["packages"].extend(new_packages)
    
    with open(out_file, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        
    print(f"Successfully wrote generated data to {out_file}")

if __name__ == "__main__":
    csv_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'data', 'JEOPARDY_CSV.csv')
    generate_packets(csv_path)
