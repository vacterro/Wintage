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
    
    content = re.sub(r'(?i)(^BackColor=)\d+', r'\g<1>1187892', content, flags=re.MULTILINE)
    content = re.sub(r'(?i)(^BackColor2=)\d+', r'\g<1>1782858', content, flags=re.MULTILINE)
    content = re.sub(r'(?i)(^ForeColor=)\d+', r'\g<1>9816802', content, flags=re.MULTILINE)
    content = re.sub(r'(?i)(^MarkColor=)\d+', r'\g<1>7252933', content, flags=re.MULTILINE)
    content = re.sub(r'(?i)(^CursorColor=)\d+', r'\g<1>2376538', content, flags=re.MULTILINE)
    content = re.sub(r'(?i)(^CursorText=)\d+', r'\g<1>9816802', content, flags=re.MULTILINE)
    
    try:
        with open(path, 'w', encoding=encoding_used) as f:
            f.write(content)
        print(f"Updated {path} using {encoding_used}")
    except Exception as e:
        print(f"Error on {path}: {e}")

print("TC update done")
