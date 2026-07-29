import sys, re

paths = [
    r"V:\___VAC\__P\_TOTALCMD\user\colors\Current.ini",
    r"V:\___VAC\__P\_TOTALCMD2\user\colors\Current.ini"
]

for path in paths:
    encoding_used = 'utf-16le'
    try:
        with open(path, 'r', encoding='utf-16le') as f:
            content = f.read()
    except Exception as e:
        encoding_used = 'windows-1251'
        with open(path, 'r', encoding='windows-1251') as f:
            content = f.read()
    
    # CursorColor to surfaceAlt #634B2B (R=99, G=75, B=43 -> 2837347)
    content = re.sub(r'(?i)(^CursorColor=)\d+', r'\g<1>2837347', content, flags=re.MULTILINE)
    
    # MarkColor to goldStar #FFC107 (R=255, G=193, B=7 -> 508415)
    content = re.sub(r'(?i)(^MarkColor=)\d+', r'\g<1>508415', content, flags=re.MULTILINE)
    
    # CursorText to textPrimary #E2CA95 (R=226, G=202, B=149 -> 9816802)
    content = re.sub(r'(?i)(^CursorText=)\d+', r'\g<1>9816802', content, flags=re.MULTILINE)
    
    try:
        with open(path, 'w', encoding=encoding_used) as f:
            f.write(content)
        print(f"Updated {path} using {encoding_used}")
    except Exception as e:
        print(f"Error on {path}: {e}")

print("TC update done")
