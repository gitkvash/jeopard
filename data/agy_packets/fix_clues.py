import json

path = r'C:\Users\giorg\Desktop\jeopard\data\agy_packets\packet_13.json'

with open(path, 'r', encoding='utf-8') as f:
    data = json.load(f)

for round_idx, r in enumerate(data['rounds']):
    for topic_idx, t in enumerate(r['topics']):
        for clue_idx, c in enumerate(t['clues']):
            # 1. Pippi Longstocking
            if "ვილა „ყივჩაღში“" in c['question']:
                c['question'] = c['question'].replace("ვილა „ყივჩაღში“", "ვილა „ყიყლიყოში“")
            
            # 2. 2001
            if c['answer'] == "2001":
                c['answer'] = "ორი ათას ერთი"
                
            # 3. 1984
            if c['answer'] == "1984":
                c['answer'] = "ათას ცხრაას ოთხმოცდაოთხი"
                
            # 4. Remarque All Quiet
            if "სადებიუტო რომანში" in c['question'] and "რემარკის" in c['question']:
                c['question'] = c['question'].replace("სადებიუტო რომანში", "ცნობილ რომანში")
                
            # 5. Jonathan Swift
            if "ამ ირლანდიული წარმოშობის ინგლისელმა ავტორმა" in c['question']:
                c['question'] = c['question'].replace("ამ ირლანდიული წარმოშობის ინგლისელმა ავტორმა", "ამ ანგლო-ირლანდიელმა მწერალმა")
                
            # 6. Mrs Dalloway
            if "სათაური მთავარი პერსონაჟის სახელსა და გვარს წარმოადგენს." in c['question']:
                c['question'] = c['question'].replace("სათაური მთავარი პერსონაჟის სახელსა და გვარს წარმოადგენს.", "სათაურში მთავარი პერსონაჟის გვარი ფიგურირებს.")
                
            # 7. Pasternak
            if "ამ რუს მწერალს ნობელის პრემია მიანიჭეს რომანისთვის „ექიმი ჟივაგო“," in c['question']:
                c['question'] = c['question'].replace(
                    "ამ რუს მწერალს ნობელის პრემია მიანიჭეს რომანისთვის „ექიმი ჟივაგო“,",
                    "ამ რუს მწერალს, რომელიც რომანის „ექიმი ჟივაგო“ ავტორია, ნობელის პრემია მიანიჭეს,"
                )
                
            # 8. Zweig
            if "ეს ნოველა მოგვითხრობს ორ იდუმალ მოთამაშეზე, რომლებიც სამგზავრო გემზე ერთმანეთს ინტელექტუალურად უპირისპირდებიან" in c['question']:
                c['question'] = c['question'].replace(
                    "ეს ნოველა მოგვითხრობს ორ იდუმალ მოთამაშეზე, რომლებიც სამგზავრო გემზე ერთმანეთს ინტელექტუალურად უპირისპირდებიან",
                    "ეს ნაწარმოები მოგვითხრობს ორ ადამიანზე, რომლებიც სამგზავრო გემზე ერთმანეთს ცნობილ ინტელექტუალურ თამაშში უპირისპირდებიან"
                )
                
            # 9. Galaktion Tabidze
            if "ეს ქართველი პოეტი, „ცისფერყანწელთა“ ორდენის ერთ-ერთი ფუძემდებელი," in c['question']:
                c['question'] = c['question'].replace(
                    "ეს ქართველი პოეტი, „ცისფერყანწელთა“ ორდენის ერთ-ერთი ფუძემდებელი,",
                    "ეს ქართველი პოეტი"
                )
                
            # 10. Rashomon
            if "იაპონელმა ავტორმა რიუნოსუკე აკუტაგავამ თავის ცნობილ მოთხრობაში ერთი დანაშაული აღწერა ოთხი სხვადასხვა თვითმხილველის თვალით. ამ მოთხრობის სახელი შემდგომში ფსიქოლოგიურ ფენომენს დაერქვა." in c['question']:
                c['question'] = "რიუნოსუკე აკუტაგავას ამ მოთხრობის მოქმედება კიოტოს დანგრეულ კარიბჭესთან ვითარდება, სადაც მსახური ხვდება მოხუც ქალს. ამ ნაწარმოების სახელი ეწოდა აკირა კუროსავას ცნობილ ფილმსა და ფსიქოლოგიურ ფენომენს."

with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    # Add a trailing newline if it's missing just in case
    f.write('\n')

print("Modifications complete.")
