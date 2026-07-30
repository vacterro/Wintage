import os
import sys

f = "v:/___VAC/__K/__CODE/_PY/_SMART_VAC_CLEANER/_SMART_VAC_CLEANER.py.bak"
with open(f, 'rb') as file:
    b = file.read()
if b.startswith(b'\xef\xbb\xbf'):
    b = b[3:]
text = b.decode('utf-8')

res = bytearray()
for c in text:
    try:
        res.extend(c.encode('cp1251'))
    except UnicodeEncodeError:
        # If it failed to encode, it might be a control char or undefined mapping that was preserved by powershell
        if ord(c) < 256:
            res.append(ord(c))
        else:
            print(f"Warning: Cannot restore character {repr(c)}")
            res.append(ord('?'))

with open("v:/___VAC/__K/__CODE/_PY/_SMART_VAC_CLEANER/_SMART_VAC_CLEANER.py", 'wb') as file:
    file.write(res)
print("Restored SMART VAC CLEANER to original working bytes!")
