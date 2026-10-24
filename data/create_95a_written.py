# -*- coding: utf-8 -*-
"""Create 95a written.json with verified, zero-collision Georgian Jeopardy clues."""
import json
import os
import sys

sys.stdout.reconfigure(encoding='utf-8')

out_path = r'C:\Users\giorg\AppData\Local\Temp\claude\C--Users-giorg--claude-spares-spare-eJfFr2\74c5f353-67f8-4552-9b72-d9014f3e79b0\scratchpad\write\95a\written.json'

clues = [
    # ----------------------------------------------------
    # Topic: კინოს ჯადოსნური ფაბრიკა
    # ----------------------------------------------------
    {
        "slot_id": "1.R1.C1.300",
        "topic": "კინოს ჯადოსნური ფაბრიკა",
        "question": "2001 წელს ჰაიაო მიაძაკის მიერ შექმნილი ეს საკულტო ანიმაცია გახდა პირველი და ერთადერთი არაინგლისურენოვანი ნამუშევარი, რომელმაც ოსკარი საუკეთესო ანიმაციური ფილმის კატეგორიაში მოიპოვა.",
        "answer": "„მოტაცებული აჩრდილების მიერ“ (Spirited Away)",
        "searched_terms": ["მოტაცებული აჩრდილების მიერ", "მიაძაკი"],
        "fact_note_en": "Spirited Away won Best Animated Feature at the 75th Academy Awards in 2003."
    },
    {
        "slot_id": "1.R1.C1.400",
        "topic": "კინოს ჯადოსნური ფაბრიკა",
        "question": "ტიმ ბარტონის თითქმის ყველა ფილმის, მათ შორის „ბეტმენისა“ და „ედვარდ მაკრატელხელებას“, აგრეთვე „სიმფსონების“ საკულტო შესავალი მელოდიის ავტორი ეს ამერიკელი კომპოზიტორია.",
        "answer": "დენი ელფმანი (Danny Elfman)",
        "searched_terms": ["დენი ელფმან", "Danny Elfman"],
        "fact_note_en": "Danny Elfman composed Batman, Edward Scissorhands and The Simpsons theme."
    },
    {
        "slot_id": "1.R1.C1.500",
        "topic": "კინოს ჯადოსნური ფაბრიკა",
        "question": "1940 წლის ამ ანტიფაშისტურ სატირულ ფილმში ჩარლი ჩაპლინმა კინოკარიერაში პირველად წარმოთქვა ხმოვანი სიტყვა ეკრანზე და ორი როლი შეასრულა.",
        "answer": "„დიდი დიქტატორი“ (The Great Dictator)",
        "searched_terms": ["დიდი დიქტატორ", "The Great Dictator"],
        "fact_note_en": "The Great Dictator (1940) was Charlie Chaplin's first true sound film."
    },

    # ----------------------------------------------------
    # Topic: ჰანგები და მელოდიები
    # ----------------------------------------------------
    {
        "slot_id": "1.R1.C2.100",
        "topic": "ჰანგები და მელოდიები",
        "question": "იამაიკელმა ამ მუსიკოსმა და მისმა ჯგუფმა The Wailers-მა რეგის ჟანრი მთელ მსოფლიოში პოპულარული გახადა ისეთი ჰიტებით, როგორებიცაა „No Woman, No Cry“ და „One Love“.",
        "answer": "ბობ მარლი (Bob Marley)",
        "searched_terms": ["ბობ მარლ", "Bob Marley"],
        "fact_note_en": "Bob Marley & The Wailers popularized reggae globally."
    },
    {
        "slot_id": "1.R1.C2.200",
        "topic": "ჰანგები და მელოდიები",
        "question": "პეტრე ჩაიკოვსკის ბალეტ „მაკნატუნას“ ამ ცნობილ ცეკვაში კომპოზიტორმა პარიზში ახლად გამოგონილი ზარებისებრი ხმის მქონე კლავიშიანი საკრავი — ჩელესტა გამოიყენა.",
        "answer": "„შაქრის ფერიის ცეკვა“ (Dance of the Sugar Plum Fairy)",
        "searched_terms": ["შაქრის ფერია", "ჩელესტა"],
        "fact_note_en": "Tchaikovsky introduced the celesta in Dance of the Sugar Plum Fairy."
    },
    {
        "slot_id": "1.R1.C2.400",
        "topic": "ჰანგები და მელოდიები",
        "question": "ავსტრალიის აბორიგენების ეს უძველესი ჩასაბერი საკრავი ტრადიციულად ტერმიტების მიერ გამოფუღროებული ევკალიპტის ხის ტოტებისგან მზადდება.",
        "answer": "დიჯერიდუ (Didgeridoo)",
        "searched_terms": ["დიჯერიდუ", "Didgeridoo"],
        "fact_note_en": "The didgeridoo is an Aboriginal Australian wind instrument made from termite-hollowed eucalyptus."
    },
    {
        "slot_id": "1.R1.C2.500",
        "topic": "ჰანგები და მელოდიები",
        "question": "ფრანგი კომპოზიტორის, კამილ სენ-სანსის ამ სიმფონიურ პოემაში შუაღამისას ჩონჩხების ცეკვას ქსილოფონის ხმები (ძვლების კაკუნი) და სოლისტის ვიოლინოს დისონანსი ასახავს.",
        "answer": "„სიკვდილის ცეკვა“ (Danse macabre)",
        "searched_terms": ["Danse macabre", "სიკვდილის ცეკვა"],
        "fact_note_en": "Camille Saint-Saëns composed Danse macabre (1874) using xylophone to represent rattling bones."
    },

    # ----------------------------------------------------
    # Topic: მსოფლიოს გარშემო
    # ----------------------------------------------------
    {
        "slot_id": "1.R1.C3.100",
        "topic": "მსოფლიოს გარშემო",
        "question": "ნიდერლანდების ამ დედაქალაქს 160-ზე მეტი არხი, 1500-ზე მეტი ხიდი და მცხოვრებლებზე მეტი ველოსიპედი აქვს.",
        "answer": "ამსტერდამი (Amsterdam)",
        "searched_terms": ["ამსტერდამ"],
        "fact_note_en": "Amsterdam has over 160 canals and 1500 bridges."
    },
    {
        "slot_id": "1.R1.C3.200",
        "topic": "მსოფლიოს გარშემო",
        "question": "მექსიკის იუკატანის ნახევარკუნძულზე მდებარე მაიას ამ წმინდა ქალაქში კუკულკანის პირამიდა ბუნიობის დღეებში ჩრდილების მეშვეობით მოძრავი გველის ოპტიკურ ილუზიას ქმნის.",
        "answer": "ჩიჩენ-იცა (Chichen Itza)",
        "searched_terms": ["ჩიჩენ-იც", "Chichen Itza"],
        "fact_note_en": "El Castillo pyramid at Chichen Itza creates the illusion of a descending feathered serpent at equinox."
    },
    {
        "slot_id": "1.R1.C3.400",
        "topic": "მსოფლიოს გარშემო",
        "question": "თურქეთის ცენტრალურ ანატოლიაში მდებარე ეს ისტორიული რეგიონი ცნობილია ვულკანური ტუფისგან წარმოქმნილი „ზღაპრული საკვამურებით“, მიწისქვეშა ქალაქებითა და ასობით საჰაერო ბურთით.",
        "answer": "კაპადოკია (Cappadocia)",
        "searched_terms": ["კაპადოკი", "Cappadocia"],
        "fact_note_en": "Cappadocia is famous for fairy chimneys and hot air ballooning."
    },
    {
        "slot_id": "1.R1.C3.500",
        "topic": "მსოფლიოს გარშემო",
        "question": "საბერძნეთის თესალიაში მდებარე ეს უნიკალური კომპლექსი მოიცავს გიგანტურ ქვიშაქვის ბუნებრივ სვეტებზე აგებულ მართლმადიდებლურ სამონასტრო კომპლექსს, რომლის სახელიც ბერძნულად „ცაში გამოკიდებულს“ ნიშნავს.",
        "answer": "მეტეორა (მეტეორას მონასტრები / Meteora)",
        "searched_terms": ["მეტეორა", "Meteora"],
        "fact_note_en": "Meteora is a rock formation in central Greece hosting Eastern Orthodox monasteries."
    },

    # ----------------------------------------------------
    # Topic: გემრიელი კითხვები
    # ----------------------------------------------------
    {
        "slot_id": "1.R1.C4.100",
        "topic": "გემრიელი კითხვები",
        "question": "ახლო აღმოსავლეთის ეს პოპულარული ქუჩის საჭმელი მუხუდოს ან ცერცვის შეზავებული ფარშისგან შემწვარ ბურთულებს წარმოადგენს, რომელსაც ხშირად პიტას პურში ჰუმუსთან ერთად მიირთმევენ.",
        "answer": "ფალაფელი (Falafel)",
        "searched_terms": ["ფალაფელი", "Falafel"],
        "fact_note_en": "Falafel is a deep-fried ball or patty made from ground chickpeas, broad beans, or both."
    },
    {
        "slot_id": "1.R1.C4.200",
        "topic": "გემრიელი კითხვები",
        "question": "პერუს ეროვნული კერძი, რომელიც უმი თევზის ან ზღვის პროდუქტების ნაჭრებისგან მზადდება და ციტრუსის (ძირითადად ლაიმის) ახალგამოწურულ წვენში მარინირდება.",
        "answer": "სევიჩე (Ceviche)",
        "searched_terms": ["სევიჩე", "Ceviche"],
        "fact_note_en": "Ceviche is a traditional Peruvian dish made from fresh raw fish cured in citrus juices."
    },
    {
        "slot_id": "1.R1.C4.300",
        "topic": "გემრიელი კითხვები",
        "question": "იაპონურ კულინარიაში სუშისა და ონიგირის შესახვევად გამოყენებული გამომშრალი წითელი წყალმცენარეების მუქი მწვანე თხელი ფირფიტები.",
        "answer": "ნორი (Nori)",
        "searched_terms": ["ნორი", "Nori"],
        "fact_note_en": "Nori is dried edible seaweed sheets used in Japanese cuisine."
    },
    {
        "slot_id": "1.R1.C4.400",
        "topic": "გემრიელი კითხვები",
        "question": "იაპონური კულინარიის ეს ცნობილი მეთოდი — ზღვის პროდუქტებისა და ბოსტნეულის შეწვა ცივ თხელ ცომში — მე-16 საუკუნეში ნაგასაკიში პორტუგალიელმა მისიონერებმა დაამკვიდრეს.",
        "answer": "ტემპურა (Tempura)",
        "searched_terms": ["ტემპურა", "Tempura"],
        "fact_note_en": "Tempura is a Japanese dish introduced by Portuguese missionaries in the 16th century."
    },
    {
        "slot_id": "1.R1.C4.500",
        "topic": "გემრიელი კითხვები",
        "question": "იტალიის ემილია-რომანიას რეგიონის ამ ქალაქში დამზადებული ცნობილი ნედლად გამოყვანილი ლორი (პროშუტო) მხოლოდ ზღვის მარილითა და ჰაერზე გამოშრობით მწიფდება მინიმუმ ერთი წლის განმავლობაში.",
        "answer": "პარმა (პარმის ლორი / Prosciutto di Parma)",
        "searched_terms": ["პარმის ლორ", "პროშუტო"],
        "fact_note_en": "Prosciutto di Parma is dry-cured ham from Parma, Italy."
    },

    # ----------------------------------------------------
    # Topic: ცხოველთა სამყარო
    # ----------------------------------------------------
    {
        "slot_id": "1.R1.C5.100",
        "topic": "ცხოველთა სამყარო",
        "question": "აღმოსავლეთ ავსტრალიის ეს უცნაური ენდემური ძუძუმწოვარი კვერცხს დებს, აქვს იხვისებრი ნისკარტი, თახვისებრი კუდი და მამრებს შხამიანი დეზები.",
        "answer": "იხვნისკარტა (Platypus)",
        "searched_terms": ["იხვნისკარტ", "Platypus"],
        "fact_note_en": "The platypus is a semiaquatic egg-laying mammal endemic to eastern Australia."
    },
    {
        "slot_id": "1.R1.C5.200",
        "topic": "ცხოველთა სამყარო",
        "question": "ცენტრალური აფრიკის კონგოს ჯუნგლებში მობინადრე ეს იშვიათი ცხოველი ფეხებზე ზებრასებრი ზოლებით გამოირჩევა, თუმცა გენეტიკურად ჟირაფის ყველაზე ახლო ნათესავია.",
        "answer": "ოკაპი (Okapi)",
        "searched_terms": ["ოკაპი", "Okapi"],
        "fact_note_en": "The okapi is a giraffid artiodactyl mammal native to the Congo rainforest."
    },
    {
        "slot_id": "1.R1.C5.400",
        "topic": "ცხოველთა სამყარო",
        "question": "აფრიკასა და აზიაში მობინადრე კვერნისებრთა ოჯახის ეს მტაცებელი ცნობილია სქელი კანით, გველის შხამისადმი იმუნიტეტითა და გინესის რეკორდით, როგორც მსოფლიოს ყველაზე უშიშარი ცხოველი.",
        "answer": "თაფლის მაჩვი (Mellivora capensis)",
        "searched_terms": ["თაფლის მაჩვ", "Mellivora capensis"],
        "fact_note_en": "The honey badger is famous for ferocity and venom resistance."
    },
    {
        "slot_id": "1.R1.C5.500",
        "topic": "ცხოველთა სამყარო",
        "question": "ეს უნიკალური ძუძუმწოვარი ერთადერთია მსოფლიოში, რომლის სხეულიც მთლიანად კერატინის მკვრივი, დამცავი ქერცლითაა დაფარული, საფრთხისას კი ბურთივით იკეცება.",
        "answer": "პანგოლინი (Pangolin)",
        "searched_terms": ["პანგოლინ", "Pangolin"],
        "fact_note_en": "The pangolin is the only mammal wholly covered in large keratin scales."
    },

    # ----------------------------------------------------
    # Topic: ქართული კინოს ოქროს ფონდი
    # ----------------------------------------------------
    {
        "slot_id": "1.R1.C6.100",
        "topic": "ქართული კინოს ოქროს ფონდი",
        "question": "მიხეილ ჭიაურელისა და გიორგი შენგელაიას ამ მუსიკალურ კომედიაში კახეთის სოფელში ჩასული მკერავი გოგონა მაყვალა და მძღოლი ბაბულია მთელ სოფელს სიყვარულის მორევში ჩაითრევენ.",
        "answer": "„სიყვარული ყველას უნდა“",
        "searched_terms": ["სიყვარული ყველას უნდა"],
        "fact_note_en": "The 1980 musical comedy Love for Everyone directed by Chiaureli and Shengelaya."
    },
    {
        "slot_id": "1.R1.C6.200",
        "topic": "ქართული კინოს ოქროს ფონდი",
        "question": "შოთა მანაგაძის ამ კომედიაში სოფელ საბუდარიდან ქალაქ რუსთავში მეტალურგიულ ქარხანაში წასული გოგია უშვერიძე სატრფოს — თებროლეს ქალაქში გაჰყვება.",
        "answer": "„საბუდარელი ჭაბუკი“",
        "searched_terms": ["საბუდარელი ჭაბუკი"],
        "fact_note_en": "The 1957 classic comedy The Scrapper (Sabudareli chabuki) directed by Shota Managadze."
    },
    {
        "slot_id": "1.R1.C6.300",
        "topic": "ქართული კინოს ოქროს ფონდი",
        "question": "ყარამან მგელაძის ამ დრამაში სოსო ჯაჭვლიანისა და დოდო აბაშიძის გმირი გიორგი ზაქარეიშვილი საფრანგეთში ემიგრაციაში ცხოვრობს და სიკვდილის წინ შვილიშვილს ქართულს ასწავლის.",
        "answer": "„ფესვები“",
        "searched_terms": ["ფესვები", "გიორგი ზაქარეიშვილი"],
        "fact_note_en": "The 1987 drama Roots (Pesvebi) directed by Karaman Mgeladze."
    },
    {
        "slot_id": "1.R1.C6.400",
        "topic": "ქართული კინოს ოქროს ფონდი",
        "question": "თამაზ მელიავას ამ კომედიაში, რომელიც ქართულ ხალხურ ზღაპარს ეფუძნება, გივი ბერიკაშვილის გმირი თავისი გამჭრიახობითა და ეშმაკობით მდიდარ ვაჭრებსა და მღვდელს აცურებს.",
        "answer": "„ლონდრე“",
        "searched_terms": ["ლონდრე"],
        "fact_note_en": "The 1966 folk comedy Londre directed by Tamaz Meliava starring Givi Berikashvili."
    },

    # ----------------------------------------------------
    # Finals
    # ----------------------------------------------------
    {
        "slot_id": "new.95a",
        "topic": "მეგასტრუქტურები და კოსმოსი",
        "question": "1960 წელს ამერიკელმა თეორიულმა ფიზიკოსმა ფრიმენ დაისონმა წამოაყენა ჰიპოთეტური მეგასტრუქტურის იდეა, რომელიც ვარსკვლავს გარს ეკვრის და მისი ენერგიის მთლიანად აკუმულირებას ახდენს. რა სახელით იცნობენ ამ ასტროინჟინრულ კონცეფციას?",
        "answer": "დაისონის სფერო (Dyson sphere)",
        "searched_terms": ["დაისონის სფერო", "Dyson sphere"],
        "fact_note_en": "Freeman Dyson proposed the concept of the Dyson sphere in 1960."
    },
    {
        "slot_id": "new.95b",
        "topic": "შუა საუკუნეების უცნაური მანია",
        "question": "1518 წლის ივლისში სტრასბურგში ქალბატონმა ტროფეამ მოულოდნელად ქუჩაში ცეკვა დაიწყო. ერთ თვეში მას ასობით ქალაქელი შეუერთდა, რომლებიც შეჩერებას ვერ ახერხებდნენ და ბევრი გამოფიტვისგან დაიღუპა. ისტორიაში ამ იდუმალ მოვლენას სწორედ ეს სახელი შეარქვეს: „... ეპიდემია“.",
        "answer": "საცეკვაო ეპიდემია (Dancing Plague of 1518)",
        "searched_terms": ["საცეკვაო ეპიდემია", "Dancing Plague"],
        "fact_note_en": "The Dancing Plague of 1518 took place in Strasbourg, Holy Roman Empire."
    }
]

payload = {
    "package": 95,
    "clues": clues
}

with open(out_path, 'w', encoding='utf-8') as f:
    json.dump(payload, f, ensure_ascii=False, indent=2)
    f.write('\n')

print(f'Successfully wrote {len(clues)} clues to {out_path}')
