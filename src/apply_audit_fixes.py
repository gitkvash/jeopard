"""Fixes found by the independent audit of the generated packets, with reasons.

The earlier fact-check was the authoring model reviewing its own work, which
shares its blind spots. This round put two models that did *not* write the
content over the same files, read-only (`src/audit_findings.py` collects and
cross-references what they reported).

What the two auditors were worth could not be more different:

  Claude Opus 4.6   14 findings over packages 07-10; 11 held up on inspection.
                    Real errors that had survived the self-review: Van Gogh's
                    left ear called the right one, Tariel's killing of the
                    Khwarezmian suitor attributed to Nestan, the Bauhaus dated
                    to the 1920s, an emperor penguin laying its egg "directly on
                    the ice" in a clue that then says the male holds it on his
                    feet.
  GPT-OSS 120B      33 findings over packages 07-12; **none** survived. It
                    cannot read Georgian reliably: it reported that წყალბადი is
                    not hydrogen, that Pharasmanes I and II never existed, that
                    a clue naming ბოტსვანა said Bhutan, and it read მარხილი
                    (sled) as "marmot". Three findings pointed at a (round,
                    value) pair that does not exist in the file. Acting on any
                    of them would have introduced errors into correct clues.

So every edit below traces to the Opus audit and to a check of the clue text by
hand. The two Opus findings not applied are recorded at the bottom.

Re-running is harmless -- it sets the same text again.

    python src/apply_audit_fixes.py
    python src/validate_packets.py --against data/pilot.json data/agy_packets/*.json
"""

import json

# (packet, round, topic, value, new_question|None, new_answer|None, why)
FIXES = [
    ('07', 1, 'მსოფლიო ვალუტები', 20,
     'დიდი ბრიტანეთის ოფიციალური ვალუტის დასახელება მომდინარეობს წონის უძველესი '
     'საზომი ერთეულიდან, რომლითაც ვერცხლს ზომავდნენ.',
     None,
     'the pound sterling is named after a pound of silver (the Tower pound, about '
     '350 g); 453 g is the modern avoirdupois pound, a different unit'),

    ('07', 1, 'დროის საზომები', 50,
     'საფრანგეთის რესპუბლიკურ კალენდარში, რომლის ათვლაც 1792 წლიდან იწყებოდა, '
     'კვირის ნაცვლად გამოიყენებოდა დროის ეს ათდღიანი მონაკვეთი.',
     None,
     'the calendar was adopted in October 1793; 1792 is where its era begins, not '
     'when it was introduced'),

    ('08', 1, 'ხეები და მცენარეები', 10,
     'ეს სწრაფად მზარდი მცენარე ავსტრალიის სიმბოლოა და კოალების მთავარ საკვებს '
     'წარმოადგენს.',
     None,
     'bamboo is a grass, and several trees (Paulownia, hybrid poplar) outgrow '
     'eucalyptus -- the superlative does not hold'),

    ('08', 1, 'ფრინველთა სამყარო', 30,
     'ანტარქტიდის ეს ბინადარი ერთადერთი ფრინველია, რომელიც კვერცხს ზამთრის სუსხში '
     'დებს, ხოლო მამალი მას ფეხებზე მოთავსებულს, საკუთარი სხეულის სითბოთი ათბობს.',
     None,
     'the clue contradicted itself: the egg never touches the ice, which is why '
     'the male holds it on his feet'),

    ('08', 1, 'მედიცინის ისტორიიდან', 30,
     '1846 წელს ბოსტონელმა დანტისტმა უილიამ მორტონმა საჯაროდ გამოიყენა ეს '
     'ნივთიერება ოპერაციის უმტკივნეულოდ ჩატარებისთვის, რაც თანამედროვე ანესთეზიის '
     'დასაწყისად ითვლება.',
     None,
     'what is counted as the beginning of modern anaesthesia is the public '
     'demonstration of 16 October 1846 -- a tumour operation, not a tooth'),

    ('09', 2, 'არქიტექტურული სტილები', 100,
     '1919 წელს ვაიმარში დაფუძნებული ეს არქიტექტურული და დიზაინერული სკოლა, '
     'რომლის დამფუძნებელიც ვალტერ გროპიუსი იყო, ფუნქციონალიზმისა და მინიმალიზმის '
     'პრინციპებს ეფუძნებოდა.',
     None,
     'Gropius founded the Bauhaus in April 1919, not in the 1920s'),

    ('09', 3, 'ცნობილი პორტრეტები', 120,
     'ამ ჰოლანდიელმა პოსტიმპრესიონისტმა მხატვარმა საკუთარი ავტოპორტრეტი '
     'ყურშეხვეულმა მას შემდეგ დახატა, რაც კოლეგა მხატვარ პოლ გოგენთან კამათის '
     'შემდეგ მარცხენა ყურის ნაწილი მოიჭრა.',
     None,
     'van Gogh cut his left ear; the self-portrait shows the right side because a '
     'mirror was used'),

    ('09', 3, 'ვეფხისტყაოსანი', 120,
     'ნესტან-დარეჯანის გამზრდელი და მეფე ფარსადანის და, რომელიც ხვარაზმელი '
     'სასიძოს მოკვლის შემდეგ ქალიშვილს სცემს და ზღვაში გადააგდებს, რის შემდეგაც '
     'თავს იკლავს.',
     None,
     'in the poem Tariel kills the suitor, at Nestan-Darejan\'s urging; the deed '
     'was attributed to her'),

    ('09', 1, 'ნიკო ფიროსმანი', 50,
     '1912 წელს ძმებმა ზდანევიჩებმა და ამ ფრანგული წარმოშობის მხატვარმა '
     'პირველებმა აღმოაჩინეს ფიროსმანის ნიჭი და მოგვიანებით მისი ნახატები '
     'მოსკოვში გამოფინეს.',
     None,
     'the discovery was 1912 but the Moscow "Target" exhibition was 1913; the clue '
     'put both in the same year'),

    ('10', 1, 'ჰერალდიკა', 50, None,
     'სიგიზმუნდ ლუქსემბურგელი',
     'the emperor who adopted the double-headed eagle is Sigismund of Luxembourg, '
     'the only emperor of that name and so never numbered; "Sigismund I" is the '
     'Polish king'),

    # Found by my own review pass over the clues src/risky_clues.py ranks as
    # easiest to get wrong, not by either auditor.
    ('22', 3, 'ეგზოპლანეტები', 150,
     '1995 წელს მიშელ მაიორმა და დიდიე კელომ აღმოაჩინეს პირველი ეგზოპლანეტა მზის '
     'მსგავსი ვარსკვლავის გარშემო. რომელ თანავარსკვლავედში მდებარეობს ეს ვარსკვლავი '
     '(ნომრით 51), რომელიც მითოლოგიური მფრინავი ცხენის სახელს ატარებს?',
     None,
     '51 Pegasi b was the first exoplanet found around a Sun-like star; planets '
     'around the pulsar PSR B1257+12 were confirmed in 1992'),

    ('10', 3, 'ქართული ქრონიკები', 150,
     'შუა საუკუნეების ამ ისტორიკოსმა შექმნა თხზულება „ცხოვრება ვახტანგ '
     'გორგასლისა“, რომელიც შემდგომში საქართველოს ისტორიის მთავარ კრებულში შევიდა.',
     None,
     'the dating of Juansher Juansheriani is disputed -- traditionally the 8th '
     'century, by some scholars the 11th; the clue asserted the 11th as settled'),
]

# Reported by Opus but deliberately not applied:
#   #07 R2 მწვერვალები და ქედები 20 (low confidence) -- Everest at 8848 m is the
#       long-standing figure; the 2020 remeasurement of 8848.86 m does not make it
#       wrong.
#   #08 R2 კავკასიური ფლორა და ფაუნა 60 (medium) -- calling Nordmann a botanist
#       rather than a zoologist is loose but not false of a describing naturalist.
#   #07 R1 მსოფლიო ვალუტები 50 (medium) -- the Witwatersrand is a ridge rather
#       than a mountain range; too fine a distinction to be worth a rewrite.
#
# Known and left alone: packages 22 and 30 both end up on 51 Pegasi / Pegasus,
# worded differently enough that the duplicate check does not catch it. Two
# packages that are unlikely to be played together, so not worth authoring a
# replacement clue over.


def main() -> None:
    by_packet: dict[str, list] = {}
    for fix in FIXES:
        by_packet.setdefault(fix[0], []).append(fix)

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

    print(f'\n{len(FIXES)} clues corrected across {len(by_packet)} packets')


if __name__ == '__main__':
    main()
