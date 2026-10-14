"""Processes, fixes, swaps matrix categories, and formats the new Argon AI packages.

Writes standard packet JSONs to data/argon_packets/packet_51..61.json
and also updates new argon packets/ with the cleaned content.
"""

from __future__ import annotations

import json
import os
import sys

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))
from validate_packets import Report, check_package

ARGON_SRC_DIR = os.path.join('new argon packets')
ARGON_OUT_DIR = os.path.join('data', 'argon_packets')

ORDER = [
    ('gemini-code-1791969122006.json', 51, 'პაკეტი #1'),
    ('gemini-code-1791969138650.json', 52, 'პაკეტი #2'),
    ('gemini-code-1791969149768.json', 53, 'პაკეტი #3'),
    ('gemini-code-1791969158363.json', 54, 'პაკეტი #4'),
    ('gemini-code-1791969168562.json', 55, 'პაკეტი #5'),
    ('gemini-code-1791969176679.json', 56, 'პაკეტი #6'),
    ('gemini-code-1791970325140.json', 57, 'პაკეტი #7'),
    ('gemini-code-1791970331597.json', 58, 'პაკეტი #8'),
    ('gemini-code-1791970032977.json', 59, 'ზოგადი ერუდიცია'),
    ('gemini-code-1791970302625.json', 60, 'კლასიკური ერუდიცია'),
    ('gemini-code-1791970269835.json', 61, 'შერეული ერუდიცია'),
]


def load_raw(filename: str) -> dict:
    with open(os.path.join(ARGON_SRC_DIR, filename), encoding='utf-8') as f:
        return json.load(f)


def to_standard_packet(d: dict, num: int, subtitle: str) -> dict:
    rounds_out = []
    rounds_in = d.get('rounds', [])
    for r_idx, r in enumerate(rounds_in):
        is_final = (r_idx == 3)
        topics_in = r.get('themes') or r.get('topics') or []
        topics_out = []
        for t in topics_in:
            topics_out.append({
                'name': t['name'].strip(),
                'clues': [
                    {
                        'value': None if is_final else c.get('value'),
                        'question': c.get('question', '').strip(),
                        'answer': c.get('answer', '').strip(),
                    }
                    for c in t.get('clues', [])
                ]
            })
        rounds_out.append({
            'index': r_idx + 1,
            'header': r.get('round_name') or f'რაუნდი {r_idx+1}',
            'is_final': is_final,
            'playable': not is_final,
            'topics': topics_out
        })
    return {
        'number': num,
        'title': f'პაკეტი #{num}',
        'subtitle': subtitle,
        'source_url': 'generated:argon',
        'rounds': rounds_out
    }


def main():
    os.makedirs(ARGON_OUT_DIR, exist_ok=True)
    pkgs = []
    raw_by_file = {}
    for filename, num, sub in ORDER:
        raw = load_raw(filename)
        raw_by_file[filename] = raw
        pkgs.append(to_standard_packet(raw, num, sub))

    # --- TEXT & FACTUAL CORRECTIONS ---
    # Pkg 52 (index 1): R3 T4 C3 (მედიცინის ისტორია, ყვავილი)
    pkgs[1]['rounds'][2]['topics'][3]['clues'][2]['question'] = (
        '1796 წელს ინგლისელმა ექიმმა ედუარდ ჯენერმა მსოფლიოში პირველი ვაქცინაცია ჩაატარა, '
        'როდესაც ბიჭუნას ძროხის სნეულებით ინფიცირებული მასალა აცრა ამ მომაკვდინებელი დაავადებისგან დასაცავად. '
        'რომელი დაავადება იყო ეს?'
    )

    # Pkg 53 (index 2):
    # R2 T4 C5 (ქართული მხატვრობა, ელენე ახვლედიანი)
    pkgs[2]['rounds'][1]['topics'][3]['clues'][4]['question'] = (
        '1920-იანი წლების ქართული ავანგარდის ამ თვალსაჩინო წარმომადგენელმა ქალმა მოხატა '
        'არტისტული კაფე „ქიმერიონი“, მოგვიანებით კი კოტე მარჯანიშვილის სპექტაკლების სცენოგრაფიაზე მუშაობდა. '
        'ვინ იყო ეს ფერმწერი?'
    )
    pkgs[2]['rounds'][1]['topics'][3]['clues'][4]['answer'] = 'ელენე ახვლედიანი'
    # R3 T1 (Topic name header length)
    pkgs[2]['rounds'][2]['topics'][0]['name'] = 'ქართული სცენოგრაფია და მხატვრობა'

    # Pkg 55 (index 4):
    # R1 T2 C5 (მსოფლიო ვალუტები, რანდი)
    pkgs[4]['rounds'][0]['topics'][1]['clues'][4]['question'] = (
        'სამხრეთ აფრიკის რესპუბლიკის ოფიციალური ფულის ერთეული, რომელიც 1961 წელს შემოიღეს '
        'და საერთაშორისო კოდია ZAR. დაასახელეთ ეს ვალუტა.'
    )
    # R2 T1 C5 (XIX საუკუნის საქართველო)
    pkgs[4]['rounds'][1]['topics'][0]['clues'][4]['answer'] = 'გრიგოლ ბატონიშვილი (გრიგოლი)'
    # R3 T1 C2 (საქართველოს პირველი რესპუბლიკა)
    pkgs[4]['rounds'][2]['topics'][0]['clues'][1]['question'] = (
        'ვინ იყო ის ქართველი კომპოზიტორი და ლოტბარი, რომელმაც 1918 წელს საქართველოს დემოკრატიული '
        'რესპუბლიკის სახელმწიფო ჰიმნის — „დიდების“ ტექსტი და მუსიკა შექმნა?'
    )

    # Pkg 56 (index 5):
    # R2 T3 C5 (ქართული მეცნიერების კორიფეები)
    pkgs[5]['rounds'][1]['topics'][2]['clues'][4]['question'] = (
        'რომელმა გამოჩენილმა ქართველმა ენათმეცნიერმა შეისწავლა იბერიულ-კავკასიური ენები და '
        'გახდა რვატომიანი „ქართული ენის განმარტებითი ლექსიკონის“ მთავარი რედაქტორი?'
    )
    pkgs[5]['rounds'][1]['topics'][2]['clues'][4]['answer'] = 'არნოლდ ჩიქობავა'
    # R3 T1 C4 (ქართული ჰაგიოგრაფია და მწერლობა)
    pkgs[5]['rounds'][2]['topics'][0]['clues'][3]['question'] = (
        'მე-12-13 საუკუნეების მიჯნაზე მოღვაწე რომელი ქართველი მემატიანეა ავტორი ისტორიული '
        'თხზულებისა „ცხოვრება მეფეთ-მეფისა თამარისი“?'
    )

    # Pkg 57 (index 6):
    # R3 T2 (Header length)
    pkgs[6]['rounds'][2]['topics'][1]['name'] = 'ნობელის პრემია მედიცინაში'
    # R3 T5 C3 (გერნიკა)
    pkgs[6]['rounds'][2]['topics'][4]['clues'][2]['question'] = (
        'პაბლო პიკასოს 1937 წლის მონუმენტური ტილო ეძღვნება ესპანეთის სამოქალაქო ომის დროს '
        'ბასკეთის ამ ისტორიული ქალაქის დაბომბვას. რა ჰქვია ქალაქს?'
    )
    # R4 T1 C1 (გიორგი ერისთავი)
    pkgs[6]['rounds'][3]['topics'][0]['clues'][0]['question'] = (
        '1850 წლის 14 იანვარს თბილისში, გიმნაზიის დარბაზში კომედია „გაყრის“ დადგმით აღდგა '
        'ქართული პროფესიული თეატრი. ვინ იყო ამ პიესის ავტორი და ქართული თეატრის აღმდგენი?'
    )

    # Pkg 58 (index 7):
    # R1 T6 C2..C5 (სავაჭრო ცენტრები - questions contained answers)
    pkgs[7]['rounds'][0]['topics'][5]['clues'][1]['question'] = (
        'ევროპის რომელ ფინანსურ დედაქალაქში მდებარეობს FTSE 100 ინდექსის მქონე უძველესი '
        'საფონდო ბირჟა და ცენტრალური ფინანსური უბანი — სიტი?'
    )
    pkgs[7]['rounds'][0]['topics'][5]['clues'][2]['question'] = (
        'აზიის რომელ მეგაპოლისში მდებარეობს გინძას უბანი და Nikkei 225 ინდექსის მქონე '
        'ცნობილი საფონდო ბირჟა?'
    )
    pkgs[7]['rounds'][0]['topics'][5]['clues'][3]['question'] = (
        'გერმანიის რომელ ფინანსურ და საქმიან ცენტრში მდებარეობს DAX ინდექსის მქონე '
        'საფონდო ბირჟა და ევროპის ცენტრალური ბანკის სათავო ოფისი?'
    )
    pkgs[7]['rounds'][0]['topics'][5]['clues'][4]['question'] = (
        'ვიქტორიას პიკის ძირში მდებარე რომელ აზიურ საფინანსო ცენტრში ფუნქციონირებს '
        'Hang Seng ინდექსის მქონე მსოფლიო დონის საფონდო ბირჟა?'
    )

    # Pkg 60 (index 9):
    # R3 T4 C3 (ცისფერი მთები)
    pkgs[9]['rounds'][2]['topics'][3]['clues'][2]['question'] = (
        'ელდარ შენგელაიას 1983 წლის ალეგორიული ტრაგიკომედია, რომელშიც რედაქციაში მიტანილ '
        'ვაჟა ზაზაევიჩის მოთხრობას არავინ კითხულობს, სანამ შენობა არ დაინგრევა. რა ჰქვია ამ საკულტო ფილმს?'
    )

    # Pkg 61 (index 10):
    pkgs[10]['rounds'][0]['topics'][0]['clues'][0]['answer'] = 'ლეჰმან ბრაზერსი (ლემან ბრაზერსი)'
    pkgs[10]['rounds'][0]['topics'][1]['name'] = 'ზოგადი ერუდიცია'
    pkgs[10]['rounds'][0]['topics'][1]['clues'][2]['question'] = (
        'დიდი ზომის სამხედრო საფრენი აპარატი, რომელიც მძიმე ტექნიკისა და დესანტის '
        'გადასროლისთვის გამოიყენება. რა დანიშნულების თვითმფრინავია ეს?'
    )
    pkgs[10]['rounds'][0]['topics'][1]['clues'][2]['answer'] = 'სამხედრო-სატრანსპორტო'
    pkgs[10]['rounds'][1]['topics'][0]['name'] = 'ანტიკური საბერძნეთი'
    pkgs[10]['rounds'][1]['topics'][1]['clues'][3]['question'] = (
        'შუა საუკუნეების ცნობილი შვეიცარიელი ექიმი, ალქიმიკოსი და ბუნებისმეტყველი, რომლის '
        'ნამდვილი სახელი იყო ფილიპუს აურეოლუს თეოფრასტუს ბომბასტუს ფონ ჰოჰენჰაიმი. რა სახელით იცნობს მას მსოფლიო?'
    )

    # --- MATRIX CATEGORY SWAPS ---
    # Swap 1: Pkg 59 (index 8) <-> Pkg 51 (index 0)
    # R1: swap p59 T2 (მატრიცული "მონ") with p51 T3 (ქიმიური ელემენტები)
    pkgs[8]['rounds'][0]['topics'][1], pkgs[0]['rounds'][0]['topics'][2] = (
        pkgs[0]['rounds'][0]['topics'][2], pkgs[8]['rounds'][0]['topics'][1]
    )
    # R2: swap p59 T2 (მატრიცული "რონ") with p51 T2 (კოსმოსი და ასტრონომია)
    pkgs[8]['rounds'][1]['topics'][1], pkgs[0]['rounds'][1]['topics'][2] = (
        pkgs[0]['rounds'][1]['topics'][2], pkgs[8]['rounds'][1]['topics'][1]
    )
    # R3: swap p59 T2 (მატრიცული "მორ") with p51 T1 (ცნობილი სრუტეები)
    pkgs[8]['rounds'][2]['topics'][1], pkgs[0]['rounds'][2]['topics'][1] = (
        pkgs[0]['rounds'][2]['topics'][1], pkgs[8]['rounds'][2]['topics'][1]
    )

    # Swap 2: Pkg 60 (index 9) <-> Pkg 52 (index 1)
    # R1: swap p60 T2 (მატრიცული "კარ") with p52 T2 (ჭადრაკი)
    pkgs[9]['rounds'][0]['topics'][1], pkgs[1]['rounds'][0]['topics'][2] = (
        pkgs[1]['rounds'][0]['topics'][2], pkgs[9]['rounds'][0]['topics'][1]
    )
    # R2: swap p60 T2 (მატრიცული "რონ") with p52 T2 (ვალუტა და ფული)
    pkgs[9]['rounds'][1]['topics'][1], pkgs[1]['rounds'][1]['topics'][2] = (
        pkgs[1]['rounds'][1]['topics'][2], pkgs[9]['rounds'][1]['topics'][1]
    )
    # R3: swap p60 T2 (მატრიცული "მარ") with p52 T4 (უდაბნოები)
    pkgs[9]['rounds'][2]['topics'][1], pkgs[1]['rounds'][2]['topics'][4] = (
        pkgs[1]['rounds'][2]['topics'][4], pkgs[9]['rounds'][2]['topics'][1]
    )

    # Swap 3: Pkg 61 (index 10) <-> Pkg 53 (index 2)
    # R1: swap p61 T0 (მატრიცული "ლემ") with p53 T2 (მსოფლიო მთები და მწვერვალები)
    pkgs[10]['rounds'][0]['topics'][0], pkgs[2]['rounds'][0]['topics'][2] = (
        pkgs[2]['rounds'][0]['topics'][2], pkgs[10]['rounds'][0]['topics'][0]
    )
    # R2: swap p61 T1 (მატრიცული "პარ") with p53 T5 (კულინარიული გეოგრაფია)
    pkgs[10]['rounds'][1]['topics'][1], pkgs[2]['rounds'][1]['topics'][5] = (
        pkgs[2]['rounds'][1]['topics'][5], pkgs[10]['rounds'][1]['topics'][1]
    )
    # R3: swap p61 T0 (მატრიცული "ტრა") with p53 T2 (მათემატიკის სამყარო)
    pkgs[10]['rounds'][2]['topics'][0], pkgs[2]['rounds'][2]['topics'][2] = (
        pkgs[2]['rounds'][2]['topics'][2], pkgs[10]['rounds'][2]['topics'][0]
    )

    # Validate all packages before saving
    seen = {}
    for p in pkgs:
        rep = Report(f"packet_{p['number']}")
        check_package(p, rep, seen)
        if not rep.ok:
            print(f"Validation FAILED for {p['title']}:")
            for err in rep.errors:
                print(f"  {err}")
            sys.exit(1)

    print("All 11 packages passed validation!")

    # Write data/argon_packets/packet_*.json
    for p in pkgs:
        out_path = os.path.join(ARGON_OUT_DIR, f"packet_{p['number']}.json")
        with open(out_path, 'w', encoding='utf-8') as f:
            json.dump(p, f, ensure_ascii=False, indent=2)
            f.write('\n')
        print(f"Wrote {out_path}")

    # Also update files in new argon packets/ to reflect the cleaned and swapped contents
    for idx, (filename, num, sub) in enumerate(ORDER):
        fpath = os.path.join(ARGON_SRC_DIR, filename)
        with open(fpath, 'w', encoding='utf-8') as f:
            json.dump(pkgs[idx], f, ensure_ascii=False, indent=2)
            f.write('\n')
        print(f"Updated {fpath}")


if __name__ == '__main__':
    main()
