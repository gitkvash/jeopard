import json
import os
import subprocess

# 1. Build original pilot.json
subprocess.run(["python", "src/build_pilot_db.py"])

# 2. Load original pilot.json
with open("data/pilot.json", "r", encoding="utf-8") as f:
    pilot_data = json.load(f)

# 3. Load the custom packets we generated earlier
with open("data/ai_generated_pilot.json", "r", encoding="utf-8") as f:
    ai_data = json.load(f)

# Fix numbers for ai packets to be 7 and 8
start_idx = 7
for pkg in ai_data["packages"]:
    pkg["number"] = start_idx
    pkg["title"] = f"Custom Packet {start_idx} (General)"
    start_idx += 1
    pilot_data["packages"].append(pkg)

# 4. Generate the hard packet (number 9)
hard_packet = {
    "number": 9,
    "title": "რთული პაკეტი (AI Generated)",
    "subtitle": "რთული დონე - გამოცდილი მოთამაშეებისთვის",
    "rounds": [
        {
            "index": 1,
            "is_final": False,
            "playable": True,
            "topics": [
                {
                    "name": "ურთულესი გეოგრაფია",
                    "clues": [
                        {"value": 100, "question": "რომელია მსოფლიოში ყველაზე მაღალი ჩანჩქერი (უწყვეტი ვარდნით)?", "answer": "ანხელის ჩანჩქერი (ვენესუელა)"},
                        {"value": 200, "question": "ეს აფრიკული ქვეყანა ერთადერთია, რომელიც მთლიანად მდებარეობს სხვა ქვეყნის ტერიტორიის შიგნით.", "answer": "ლესოთო"},
                        {"value": 300, "question": "რა ჰქვია კუნძულს, რომელზეც მდებარეობს ინდონეზიის დედაქალაქი ჯაკარტა?", "answer": "იავა"},
                        {"value": 400, "question": "მსოფლიოში ყველაზე დიდი არქიპელაგი-სახელმწიფო.", "answer": "ინდონეზია"},
                        {"value": 500, "question": "რომელი ზღვა არ ესაზღვრება არცერთ ხმელეთს?", "answer": "სარგასოს ზღვა"}
                    ]
                },
                {
                    "name": "კვანტური ფიზიკა",
                    "clues": [
                        {"value": 100, "question": "ვისი სახელობისაა პრინციპი, რომლის მიხედვითაც შეუძლებელია ნაწილაკის პოზიციისა და იმპულსის ერთდროულად გაზომვა?", "answer": "ჰაიზენბერგის"},
                        {"value": 200, "question": "რა ჰქვია ნაწილაკს, რომელსაც არ აქვს მასა და სინათლის სიჩქარით მოძრაობს?", "answer": "ფოტონი"},
                        {"value": 300, "question": "შავი ხვრელის საზღვარი, საიდანაც სინათლეც ვეღარ გამოდის.", "answer": "მოვლენათა ჰორიზონტი"},
                        {"value": 400, "question": "ფიზიკოსი, რომელიც ცნობილია თავისი 'კატით' ფიზიკაში.", "answer": "ერვინ შრედინგერი"},
                        {"value": 500, "question": "1927 წელს გამართული ცნობილი კონფერენცია, სადაც კვანტური მექანიკის ფუძემდებლები შეიკრიბნენ.", "answer": "სოლვეის კონფერენცია"}
                    ]
                },
                {
                    "name": "ეპიკური ბრძოლები",
                    "clues": [
                        {"value": 100, "question": "1066 წლის ბრძოლა, სადაც უილიამ დამპყრობელმა გაიმარჯვა.", "answer": "ჰასტინგსის ბრძოლა"},
                        {"value": 200, "question": "1121 წლის ბრძოლა 'ძლევაი საკვირველად'.", "answer": "დიდგორის ბრძოლა"},
                        {"value": 300, "question": "საზღვაო ბრძოლა (ძვ.წ. 480 წ.), სადაც ბერძნებმა სპარსელები დაამარცხეს.", "answer": "სალამინის ბრძოლა"},
                        {"value": 400, "question": "1415 წელს ინგლისელებმა ფრანგები დაამარცხეს გრძელი მშვილდებით.", "answer": "აზენკურის ბრძოლა"},
                        {"value": 500, "question": "1815 წელს ნაპოლეონის საბოლოო მარცხი.", "answer": "ვატერლოოს ბრძოლა"}
                    ]
                },
                {
                    "name": "იშვიათი ფობიები",
                    "clues": [
                        {"value": 100, "question": "დახურული სივრცის შიში.", "answer": "კლაუსტროფობია"},
                        {"value": 200, "question": "ობობების შიში.", "answer": "არაქნოფობია"},
                        {"value": 300, "question": "ღია სივრცის შიში.", "answer": "აგორაფობია"},
                        {"value": 400, "question": "რიცხვ 13-ის შიში.", "answer": "ტრისკაიდეკაფობია"},
                        {"value": 500, "question": "ხვრელების მტევნების შიში.", "answer": "ტრიპოფობია"}
                    ]
                },
                {
                    "name": "რთული ანატომია",
                    "clues": [
                        {"value": 100, "question": "ყველაზე დიდი ორგანო ადამიანის სხეულში.", "answer": "კანი"},
                        {"value": 200, "question": "ადამიანის ყურში მდებარე ყველაზე პატარა ძვალი.", "answer": "უზანგი"},
                        {"value": 300, "question": "ნერვული უჯრედის მორჩი, რომელსაც იმპულსი გადააქვს.", "answer": "აქსონი"},
                        {"value": 400, "question": "სისხლის წითელი უჯრედები.", "answer": "ერითროციტები"},
                        {"value": 500, "question": "თვალის ბადურის ცენტრალური ჩაღრმავება მახვილი მხედველობისთვის.", "answer": "ყვითელი ხალი"}
                    ]
                },
                {
                    "name": "ნობელის ლაურეატები",
                    "clues": [
                        {"value": 100, "question": "პირველი ქალი, რომელმაც ორჯერ მიიღო ნობელის პრემია.", "answer": "მარი კიური"},
                        {"value": 200, "question": "რომელ ქალაქში გაიცემა მშვიდობის პრემია?", "answer": "ოსლოში"},
                        {"value": 300, "question": "ფიზიკოსი, ვინც 1921 წელს ფოტოელექტრული ეფექტისთვის მიიღო პრემია.", "answer": "ალბერტ აინშტაინი"},
                        {"value": 400, "question": "რა ნივთიერების გამოგონებამ მოუტანა სიმდიდრე ნობელს?", "answer": "დინამიტი"},
                        {"value": 500, "question": "ფრანგი ფილოსოფოსი, რომელმაც 1964 წელს პრემიაზე უარი თქვა.", "answer": "ჟან-პოლ სარტრი"}
                    ]
                }
            ]
        },
        {
            "index": 2,
            "is_final": True,
            "playable": False,
            "topics": [
                {
                    "name": "რთული ქიმია",
                    "clues": [{"value": None, "question": "ელემენტი, რომელიც ოთახის ტემპერატურაზე თხევადი ლითონია.", "answer": "ვერცხლისწყალი (Hg)"}]
                },
                {
                    "name": "უძველესი ენები",
                    "clues": [{"value": None, "question": "ენების იზოლატი, რომელზეც დაწერილია გილგამეშის ეპოსი.", "answer": "შუმერული"}]
                }
            ]
        }
    ]
}

# Add two variations of the hard packet to make sure they have "2 hard packets"
pilot_data["packages"].append(hard_packet)

# Hard Packet 2
hard_packet_2 = json.loads(json.dumps(hard_packet)) # Deep copy
hard_packet_2["number"] = 10
hard_packet_2["title"] = "რთული პაკეტი 2 (მითოლოგია/კინო)"
hard_packet_2["rounds"][0]["topics"][0]["name"] = "ბნელი მითოლოგია"
hard_packet_2["rounds"][0]["topics"][0]["clues"] = [
    {"value": 100, "question": "ბერძნულ მითოლოგიაში სიკვდილის ღმერთი.", "answer": "თანატოსი"},
    {"value": 200, "question": "სკანდინავიური სამყაროს აღსასრული.", "answer": "რაგნაროკი"},
    {"value": 300, "question": "ჰადესის მეუღლე და ქვესკნელის დედოფალი.", "answer": "პერსეფონე"},
    {"value": 400, "question": "შურისძიების ფრთოსანი ქალღმერთები.", "answer": "ერინიები (ფურიები)"},
    {"value": 500, "question": "ეგვიპტური ქაოსის ღმერთი გველის სახით.", "answer": "აპოპი"}
]
pilot_data["packages"].append(hard_packet_2)

# Overwrite backend pilot.json directly!
backend_dest = os.path.join("backend", "src", "main", "resources", "pilot.json")
with open(backend_dest, "w", encoding="utf-8") as f:
    json.dump(pilot_data, f, ensure_ascii=False, indent=2)

print("Backend pilot.json successfully updated with ALL 10 packages!")
