"""
Linguistic Filter for Jeopardy Questions
Detects questions that rely on English-specific wordplay, spelling, rhymes, letter counts, etc.
"""
import re

RULES = [
    # 1. Letter count categories (e.g., "3-LETTER WORDS", "4-LETTER WORDS", "5-LETTER WORDS")
    (
        re.compile(r'\b\d+[- ]LETTER\b|\b[A-Z]+[- ]LETTER\b|\bFIVE[- ]LETTER\b|\bFOUR[- ]LETTER\b|\bTHREE[- ]LETTER\b|\bSIX[- ]LETTER\b|\bSEVEN[- ]LETTER\b|\bEIGHT[- ]LETTER\b', re.IGNORECASE),
        "არა",
        "კატეგორია ეფუძნება ინგლისურ სიტყვაში ასოების რაოდენობას"
    ),
    # 2. Before & After wordplay
    (
        re.compile(r'BEFORE\s*&\s*AFTER|BEFORE\s+AND\s+AFTER', re.IGNORECASE),
        "არა",
        "სიტყვათა თამაში (Before & After) — ორი ინგლისური ფრაზის შერწყმა საერთო სიტყვით"
    ),
    # 3. Rhymes
    (
        re.compile(r'\bRHYME\b|\bRHYMES\b|\bRHYMING\b|RHYME\s+TIME|RHYME\s+PATROL', re.IGNORECASE),
        "არა",
        "კატეგორია/კითხვა აგებულია ინგლისურ რითმაზე"
    ),
    # 4. Anagrams
    (
        re.compile(r'\bANAGRAM\b|\bANAGRAMS\b', re.IGNORECASE),
        "არა",
        "ინგლისური ანაგრამა (ასოების გადაადგილებით მიღებული სიტყვა)"
    ),
    # 5. Homophones & Homonyms
    (
        re.compile(r'\bHOMOPHONE\b|\bHOMOPHONES\b|\bHOMONYM\b|\bHOMONYMS\b|\bSOUNDS\s+LIKE\b', re.IGNORECASE),
        "არა",
        "ჰომოფონები — სიტყვები, რომლებიც ინგლისურად ერთნაირად ჟღერს"
    ),
    # 6. Palindromes
    (
        re.compile(r'\bPALINDROME\b|\bPALINDROMES\b', re.IGNORECASE),
        "არა",
        "პალინდრომი — ინგლისური სიტყვა/ფრაზა, რომელიც წაღმა-უკუღმა ერთნაირად იკითხება"
    ),
    # 7. Spoonerisms
    (
        re.compile(r'\bSPOONERISM\b|\bSPOONERISMS\b', re.IGNORECASE),
        "არა",
        "სპუნერიზმი — ინგლისურ ბგერათა/ასოთა შეცვლა სახალისო ეფექტისთვის"
    ),
    # 8. Spelling, Alphabet, and Starts/Ends with
    (
        re.compile(r'STARTS\s+WITH|ENDS\s+WITH|ENDS\s+IN|BEGINS\s+WITH|STARTS\s*&\s*ENDS|BEGINS\s*&\s*ENDS', re.IGNORECASE),
        "არა",
        "კატეგორია მოითხოვს კონკრეტული ინგლისური ასოთი დაწყებას ან დაბოლოებას"
    ),
    (
        re.compile(r'\bSPELL\s+IT\b|\bSPELLING\b|\bSPELL\b|\bSPELL\s+OUT\b', re.IGNORECASE),
        "არა",
        "ინგლისური სიტყვის ორთოგრაფია/დამარცვლა (Spelling)"
    ),
    (
        re.compile(r'\"[A-Z]\"\s+IN\s+COMMON|DOUBLE\s+\"[A-Z]\"|DOUBLE\s+[A-Z]\b|ALLITERATION', re.IGNORECASE),
        "არა",
        "ინგლისური ასოების კანონზომიერება ან ალიტერაცია"
    ),
    # 9. Crossword clues
    (
        re.compile(r'CROSSWORD\s+CLUES|CROSSWORD\s+CLUE', re.IGNORECASE),
        "ნაწილობრივ",
        "კროსვორდის მინიშნება (ხშირად მითითებულია ინგლისური ასოების რაოდენობა)"
    ),
    # 10. Puns & Wordplay
    (
        re.compile(r'\bPUNS\b|\bPUNNY\b|\bWORD\s+PLAY\b|\bWORDPLAY\b|\bPLAY\s+ON\s+WORDS\b', re.IGNORECASE),
        "არა",
        "ინგლისური სიტყვების თამაში / კალამბური (Puns)"
    ),
    # 11. Stupid answers
    (
        re.compile(r'STUPID\s+ANSWERS', re.IGNORECASE),
        "ნაწილობრივ",
        "პასუხი თავად კითხვაშია ჩადებული (ინგლისურ ფორმულირებაზეა დამოკიდებული)"
    ),
    # 12. Word origins / Etymology
    (
        re.compile(r'WORD\s+ORIGINS|ETYMOLOGY', re.IGNORECASE),
        "ნაწილობრივ",
        "ინგლისური სიტყვის წარმოშობა / ეტიმოლოგია (საჭიროებს ენობრივ კონტექსტს)"
    )
]

def analyze_adaptability(category: str, question: str, answer: str) -> tuple[str, str]:
    """
    Analyzes a Jeopardy question to determine if it is adaptable to Georgian.
    Returns:
        (is_adaptable, reason)
        where is_adaptable is "კი", "არა", or "ნაწილობრივ"
        and reason is a descriptive Georgian explanation.
    """
    category = category or ""
    question = question or ""
    answer = answer or ""

    for pattern, status, reason in RULES:
        if pattern.search(category):
            return status, reason
        if pattern.search(question) and status == "არა":
            return status, reason

    # Check for quotes with single letters indicating spelling clues like "starts with a 'Q'"
    if re.search(r'\bstarts with (an? )?[\'\"][a-z][\'\"]|\bends with (an? )?[\'\"][a-z][\'\"]', question, re.I):
        return "არა", "კითხვა მოითხოვს კონკრეტული ინგლისური ასოთი დაწყებას ან დაბოლოებას"

    if re.search(r'\b\d+-letter word\b', question, re.I):
        return "არა", "კითხვაში მითითებულია ინგლისური სიტყვის ასოთა რაოდენობა"

    return "კი", "სრულად თავსებადია ქართულ ენაზე"


if __name__ == "__main__":
    import sys
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass
    test_cases = [
        ("3-LETTER WORDS", "In the title of an Aesop fable, this insect shared billing with a grasshopper", "the ant"),
        ("BEFORE & AFTER", "Popular game show hosted by Pat Sajak that lists the top 500 companies", "Wheel of Fortune 500"),
        ("RHYME TIME", "A heavy wooden hammer for Sally", "Sally's mallet"),
        ("HISTORY", "For the last 8 years of his life, Galileo was under house arrest for espousing this man's theory", "Copernicus"),
        ("SCIENCE", "This element with atomic number 1 is the most abundant in the universe", "Hydrogen"),
        ("CROSSWORD CLUES 'C'", "Feline pet (3)", "Cat"),
    ]

    for cat, q, a in test_cases:
        status, reason = analyze_adaptability(cat, q, a)
        print(f"[{status}] {cat} -> {reason}")
