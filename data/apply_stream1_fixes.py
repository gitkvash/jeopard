# -*- coding: utf-8 -*-
import json
import os
import sys

sys.stdout.reconfigure(encoding='utf-8')

scratch = r'C:\Users\giorg\AppData\Local\Temp\claude\C--Users-giorg--claude-spares-spare-eJfFr2\74c5f353-67f8-4552-9b72-d9014f3e79b0\scratchpad'

# 1. 96a
p96a = os.path.join(scratch, 'write', '96a', 'written.json')
d96a = json.load(open(p96a, encoding='utf-8'))
for c in d96a['clues']:
    if c['slot_id'] == '2.R1.C2.500':
        c['question'] = '1977 წელს გამოსულმა ალბომმა „Rumours“, რომელიც ჯგუფის წევრებს შორის რთული პირადი დაშორებების ფონზე ჩაიწერა, 40 მილიონზე მეტი ეგზემპლარი გაყიდა. დაასახელეთ ეს ბრიტანულ-ამერიკული როკ-ჯგუფი.'
        c['answer'] = 'Fleetwood Mac („ფლიტვუდ მეკი“)'
        c['searched_terms'] = ['Fleetwood Mac', 'Rumours']
        c['fact_note_en'] = 'Fleetwood Mac released Rumours in 1977.'
json.dump(d96a, open(p96a, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
print('Updated 96a')

# 2. 96b
p96b = os.path.join(scratch, 'write', '96b', 'written.json')
d96b = json.load(open(p96b, encoding='utf-8'))
for c in d96b['clues']:
    if c['slot_id'] == '5.R2.C6.1000':
        c['question'] = 'ხევსურული ტრადიციული ხალხური სამოსი, რომელიც გეომეტრიული ჯვრებითა და ფერადი ორნამენტებით მორთული შალის ტანსაცმელია და მამაკაცის სრულ საბრძოლო აღკაზმულობას მოიცავს.'
        c['answer'] = 'ტალავარი (ხევსურული ტალავარი)'
        c['searched_terms'] = ['ტალავარი', 'ხევსურული ტალავარი']
        c['fact_note_en'] = 'Talavari is traditional Khevsurian embroidered woolen national costume.'
json.dump(d96b, open(p96b, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
print('Updated 96b')

# 3. 96c
p96c = os.path.join(scratch, 'write', '96c', 'written.json')
d96c = json.load(open(p96c, encoding='utf-8'))
for c in d96c['clues']:
    if c['slot_id'] == '2.R2.C2.200':
        c['question'] = 'ფლორენციული რენესანსის ამ ოსტატს ეკუთვნის ცნობილი შედევრები „ვენერას დაბადება“ და „პრიმავერა“ (გაზაფხული), რომლებიც უფიცის გალერეაში ინახება.'
        c['answer'] = 'სანდრო ბოტიჩელი (Sandro Botticelli)'
        c['searched_terms'] = ['ბოტიჩელი', 'Botticelli']
        c['fact_note_en'] = 'Sandro Botticelli painted The Birth of Venus and Primavera.'
    elif c['slot_id'] == '2.R2.C2.400':
        c['question'] = 'ფრანგი მოქანდაკე, მოდერნისტული სკულპტურის მამა, რომლის ყველაზე ცნობილი ქანდაკება — ნიკაპზე ხელით დაყრდნობილი „მოაზროვნე“ — თავდაპირველად „ჯოჯოხეთის კარიბჭის“ კომპოზიციისთვის შეიქმნა.'
        c['answer'] = 'ოგიუსტ როდენი (Auguste Rodin)'
        c['searched_terms'] = ['როდენი', 'Rodin']
        c['fact_note_en'] = 'Auguste Rodin created The Thinker.'
    elif c['slot_id'] == '2.R2.C2.600':
        c['question'] = 'ჩრდილოური რენესანსის ამ გერმანელმა დიდოსტატმა შექმნა გრავიურა „რაინდი, სიკვდილი და ეშმაკი“, აგრეთვე განთქმული ნახატი „მლოცველი ხელები“ და ცნობილი ქსილოგრაფია „მარტორქა“.'
        c['answer'] = 'ალბრეხტ დიურერი (Albrecht Dürer)'
        c['searched_terms'] = ['დიურერი', 'Durer']
        c['fact_note_en'] = 'Albrecht Dürer created Knight, Death and the Devil, Praying Hands and Rhinoceros.'
json.dump(d96c, open(p96c, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
print('Updated 96c')

# 4. 97b
p97b = os.path.join(scratch, 'write', '97b', 'written.json')
d97b = json.load(open(p97b, encoding='utf-8'))
for c in d97b['clues']:
    if c['slot_id'] == '5.R1.C4.100':
        c['question'] = 'ბერძნული და ბალკანური სამზარეულოს ეს ტრადიციული ფენოვანი ცხელი კერძი ძირითადად შემწვარი ბადრიჯნის, დაკეპილი ხორცისა (ხშირად ცხვრის) და ზემოდან ბეშამელის სოუსის ფენებით ცხვება.'
        c['answer'] = 'მუსაკა (Moussaka)'
        c['searched_terms'] = ['მუსაკა', 'Moussaka']
        c['fact_note_en'] = 'Moussaka is an eggplant- or potato-based baked dish.'
json.dump(d97b, open(p97b, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
print('Updated 97b')

# 5. 97c
p97c = os.path.join(scratch, 'write', '97c', 'written.json')
d97c = json.load(open(p97c, encoding='utf-8'))
for c in d97c['clues']:
    if c['slot_id'] == '3.R2.C2.600':
        c['question'] = 'პოსტიმპრესიონიზმის ამ ფრანგმა ოსტატმა, რომელსაც პიკასო „ჩვენი ყველას მამას“ უწოდებდა, თავისი მშობლიური ექს-ან-პროვანსის მახლობლად მდებარე მთა სენტ-ვიქტუარი ათეულობით ტილოზე აღბეჭდა.'
        c['answer'] = 'პოლ სეზანი (Paul Cézanne)'
        c['searched_terms'] = ['სეზანი', 'Cezanne']
        c['fact_note_en'] = 'Paul Cézanne was a French Post-Impressionist painter known for Mont Sainte-Victoire.'
    elif c['slot_id'] == '5.R2.C3.1000':
        c['question'] = 'ვენის სამშობიარო კლინიკაში მომუშავე ამ უნგრელმა ექიმმა 1847 წელს აღმოაჩინა, რომ სამშობიარო ცხელებით სიკვდილიანობა მკვეთრად მცირდებოდა ექიმების მიერ ხელების ქლორიანი წყლით დაბანის შემთხვევაში, რის გამოც მას „დედათა მხსნელი“ უწოდეს.'
        c['answer'] = 'იგნაც სემელვეისი (Ignaz Semmelweis)'
        c['searched_terms'] = ['სემელვეისი', 'Semmelweis']
        c['fact_note_en'] = 'Ignaz Semmelweis discovered antiseptic prophylaxis.'
json.dump(d97c, open(p97c, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
print('Updated 97c')

# 6. Compose 96
pcomp96 = os.path.join(scratch, 'compose', 'packet_96.json')
dcomp96 = json.load(open(pcomp96, encoding='utf-8'))
for r in dcomp96['rounds']:
    for t in r['topics']:
        for c in t['clues']:
            if c['src'] == '2.R1.C3.100':
                c['question'] = 'მანჰეტენის სამხრეთით, ლიბერტის კუნძულზე აღმართული ეს მონუმენტური ნეოკლასიკური ქანდაკება ამერიკის შეერთებულ შტატებს საფრანგეთმა აჩუქა. რომელ ქალაქში მდებარეობს ის?'
                c['answer'] = 'ნიუ-იორკი'
            elif c['src'] == '2.R1.C3.300':
                c['question'] = 'მდინარე ვლტავაზე გადებული მე-14 საუკუნის ეს ცნობილი ისტორიული ხიდი 30 ბაროკოს ქანდაკებითაა დამშვენებული. რომელ ჩეხურ დედაქალაქში ვხვდებით მას?'
                c['answer'] = 'პრაღა'
            elif c['src'] == '4.R2.C3.200':
                c['question'] = '1998 წელს ლარი პეიჯისა და სერგეი ბრინის მიერ კალიფორნიაში დაარსებული ეს ტექნოლოგიური გიგანტი თავდაპირველად სტენფორდის უნივერსიტეტის კვლევითი პროექტი იყო.'
                c['answer'] = 'Google (გუგლი)'
            elif c['src'] == '2.R2.C6.200':
                c['question'] = 'ქართული იგავ-არაკების კრებულის — „სიბრძნე სიცრუისა“ და პირველი ქართული განმარტებითი ლექსიკონის — „სიტყვის კონის“ ავტორი.'
                c['answer'] = 'სულხან-საბა ორბელიანი'
json.dump(dcomp96, open(pcomp96, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
print('Updated compose 96')

# 7. Compose 97
pcomp97 = os.path.join(scratch, 'compose', 'packet_97.json')
dcomp97 = json.load(open(pcomp97, encoding='utf-8'))
for r in dcomp97['rounds']:
    for t in r['topics']:
        for c in t['clues']:
            if c['src'] == '4.R1.C3.100':
                c['question'] = 'ვესტმინსტერის სასახლის ჩრდილოეთ ბოლოში მდებარე ელიზაბეთის კოშკის საკულტო დიდი საათი და მისი ცნობილი 13-ტონიანი ზარი ამ ბრიტანული დედაქალაქის მთავარი სიმბოლოა.'
                c['answer'] = 'ლონდონი'
            elif c['src'] == '3.R1.C3.300':
                c['question'] = 'რიო-დე-ჟანეიროს რომელი პლაჟის ბულვარი ცნობილია ტალღისებური შავ-თეთრი მოზაიკით?'
                c['answer'] = 'კოპაკაბანა'
            elif c['src'] == '3.R1.C3.500':
                c['question'] = '26 ატოლზე განფენილი ეს ტროპიკული არქიპელაგი ზღვის დონიდან საშუალოდ მხოლოდ 1.5 მეტრ სიმაღლეზე მდებარეობს, რაც მას პლანეტის ყველაზე დაბალ ქვეყნად აქცევს.'
                c['answer'] = 'მალდივები (მალდივის რესპუბლიკა)'
            elif c['src'] == '5.R1.C4.200':
                c['question'] = 'იაპონური სამზარეულოს ეს მწვანე ცხარე პასტა, რომელსაც სუშისთან ერთად მიირთმევენ, ევტრემასებრთა მცენარის გახეხილი ფესვისგან მზადდება.'
                c['answer'] = 'ვასაბი (Wasabi)'
            elif c['src'] == '5.R1.C4.500':
                c['question'] = '1832 წელს ვენაში ახალგაზრდა კონდიტერმა ფრანც ზახერმა მეტერნიხის სასახლისთვის შექმნა ეს ცნობილი შოკოლადის ტორტი გარგარის ჯემის თხელი ფენითა და მუქი შოკოლადის მინანქრით.'
                c['answer'] = 'ზახერი (ზახერის ტორტი / Sachertorte)'
            elif c['src'] == '3.R2.C5.1000':
                c['question'] = 'ჩეხეთი, უნგრეთი, სლოვაკეთი, პოლონეთი'
                c['answer'] = 'პოლონეთი — ზღვაზე გასასვლელი აქვს, დანარჩენს არა'
            elif c['src'] == '3.R2.C6.200':
                c['question'] = 'მტკვრისა და არაგვის შესართავთან გაშენებული საქართველოს ეს უძველესი დედაქალაქი XI საუკუნის საპატრიარქო ტაძრის — სვეტიცხოვლის სამყოფელია.'
                c['answer'] = 'მცხეთა'
json.dump(dcomp97, open(pcomp97, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
print('Updated compose 97')
