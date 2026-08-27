"""Second pass: keep only rows from categories a human judged genuinely general/
international knowledge, out of the survivors of mine_csv_candidates.py.

The per-row keyword filter in mine_csv_candidates.py catches the obvious markers
(state names, "president", NFL...) but 76% of the archive survived it -- most
categories are generically named ("HISTORY", "POTPOURRI") yet lean heavily on
American civics, sports leagues, and Hollywood-award trivia anyway. This script
applies an explicit category whitelist, reviewed by hand against
data/csv_category_counts.txt, so only domains that are genuinely universal
(world geography/history, science, classical arts, mythology, nature...) feed
the packet-writing prompts. Output is grounding material for a model to verify
and rewrite, not a translation source.

    python src/filter_csv_pool.py

Writes data/csv_grounding_pool.jsonl (category, question, answer, domain).
"""
import json
import os

SRC = os.path.join('data', 'csv_candidates.jsonl')
OUT = os.path.join('data', 'csv_grounding_pool.jsonl')

DOMAINS = {
    'science': {
        'SCIENCE', 'SCIENCE & NATURE', 'BIOLOGY', 'CHEMISTRY', 'PHYSICS',
        'GENERAL SCIENCE', 'PHYSICAL SCIENCE', 'ANATOMY', 'THE BODY HUMAN',
        'THE HUMAN BODY', 'ASTRONOMY', 'THE PLANETS', 'THE SOLAR SYSTEM',
        'CONSTELLATIONS', 'GEOLOGY', 'ROCKS & MINERALS', 'THE ELEMENTS',
        'ZOOLOGY', 'MAMMALS', 'BIRDS', 'INSECTS', 'FISH', 'THE ANIMAL KINGDOM',
        'BOTANY', 'PLANTS', 'PLANTS & TREES', 'TREES', 'FLOWERS',
        'FRUITS & VEGETABLES', 'HERBS & SPICES', 'WEATHER', 'VOLCANOES',
        'MATH', 'MATHEMATICS', 'GEOMETRY', 'ARCHAEOLOGY', 'MEDICINE',
        'HEALTH & MEDICINE', 'TECHNOLOGY', 'INVENTIONS', 'INVENTORS',
        'SCIENTISTS', 'ASTRONOMERS', 'NUCLEAR PHYSICS', 'MARINE BIOLOGY',
        'EARTH SCIENCE', 'LIFE SCIENCE', 'SIMPLE SCIENCE', 'THE EARTH',
        'THE UNIVERSE', 'BASIC SCIENCE', 'SCIENCE CLASS', 'SCIENCE STUFF',
        'DINOSAURS', 'PREHISTORIC TIMES', 'SPACE', 'SPACE EXPLORATION',
        'ANIMAL GROUPS', 'BUGS', 'REPTILES', 'SEA CREATURES', 'PLANT LIFE',
        'MEDICAL HISTORY', 'MEDICAL MILESTONES', 'DISCOVERIES', 'ANTHROPOLOGY',
        'EARLY MAN', 'NATURE', 'NATURE STUDY', 'ENERGY', 'ENGINEERING',
        'SICKNESS & HEALTH', 'HEALTH MATTERS', 'FIRST AID', 'FITNESS',
        'NUTRITION', 'MEN OF SCIENCE', 'THE BRAIN', 'AROUND THE BODY',
        "\"D\" IN SCIENCE", "\"C\" IN SCIENCE", "\"A\" IN SCIENCE",
    },
    'geography': {
        'WORLD GEOGRAPHY', 'WORLD CAPITALS', 'BODIES OF WATER', 'WORLD CITIES',
        'GEOGRAPHY', 'AROUND THE WORLD', 'ISLANDS', 'MOUNTAINS',
        'COUNTRIES OF THE WORLD', 'EUROPE', 'ASIA', 'AFRICA', 'SOUTH AMERICA',
        'EASTERN EUROPE', 'EUROPEAN GEOGRAPHY', 'EUROPEAN CITIES',
        'EUROPEAN CAPITALS', 'ASIAN CAPITALS', 'LAKES & RIVERS', 'RIVERS',
        'DESERTS', 'SEAS', 'PENINSULAS', 'WATERFALLS',
        'NATIONAL PARKS OF THE WORLD', 'WORLD HERITAGE SITES',
        'GEOGRAPHIC TERMS', 'WHERE AM I?', 'ON THE MAP', 'THE LARGEST IN AREA',
        'THE SMALLEST IN AREA', 'THE NORTHERNMOST CAPITAL CITY',
        'CAPITAL CITY BIRTHPLACES', 'TOUGH GEOGRAPHY', '"A" IN GEOGRAPHY',
        'GEOGRAPHY "B"', 'SOUTH OF THE EQUATOR', 'IT BORDERS BOTH',
        'THE MOST POPULOUS NATION', 'SECOND-LARGEST CITIES',
        "COUNTRIES' HIGHEST POINTS", 'NAME THAT COUNTRY', 'PROVINCES',
        'CANADIAN PROVINCES', 'SCOTLAND', 'GREECE', 'EGYPT', 'CHINA',
        'SWITZERLAND', 'MEXICO', 'ENGLAND', 'THE CARIBBEAN', 'WORLD FLAGS',
        'FLAGS', 'FLAGS OF THE WORLD', 'WORLD FACTS', 'WORLD TRAVEL',
        'TRAVEL EUROPE', 'TRAVEL & TOURISM', 'JAPAN', "\"G\"EOGRAPHY",
    },
    'history': {
        'WORLD HISTORY', 'HISTORY', 'ANCIENT HISTORY', 'ANCIENT TIMES',
        'EUROPEAN HISTORY', 'HISTORIC NAMES', 'HISTORIC PEOPLE',
        'PEOPLE IN HISTORY', 'THE MIDDLE AGES', 'ROYALTY', 'BRITISH ROYALTY',
        'RULERS', 'WORLD LEADERS', 'KINGS & QUEENS', 'MONARCHS', 'DYNASTY',
        'EXPLORERS', 'EXPLORATION', 'ANCIENT ROME', 'ANCIENT EGYPT',
        'ANCIENT GREECE', 'ROMANS', 'THE CRUSADES', 'THE RENAISSANCE',
        'THE FRENCH REVOLUTION', 'WORLD WAR I', 'WORLD WAR II',
        'THE KOREAN WAR', 'FRENCH HISTORY', 'RUSSIAN HISTORY',
        'ASIAN HISTORY', 'AFRICAN HISTORY', 'CANADIAN HISTORY',
        'BRITISH HISTORY', 'GREAT BRITS', 'HISTORIC WOMEN', 'WOMEN IN HISTORY',
        'HISTORIC QUOTES', 'HISTORIC DATES', 'TREATIES',
        'MEDALS & DECORATIONS', 'PRIME MINISTERS', 'MODERN HISTORY',
        'THE 16th CENTURY', 'THE 17th CENTURY', 'THE 15th CENTURY',
        'HISTORIC DOCUMENTS', 'BIOGRAPHY', 'AUTOBIOGRAPHIES',
        'FAMOUS FIRSTS', "WOMEN'S FIRSTS", 'BORN FIRST', 'BORN & DIED',
        'THEY USED TO BE IN CHARGE', 'CONTEMPORARIES', 'MILITARY MATTERS',
        'WAR', 'PREHISTORIC TIMES',
    },
    'arts_lit_myth': {
        'LITERATURE', 'SHAKESPEARE', 'OPERA', 'BALLET', 'ART & ARTISTS', 'ART',
        'CLASSICAL MUSIC', 'MYTHOLOGY', 'POETS & POETRY', 'BOOKS & AUTHORS',
        'MUSIC', 'MUSICAL INSTRUMENTS', 'COMPOSERS', 'ARCHITECTURE',
        'THEATRE', 'THEATER', 'ARTISTS', 'NOVELS', 'PLAYS', 'DRAMA', 'DANCE',
        'PHILOSOPHY', 'PHILOSOPHERS', 'SCULPTURE', 'SCULPTORS', 'PAINTERS',
        'PAINTINGS', 'MUSEUMS', 'LANDMARKS', 'FOREIGN WORDS & PHRASES',
        'QUOTATIONS', 'QUOTES', 'FAMOUS QUOTES', 'LITERARY QUOTES',
        'WORLD LITERATURE', 'WORLD LIT', 'WORLD AUTHORS',
        'ENGLISH LITERATURE', 'BRIT LIT', 'BRITISH AUTHORS',
        'BRITISH POETS & POETRY', 'FRENCH LITERATURE', 'FRENCH ART & ARTISTS',
        'FRENCH CUISINE', '19th CENTURY LITERATURE', '19th CENTURY LIT',
        'CHILDRENS LITERATURE', 'LITERARY CHARACTERS', 'PLAYWRIGHTS',
        'MYTHS & LEGENDS', 'GREEK MYTHOLOGY', 'NORSE MYTHOLOGY',
        'MYTHOLOGY & ART', 'WOMEN IN MYTHOLOGY', 'YE GODS!',
        'GILBERT & SULLIVAN', 'SYMPHONIES', 'CONDUCTORS', 'OPERA CHARACTERS',
        'THE DREADED OPERA CATEGORY', 'FUN WITH OPERA', 'MUSIC APPRECIATION',
        'MUSIC CLASS', 'ARTS & CRAFTS', 'THE ARTS', 'DECORATIVE ARTS',
        'DESIGN', 'PHOTOGRAPHY', 'PHOTOGRAPHERS', 'CHURCHES & CATHEDRALS',
        'ARCHITECTS', 'ART HISTORY', 'SAINTS', 'PATRON SAINTS',
        'RELIGIOUS LEADERS', 'RELIGION', 'WORLD RELIGION', 'THE BIBLE',
        'THE OLD TESTAMENT', 'THE NEW TESTAMENT', 'GENESIS',
        'BIBLICAL PEOPLE', 'BIBLICAL QUOTES', 'BOOKS OF THE BIBLE',
        'CHRISTIANITY', 'THE GOOD BOOK', 'READ YOUR BIBLE',
        'RELIGIOUS MATTERS', 'NOVEL CHARACTERS', 'LITERARY LOCALES',
        'LITERARY RELATIVES', 'LITERARY TRANSLATIONS', 'LITERARY TERMS',
        'FIRST NOVELS', 'THEIR FIRST NOVELS', '20th CENTURY NOVELS',
        '20th CENTURY AUTHORS', 'WOMEN AUTHORS', 'WOMEN WRITERS',
        'WOMEN: WRITE ON!', 'AUTHORS', 'AUTHORS & THEIR WORKS',
        'AUTHORS ON AUTHORS', 'NAME THE AUTHOR', 'NOVELS & NOVELISTS',
        'SHORT STORIES', 'SHORT FICTION', 'FICTION', 'NONFICTION',
        'BEST SELLERS', 'BESTSELLERS', 'POETRY', 'POETS', 'NAME THE POET',
        'SONNETS', 'SHAKESPEAREAN CHARACTERS', "SHAKESPEARE'S WOMEN",
        'THE BARD WRITES', '"C" IN SHAKESPEARE', 'MEASURE FOR MEASURE',
        'SCIENCE FICTION',
    },
    'world_culture': {
        'INTERNATIONAL CUISINE', 'INTERNATIONAL FOOD & DRINK', 'FOOD',
        'FOOD & DRINK', 'COOKING', 'WINE', 'FOREIGN CURRENCY', 'WORLD COINS',
        'OFFICIAL LANGUAGES', 'LANGUAGES', 'THE UNITED NATIONS', 'THE U.N.',
        'FOREIGN FILMS', 'MOVIE TITLE TRANSLATIONS',
        'WOMEN OF THE WORLD', 'GEMS & JEWELRY', 'GEMS', 'JEWELRY', 'FASHION',
        'FASHION DESIGNERS', 'FASHION HISTORY', 'MONEY', 'WEIGHTS & MEASURES',
        'APPROXIMATE WEIGHTS & MEASURES', 'SIGNS & SYMBOLS', 'TRANSPORTATION',
        'SHIPS', 'AVIATION', 'THE OLYMPICS', 'THE OLYMPIC GAMES', 'TENNIS',
        'BOXING', 'CARD GAMES', 'TOYS & GAMES', 'GAMES', 'HORSES',
        'NATIONAL ANTHEMS', 'ASTROLOGY', 'SUPERSTITIONS', 'ECONOMICS',
        'PSYCHOLOGY', 'SOCIOLOGY', 'ENVIRONMENT', 'THE ENVIRONMENT',
        'EPONYMS', 'PROVERBS',
    },
}

WHITELIST = set()
for names in DOMAINS.values():
    WHITELIST.update(names)

CATEGORY_TO_DOMAIN = {name: domain for domain, names in DOMAINS.items() for name in names}


def main():
    kept_by_domain = {d: [] for d in DOMAINS}
    total = 0
    with open(SRC, encoding='utf-8') as fh:
        for line in fh:
            row = json.loads(line)
            cat = row['category'].strip()
            if cat not in WHITELIST:
                continue
            total += 1
            domain = CATEGORY_TO_DOMAIN[cat]
            kept_by_domain[domain].append(row)

    with open(OUT, 'w', encoding='utf-8') as out:
        for domain, rows in kept_by_domain.items():
            for row in rows:
                row['domain'] = domain
                out.write(json.dumps(row, ensure_ascii=False) + '\n')

    print(f'{total} rows kept across {len(WHITELIST)} whitelisted categories')
    for domain, rows in kept_by_domain.items():
        cats = len({r["category"] for r in rows})
        print(f'  {domain}: {len(rows)} rows, {cats} categories')
    print(f'-> {OUT}')


if __name__ == '__main__':
    main()
