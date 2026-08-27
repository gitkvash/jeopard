"""The fact-check corrections applied to the generated packets, with reasons.

Kept in the repository rather than run once and thrown away: it is the record of
what was changed in machine-written content and why. Each entry names the clue by
(packet, round, topic, value) and carries the finding that prompted the edit, so a
disputed correction can be argued with.

Re-running it is harmless -- it sets the same text again.

    python src/apply_factcheck_fixes.py
    python src/validate_packets.py --against data/pilot.json data/agy_packets/*.json

The findings came from asking Gemini 3.1 Pro (through the `agy` CLI) to attack the
output it had just written, then checking each claim by hand before accepting it.
Two were rejected as unproven and handled by removing the contested claim from the
clue instead: whether bison have been reintroduced in Borjomi-Kharagauli, and which
institution the characters in `შერეკილები` escape from.
"""
import json

# (packet, round, topic, value, new_question|None, new_answer|None, why)
PATCHES = [
    # ---------------- packet 07 ----------------
    ('07', 1, 'გეოგრაფიული ტერმინები', 20,
     'უდაბნოში, მიწისქვეშა წყლების ზედაპირზე გამოსვლის შედეგად წარმოქმნილ, '
     'მცენარეულობით მდიდარ ამ ადგილს ხშირად უდაბნოს კუნძულს უწოდებენ.',
     None, 'oasis does not mean "island" in Arabic (jazira does); the word is '
     'Egyptian by way of Greek'),

    ('07', 1, 'ქართული სამზარეულო', 30,
     'რაჭული სამზარეულოს ეს გამორჩეული კერძი პარკოსანი მცენარის შიგთავსიან '
     'ცომეულს წარმოადგენს და განსაკუთრებით ზამთრის დღესასწაულებზე მზადდება.',
     None, 'traditional Rachan lobiani is round, not square'),

    ('07', 1, 'ჭადრაკი', 30,
     'ეს ლეგენდარული ქართველი მოჭადრაკე ქალი 16 წლის განმავლობაში ინარჩუნებდა '
     'მსოფლიო ჩემპიონის ტიტულს და პირველი ქალი გახდა, რომელსაც საერთაშორისო '
     'გროსმაისტერის წოდება მიენიჭა.',
     None, 'Vera Menchik was the first womens world champion; Gaprindashvili was '
     'the first woman awarded the grandmaster title'),

    ('07', 2, 'მწვერვალები და ქედები', 40,
     'ევროპისა და აზიის გამყოფი ეს მთათა სისტემა ჩრდილოეთიდან სამხრეთისკენ '
     '2000 კილომეტრზე მეტ მანძილზეა გადაჭიმული და რუსეთის ტერიტორიაზე მდებარეობს.',
     None, 'the Urals divide the continents rather than connect them'),

    ('07', 2, 'ცნობილი მეტსახელები', 80,
     '1986 წლის მსოფლიო ჩემპიონატზე დიეგო მარადონამ ინგლისის ნაკრებთან მატჩში '
     'ხელით გაიტანა გოლი, რომელიც თავად მარადონას სიტყვების შემდეგ ისტორიაში '
     'ამ სახელით შევიდა.',
     None, '"Hand of God" names the goal, not the player, and Maradona coined it'),

    ('07', 2, 'ცნობილი მეტსახელები', 60,
     'რომის ამ იმპერატორს, რომელიც ისტორიაში სისასტიკით შევიდა, მეტსახელი '
     'ბავშვობიდან შერჩა — მამის ჯარში ის პატარა სამხედრო ჩექმებს ატარებდა.',
     None, 'the original clause read as a word-for-word translation'),

    ('07', 3, 'ცნობილი ცხოველები', 30,
     '1957 წელს საბჭოთა ხომალდით „სპუტნიკ-2“ დედამიწის ორბიტაზე გაგზავნეს ეს '
     'ძაღლი — პირველი ცოცხალი არსება, რომელმაც ორბიტაზე იმოგზაურა.',
     None, 'flies and monkeys reached space before Laika; she was first to orbit'),

    ('07', 3, 'ცნობილი ცხოველები', 150,
     'ძველი რომის დაარსების ლეგენდაში მნიშვნელოვან როლს ასრულებს ეს ცხოველი, '
     'რომელმაც პალატინის ბორცვის ძირას ტყუპი ძმები საკუთარი რძით გამოკვება.',
     None, 'the Lupercal cave is at the foot of the Palatine, not the Capitoline'),

    ('07', 3, 'ცნობილი ცხოველები', 120,
     '1925 წელს ალასკაზე დიფტერიის ეპიდემიის დროს მარხილის ძაღლების ამ ლიდერმა '
     'შრატის მიტანაში გადამწყვეტი როლი ითამაშა, რისთვისაც ნიუ-იორკში ძეგლი დაუდგეს.',
     None, '"სახელად ამ ძაღლმა" was a literal rendering of an English template'),

    ('07', 3, 'ჩაი და ყავა', 150,
     'ყავის მოხარშვის ეს ტრადიციული მოწყობილობა, რომელსაც ხშირად სპილენძისგან '
     'ამზადებენ და გრძელი ტარი აქვს, ახლო აღმოსავლეთსა და საქართველოშიც '
     'ფართოდ გამოიყენება.',
     None, 'a cezve brews coffee; it does not roast beans'),

    # ---------------- packet 08 ----------------
    ('08', 1, 'ფრინველთა სამყარო', 20,
     'ამ ფრინველს, რომელიც ახალი ზელანდიის ეროვნულ სიმბოლოს წარმოადგენს, თითქმის '
     'შეუმჩნეველი, ჩამოკლებული ფრთები აქვს, ვერ დაფრინავს და მისი ბუმბული უფრო ბეწვს წააგავს.',
     None, 'kiwis have vestigial wings; "no wings" is false'),

    ('08', 1, 'კლასიკური ფიზიკა', 50,
     '1851 წელს პარიზის პანთეონში ჩატარებულმა ცდამ, გრძელ ძაფზე დაკიდებული მასიური '
     'ბირთვის რხევის სიბრტყის ნელი შემობრუნებით, პირველად თვალსაჩინოდ დაამტკიცა '
     'დედამიწის ღერძული ბრუნვა. ვისი სახელი ჰქვია ამ ქანქარას?',
     'ლეონ ფუკო (ფუკოს ქანქარა)',
     'the uncertainty principle is quantum, not classical physics -- replaced with a '
     'classical-mechanics clue of the same difficulty'),

    ('08', 2, 'კავკასიური ფლორა და ფაუნა', 40,
     'ევროპული ბიზონის კავკასიური ნათესავი, ეს მსხვილი ჩლიქოსანი, მეოცე საუკუნის '
     'დასაწყისში კავკასიის ბუნებაში მთლიანად გაანადგურეს.',
     None, 'the claim that it was reintroduced in Borjomi-Kharagauli is not established'),

    ('08', 2, 'მეტეოროლოგია', 20,
     'ატმოსფერული ნალექების ეს სახეობა მძლავრ გროვა-წვიმის ღრუბლებში წარმოიქმნება, '
     'სადაც აღმავალი ჰაერის ნაკადები წყლის წვეთებს ცივ ზონაში აიტაცებს და ყინულის '
     'ბურთულებად აქცევს.',
     None, 'the mechanism described was sleet, not hail'),

    ('08', 2, 'დიდი ეპიდემიები', 80,
     '1980-იან წლებში აღმოჩენილმა ამ ვირუსმა გლობალური პანდემია გამოიწვია. მის მიერ '
     'გამოწვეულ დაავადებას აკრონიმით მოიხსენიებენ.',
     'აივ (HIV)', 'the question asks for the virus but the answer named the disease'),

    ('08', 3, 'ავიაციის ისტორია', 90,
     '1927 წელს ამერიკელმა ჩარლზ ლინდბერგმა ისტორიაში პირველმა, მარტომ და '
     'შეუჩერებლად გადაუფრინა ამ ოკეანეს და ნიუ-იორკიდან პარიზში ჩავიდა.',
     None, 'Alcock and Brown flew the Atlantic non-stop in 1919; Lindbergh was first solo'),

    ('08', 3, 'ქართველი მეცნიერები', 60,
     '1963 წელს ლენინის პრემია მიიღო ამ ქართველმა მათემატიკოსმა და მექანიკოსმა, '
     'რომელიც სიცოცხლის ბოლო წლებში საქართველოს მეცნიერებათა აკადემიის პრეზიდენტი '
     'იყო. მისი სახელობისაა გამოყენებითი მათემატიკის ინსტიტუტი.',
     None, 'Vekua died in 1977, so a 1984 Lenin Prize is impossible; his was 1963'),

    ('08', 1, 'მზის სისტემის ირგვლივ', 10,
     'ის ჩვენი მზის სისტემის ყველაზე დიდი პლანეტაა. მისი მასა ორჯერზე მეტად '
     'აღემატება ყველა დანარჩენი პლანეტის მასათა ჯამს.',
     None, '"orjer da kidev ufro metad" read as a literal translation'),

    ('08', 3, 'ციფრები და მუდმივები', 150,
     'ორის კვადრატულ ფესვს ამ ცნობილი ძველბერძენი მათემატიკოსისა და ფილოსოფოსის '
     'მუდმივას უწოდებენ. ითვლება, რომ სწორედ მისმა სკოლამ დაამტკიცა ამ რიცხვის '
     'ირაციონალურობა.',
     None, 'case-agreement error: "kvadratuli fesvs"'),

    ('08', 3, 'ვულკანები და მიწისძვრები', 150,
     'დედამიწის ქერქსა და მანტიას შორის არსებული საზღვარი, სადაც სეისმური ტალღების '
     'სიჩქარე მკვეთრად იცვლება, ამ ხორვატი სეისმოლოგის სახელს ატარებს.',
     None, '"ewodeba misi saxeli" read as a literal translation'),

    # ---------------- packet 09 ----------------
    ('09', 1, 'ქართული ხუროთმოძღვრება', 50,
     'თბილისის ძველ უბანში მდებარე ეს ისტორიული ციხესიმაგრე, რომლის სახელიც '
     '„მცირე ციხეს“ ნიშნავს, დედაქალაქის ერთ-ერთი მთავარი დომინანტია.',
     None, 'Narin Qala means "small/inner fortress", not "inaccessible fortress"'),

    ('09', 2, 'მუნჯი კინო', 40,
     'ძმები ლუმიერების 1896 წელს ნაჩვენები ერთ-ერთი პირველი ფილმი მაყურებელში '
     'პანიკას იწვევდა, რადგან ეკრანიდან მათკენ ეს სატრანსპორტო საშუალება მოემართებოდა.',
     None, '"Arrival of a Train" was not in the December 1895 programme; it premiered in 1896'),

    ('09', 3, 'ქართული კინოს კლასიკა', 30,
     'თენგიზ აბულაძის ტრილოგიის ეს ბოლო ფილმი, რომელიც 1984 წელს შეიქმნა და '
     'ტოტალიტარულ რეჟიმს ამხელს, სრულდება კითხვით — ტაძრამდე მიდის თუ არა ეს გზა.',
     None, 'the closing line was misquoted; the clue no longer asserts exact wording'),

    ('09', 3, 'ქართული კინოს კლასიკა', 120,
     'ელდარ შენგელაიას ამ სატირულ კომედიაში მთავარი გმირები, ქრისტეფორე და ერტაოზი, '
     'საკუთარი ხელით აგებული საჰაერო ხომალდით გაფრენას ახერხებენ.',
     None, 'the institution they escape from was misdescribed; the claim is removed'),

    ('09', 3, 'ვეფხისტყაოსანი', 90,
     'ასე ჰქვია ავთანდილის ერთგულ მსახურს, რომელსაც ის ტარიელის საძებრად წასვლის '
     'წინ ანდერძს უტოვებს.',
     None, 'Shermadin stays behind in Arabia; he is not a travelling companion'),

    ('09', 1, 'მსოფლიოს მუზეუმები', 10,
     'პარიზში მდებარე ეს უდიდესი ხელოვნების მუზეუმი, რომელიც წარსულში საფრანგეთის '
     'მეფეთა სასახლე იყო, ლეონარდო და ვინჩის „მონა ლიზას“ ინახავს.',
     None, '"is home to" calque'),

    ('09', 1, 'პირველი ფრაზები', 50,
     '„ეს იყო საუკეთესო დრო, ეს იყო ყველაზე ცუდი დრო...“ — ასე იწყება ჩარლზ დიკენსის '
     'ეს ისტორიული რომანი, რომლის მოქმედება ლონდონსა და პარიზში მიმდინარეობს.',
     None, 'a comparative was used where the original is superlative'),

    # ---------------- packet 10 ----------------
    ('10', 1, 'ჰერალდიკა', 50,
     'ორთავიანი არწივის სიმბოლო ფართოდ გავრცელდა ბიზანტიაში, ხოლო XV საუკუნეში ის '
     'საღვთო რომის ამ იმპერატორმა საკუთარ გერბზე ოფიციალურად დაამტკიცა.',
     None, 'the double-headed eagle predates Byzantium (Hittite and Mesopotamian art)'),

    ('10', 2, 'ძველი კოლხეთი და იბერია', 60,
     'ეს ბერძენი გეოგრაფოსი და ისტორიკოსი თავის ნაშრომში „გეოგრაფია“ დაწვრილებით '
     'აღწერს კოლხეთის ეკონომიკას, სანაოსნო მდინარეებსა და ოთხ სოციალურ ფენას იბერიაში.',
     None, 'Strabo was Greek, not Roman'),

    ('10', 2, 'ეტიმოლოგია და მკვდარი ენები', 40,
     'შუმერული და აქადური ტექსტების ჩასაწერად გამოყენებული ეს სისტემა თავისი ნიშნების '
     'ფორმის გამო ლათინური სიტყვისგან cuneus („სოლი“) იღებს საერთაშორისო სახელს.',
     None, '"Cuneiform" is a modern coinage from Latin cuneus, not a Latin name'),

    ('10', 2, 'ისტორიული ტიტულები', 100,
     'ძველ ეგვიპტეში ფარაონის კარზე არსებული ეს უმაღლესი სამოქალაქო თანამდებობა '
     'ქვეყნის მთელ ადმინისტრაციას ხელმძღვანელობდა; დღეს მას ხშირად ვეზირს უწოდებენ.',
     None, 'the stated etymology of tjaty is not established'),

    ('10', 3, 'ქართული ქრონიკები', 90,
     'ლეონტი მროველის თხზულების მიხედვით, ქართველთა და კავკასიის სხვა ხალხების '
     'ეთნარქად მიიჩნევა იაფეთის ეს შვილიშვილი, თარშისის ძე.',
     None, 'in Kartlis Tskhovreba Targamos is the son of Tarshis; he *is* the biblical Togarmah'),

    ('10', 1, 'ჰერალდიკა', 20,
     'ბრიტანეთის სამეფო გერბზე ეს ცხოველი, ინგლისის სიმბოლო, შოტლანდიის სიმბოლო '
     'ერთრქასთან (უნიკორნთან) ერთად არის გამოსახული.',
     None, '"martorqa" means rhinoceros in modern Georgian, not unicorn'),

    ('10', 1, 'ბიზანტიის იმპერატორები', 30,
     'ბულგარელთა სასტიკად დამარცხების გამო მაკედონური დინასტიის ამ წარმომადგენელს '
     '„ბულგართმმუსვრელი“ უწოდეს.',
     None, '"sastiki gamarjveba" is an unnatural calque'),
]


def main() -> None:
    by_packet: dict[str, list] = {}
    for patch in PATCHES:
        by_packet.setdefault(patch[0], []).append(patch)

    for packet, items in sorted(by_packet.items()):
        path = f'data/agy_packets/packet_{packet}.json'
        with open(path, encoding='utf-8') as fh:
            doc = json.load(fh)
        print(f'--- packet {packet}')
        for _, ri, topic_name, value, new_q, new_a, why in items:
            topic = next(t for t in doc['rounds'][ri - 1]['topics']
                         if t['name'] == topic_name)
            clue = next(c for c in topic['clues'] if c['value'] == value)
            if new_q:
                clue['question'] = new_q
            if new_a:
                clue['answer'] = new_a
            print(f'  R{ri} | {topic_name} | {value}: {why}')
        with open(path, 'w', encoding='utf-8') as fh:
            json.dump(doc, fh, ensure_ascii=False, indent=2)
            fh.write('\n')

    print(f'\n{len(PATCHES)} clues corrected across {len(by_packet)} packets')


if __name__ == '__main__':
    main()
